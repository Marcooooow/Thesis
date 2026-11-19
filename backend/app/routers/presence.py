from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from datetime import datetime, timezone
from typing import List, Optional

from ..models import User, OrganizationMembership, Profile, WorkSession, Break, UserSettings
from ..models_presence import UserPresence
from ..auth.security import get_current_active_user, get_current_admin_user, get_current_manager_user, get_current_employee_user
from ..database import get_db

router = APIRouter(
    prefix="/presence",
    tags=["presence"],
    responses={404: {"description": "Not found"}},
)

# Heartbeat expiration time (30 seconds)
HEARTBEAT_EXPIRY_SECONDS = 30


def compute_user_presence_status(db: Session, target_user_id) -> dict:
    """Helper to compute deterministic presence status and state mode for a user."""
    try:
        presence = db.query(UserPresence).filter(UserPresence.user_id == target_user_id).first()
    except Exception:
        presence = None

    try:
        user_settings = db.query(UserSettings).filter(UserSettings.user_id == target_user_id).first()
    except Exception:
        user_settings = None

    is_dnd = getattr(user_settings, 'do_not_disturb', False)

    if not presence or not presence.is_online:
        return {
            "user_id": str(target_user_id),
            "is_online": False,
            "status_mode": "OFFLINE",
            "is_dnd": is_dnd,
            "last_heartbeat": presence.last_heartbeat.isoformat() if presence and presence.last_heartbeat else None,
            "updated_at": presence.updated_at.isoformat() if presence and presence.updated_at else None
        }

    status_mode = "OFFLINE"
    is_online = True
    last_heartbeat = presence.last_heartbeat
    updated_at = presence.updated_at

    try:
        profile = db.query(Profile).filter(Profile.user_id == target_user_id).first()
    except Exception:
        profile = None

    now = datetime.now(timezone.utc)

    if profile:
        try:
            active_session = db.query(WorkSession).filter(
                WorkSession.profile_id == profile.id,
                WorkSession.ended_at.is_(None)
            ).first()
        except Exception:
            active_session = None

        if active_session:
            try:
                active_break = db.query(Break).filter(
                    Break.work_session_id == active_session.id,
                    Break.ended_at.is_(None)
                ).first()
            except Exception:
                active_break = None

            if active_break:
                b_type = (active_break.break_type or "").upper()
                if b_type in ("LUNCH", "MEAL"):
                    status_mode = "MEAL"
                else:
                    status_mode = "BREAK"
            else:
                if presence and presence.last_heartbeat:
                    age = (now - presence.last_heartbeat).total_seconds()
                    if age <= 30:
                        is_online = True
                        status_mode = "DND" if is_dnd else "ONLINE"
                    elif age <= 300:
                        status_mode = "AWAY"
                    else:
                        status_mode = "OFFLINE"
                        is_online = False
                else:
                    is_online = True
                    status_mode = "DND" if is_dnd else "ONLINE"
        else:
            if presence and presence.last_heartbeat:
                age = (now - presence.last_heartbeat).total_seconds()
                if age <= 30:
                    is_online = True
                    status_mode = "DND" if is_dnd else "ONLINE"
                elif age <= 300:
                    status_mode = "AWAY"
                else:
                    status_mode = "OFFLINE"
                    is_online = False
            else:
                status_mode = "OFFLINE"
                is_online = False
    else:
        if presence and presence.last_heartbeat:
            age = (now - presence.last_heartbeat).total_seconds()
            if age <= 30:
                is_online = True
                status_mode = "DND" if is_dnd else "ONLINE"
            elif age <= 300:
                status_mode = "AWAY"
            else:
                status_mode = "OFFLINE"
                is_online = False

    return {
        "user_id": str(target_user_id),
        "is_online": is_online,
        "status_mode": status_mode,
        "is_dnd": is_dnd,
        "last_heartbeat": last_heartbeat.isoformat() if last_heartbeat else None,
        "updated_at": updated_at.isoformat() if updated_at else None
    }


@router.post("/heartbeat")
def update_presence_heartbeat(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Update the current user's presence heartbeat.
    This endpoint should be called periodically by the frontend to indicate the user is online.
    """
    try:
        presence = db.query(UserPresence).filter(UserPresence.user_id == current_user.id).first()

        if not presence:
            presence = UserPresence(
                user_id=current_user.id,
                is_online=True,
                last_heartbeat=datetime.now(timezone.utc),
                updated_at=datetime.now(timezone.utc)
            )
            db.add(presence)
        else:
            presence.is_online = True
            presence.last_heartbeat = datetime.now(timezone.utc)
            presence.updated_at = datetime.now(timezone.utc)

        db.commit()
        db.refresh(presence)
    except Exception as e:
        db.rollback()
        try:
            UserPresence.__table__.create(db.get_bind(), checkfirst=True)
            presence = db.query(UserPresence).filter(UserPresence.user_id == current_user.id).first()
            if not presence:
                presence = UserPresence(
                    user_id=current_user.id,
                    is_online=True,
                    last_heartbeat=datetime.now(timezone.utc),
                    updated_at=datetime.now(timezone.utc)
                )
                db.add(presence)
            else:
                presence.is_online = True
                presence.last_heartbeat = datetime.now(timezone.utc)
                presence.updated_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(presence)
        except Exception as inner_e:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to update heartbeat: {str(inner_e)}"
            )

    return compute_user_presence_status(db, current_user.id)


@router.get("/status/{user_id}", response_model=dict)
def get_user_presence_status(
    user_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get the presence status for a specific user.
    Requires appropriate authorization based on roles and teams.
    """
    try:
        import uuid
        target_user_id = uuid.UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format"
        )

    # Check if target user exists
    target_user = db.query(User).filter(User.id == target_user_id).first()
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    # Authorization logic:
    if current_user.id == target_user_id:
        pass
    elif current_user.role == "ADMIN":
        pass
    elif current_user.role == "MANAGER":
        manager_memberships = db.query(
            OrganizationMembership.organization_id
        ).filter(
            OrganizationMembership.user_id == current_user.id,
            OrganizationMembership.role == "MANAGER",
            OrganizationMembership.status == "APPROVED"
        ).subquery()

        target_user_in_manager_orgs = db.query(
            OrganizationMembership
        ).filter(
            OrganizationMembership.user_id == target_user_id,
            OrganizationMembership.organization_id.in_(manager_memberships),
            OrganizationMembership.status == "APPROVED"
        ).first()

        if not target_user_in_manager_orgs:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to check this user's presence"
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to check this user's presence"
        )

    return compute_user_presence_status(db, target_user_id)


@router.get("/status", response_model=List[dict])
def get_multiple_users_presence_status(
    user_ids: List[str] = Query(...),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get presence status for multiple users.
    """
    results = []
    for user_id_str in user_ids:
        try:
            status_result = get_user_presence_status(user_id_str, current_user, db)
            results.append(status_result)
        except HTTPException:
            results.append({
                "user_id": user_id_str,
                "is_online": False,
                "status_mode": "OFFLINE",
                "last_heartbeat": None,
                "updated_at": None
            })
        except ValueError:
            results.append({
                "user_id": user_id_str,
                "is_online": False,
                "status_mode": "OFFLINE",
                "last_heartbeat": None,
                "updated_at": None
            })

    return results


@router.delete("/clear/{user_id}")
def clear_user_presence(
    user_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Clear a user's presence record (set to offline).
    """
    try:
        import uuid
        target_user_id = uuid.UUID(user_id)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format"
        )

    if current_user.id != target_user_id and current_user.role != "ADMIN":
        if current_user.role != "MANAGER":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to clear this user's presence"
            )

    try:
        presence = db.query(UserPresence).filter(UserPresence.user_id == target_user_id).first()
        if presence:
            presence.is_online = False
            presence.updated_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(presence)
    except Exception:
        db.rollback()

    return compute_user_presence_status(db, target_user_id)
