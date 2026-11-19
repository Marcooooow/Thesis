from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid

from ..database import get_db
from ..auth.security import get_current_manager_user
from ..models import User, Profile, EmployeeSchedule, Team, TeamMembership
from ..schemas.absence import EmployeeScheduleCreate, EmployeeScheduleResponse
from ..services.cache_service import analytics_cache

router = APIRouter(
    prefix="/schedules",
    tags=["schedules"],
    responses={404: {"description": "Not found"}},
)

def verify_access(db: Session, current_user: User, profile_id: uuid.UUID):
    if current_user.role and current_user.role.strip().upper() == "ADMIN":
        return
    managed_teams = db.query(Team.id).filter(Team.manager_user_id == current_user.id).all()
    team_ids = [t[0] for t in managed_teams]
    if not team_ids:
        raise HTTPException(status_code=403, detail="Unauthorized access to schedule")
    membership = db.query(TeamMembership).filter(
        TeamMembership.team_id.in_(team_ids),
        TeamMembership.profile_id == profile_id,
        TeamMembership.left_at.is_(None)
    ).first()
    if not membership:
        raise HTTPException(status_code=403, detail="Unauthorized access to schedule")

@router.get("/{profile_id}/current", response_model=EmployeeScheduleResponse)
def get_current_schedule(
    profile_id: uuid.UUID,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    verify_access(db, current_user, profile_id)
    today = uuid.uuid4().__class__.date.today() if hasattr(uuid.uuid4(), 'date') else None
    from datetime import date
    today = date.today()
    schedule = db.query(EmployeeSchedule).filter(
        EmployeeSchedule.profile_id == profile_id,
        EmployeeSchedule.effective_from <= today,
        (EmployeeSchedule.effective_until.is_(None) | (EmployeeSchedule.effective_until >= today))
    ).order_by(EmployeeSchedule.effective_from.desc()).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="No active schedule found for profile")
    return schedule

@router.post("/{profile_id}", response_model=EmployeeScheduleResponse, status_code=status.HTTP_201_CREATED)
def create_schedule(
    profile_id: uuid.UUID,
    data: EmployeeScheduleCreate,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    verify_access(db, current_user, profile_id)

    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    schedule = EmployeeSchedule(
        profile_id=profile_id,
        effective_from=data.effective_from,
        effective_until=data.effective_until,
        work_days=data.work_days,
        shift_start=data.shift_start,
        shift_end=data.shift_end,
        timezone=data.timezone,
        created_by=current_user.id
    )
    db.add(schedule)
    try:
        db.commit()
        analytics_cache.invalidate()
        db.refresh(schedule)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=f"Failed to create schedule (possible overlap or validation error): {e}")
    return schedule

@router.get("/{profile_id}/history", response_model=List[EmployeeScheduleResponse])
def get_schedule_history(
    profile_id: uuid.UUID,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    verify_access(db, current_user, profile_id)
    schedules = db.query(EmployeeSchedule).filter(
        EmployeeSchedule.profile_id == profile_id
    ).order_by(EmployeeSchedule.effective_from.desc()).all()
    return schedules
