from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import date

from ..database import get_db
from ..auth.security import get_current_active_user, get_current_manager_user
from ..models import User, Profile
from ..schemas.absence import (
    ReturnToWorkSubmit, ReturnToWorkResponse, ReturnToWorkManagerView
)
from ..services.return_to_work import ReturnToWorkService

router = APIRouter(
    tags=["return-to-work"],
)

rtw_router = APIRouter(
    prefix="/return-to-work",
    tags=["return-to-work"],
    responses={404: {"description": "Not found"}},
)

manager_rtw_router = APIRouter(
    prefix="/manager/return-to-work",
    tags=["manager-return-to-work"],
    responses={404: {"description": "Not found"}},
)

@rtw_router.get("/pending")
def check_pending_rtw(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return {"has_pending": False}

    rtw_svc = ReturnToWorkService(db)
    pending = rtw_svc.check_pending_rtw(profile.id)
    if not pending:
        return {"has_pending": False}

    return {
        "has_pending": True,
        "work_session_id": pending["work_session_id"],
        "absence_record_id": pending["absence_record_id"],
        "session_ended_at": pending["session_ended_at"]
    }

@rtw_router.post("/checkin", response_model=ReturnToWorkResponse, status_code=status.HTTP_201_CREATED)
def submit_rtw_checkin(
    data: ReturnToWorkSubmit,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    rtw_svc = ReturnToWorkService(db)
    try:
        return rtw_svc.submit_rtw(profile.id, data.work_session_id, data)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@rtw_router.get("/history", response_model=List[ReturnToWorkResponse])
def get_rtw_history(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return []

    rtw_svc = ReturnToWorkService(db)
    checkins = rtw_svc.db.query(rtw_svc.db.class_mapper(ReturnToWorkResponse).class_ if hasattr(rtw_svc, 'db') else None) # or query ReturnToWorkCheckin
    from ..models import ReturnToWorkCheckin
    return db.query(ReturnToWorkCheckin).filter(
        ReturnToWorkCheckin.profile_id == profile.id
    ).order_by(ReturnToWorkCheckin.submitted_at.desc()).all()

@manager_rtw_router.get("/team", response_model=List[ReturnToWorkManagerView])
def get_team_rtw(
    week_start: Optional[date] = None,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    rtw_svc = ReturnToWorkService(db)
    # Get team profiles managed by current_user (or all if admin)
    from ..models import Team, TeamMembership, ReturnToWorkCheckin
    if current_user.role and current_user.role.strip().upper() == "ADMIN":
        checkins = db.query(ReturnToWorkCheckin).all()
    else:
        managed_teams = db.query(Team.id).filter(Team.manager_user_id == current_user.id).all()
        team_ids = [t[0] for t in managed_teams]
        if not team_ids:
            return []
        profile_ids = db.query(TeamMembership.profile_id).filter(
            TeamMembership.team_id.in_(team_ids),
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [p[0] for p in profile_ids]
        if not p_ids:
            return []
        checkins = db.query(ReturnToWorkCheckin).filter(ReturnToWorkCheckin.profile_id.in_(p_ids)).all()

    # Apply privacy filtering
    results = []
    for c in checkins:
        view_data = rtw_svc.get_rtw_for_manager(current_user.id, c.id)
        if view_data:
            results.append(view_data)
    return results
