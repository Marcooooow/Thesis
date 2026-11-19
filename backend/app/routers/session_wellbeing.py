from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid

from .. import models
from ..schemas import session_wellbeing
from ..database import get_db
from .auth import get_current_active_user
from ..services.cache_service import analytics_cache

router = APIRouter(
    prefix="/session-wellbeing",
    tags=["session-wellbeing"],
)

@router.post("/", response_model=session_wellbeing.SessionWellbeingCheckinRead)
def create_session_wellbeing_checkin(
    checkin: session_wellbeing.SessionWellbeingCheckinCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user),
):
    # Verify that the work_session_id belongs to the current user's active (or just completed) session
    # We can check by joining WorkSession and ensuring the session's profile_id matches the user's profile.
    # For simplicity, we assume the user can only submit for their own sessions.
    work_session = (
        db.query(models.WorkSession)
        .filter(models.WorkSession.id == checkin.work_session_id)
        .first()
    )
    if not work_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Work session not found",
        )
    # Check that the session belongs to the current user's profile
    if work_session.profile_id != current_user.profile.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to submit check-in for this session",
        )

    # Check if a check-in already exists for this work_session_id (optional: we can allow update or reject)
    existing_checkin = (
        db.query(models.SessionWellbeingCheckin)
        .filter(models.SessionWellbeingCheckin.work_session_id == checkin.work_session_id)
        .first()
    )
    if existing_checkin:
        # For now, we update the existing check-in (upsert behavior) to avoid duplicate submission errors.
        # Alternatively, we could return an error. We choose to update.
        for var, value in vars(checkin).items():
            if var not in ["id", "created_at"] and value is not None:
                setattr(existing_checkin, var, value)
        db.add(existing_checkin)
        db.commit()
        analytics_cache.invalidate()
        db.refresh(existing_checkin)
        return existing_checkin

    # Create new check-in
    db_checkin = models.SessionWellbeingCheckin(
        **checkin.model_dump(),
        user_id=current_user.id,
    )
    db.add(db_checkin)
    db.commit()
    analytics_cache.invalidate()
    db.refresh(db_checkin)
    return db_checkin

@router.get("/", response_model=List[session_wellbeing.SessionWellbeingCheckinRead])
def read_session_wellbeing_checkins(
    work_session_id: Optional[uuid.UUID] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user),
):
    query = db.query(models.SessionWellbeingCheckin).filter(
        models.SessionWellbeingCheckin.user_id == current_user.id
    )
    if work_session_id:
        query = query.filter(models.SessionWellbeingCheckin.work_session_id == work_session_id)
    checkins = query.offset(skip).limit(limit).all()
    return checkins

@router.get("/{checkin_id}", response_model=session_wellbeing.SessionWellbeingCheckinRead)
def read_session_wellbeing_checkin(
    checkin_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_active_user),
):
    checkin = (
        db.query(models.SessionWellbeingCheckin)
        .filter(models.SessionWellbeingCheckin.id == checkin_id)
        .first()
    )
    if not checkin:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Session wellbeing check-in not found",
        )
    if checkin.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this check-in",
        )
    return checkin