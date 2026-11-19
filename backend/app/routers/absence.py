from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import date, datetime, timezone

from ..database import get_db
from ..auth.security import get_current_manager_user
from ..models import User, Profile, AbsenceRecord, Team, TeamMembership
from ..schemas.absence import AbsenceRecordResponse, AbsenceAcknowledgment

router = APIRouter(
    prefix="/manager/absences",
    tags=["manager-absences"],
    responses={404: {"description": "Not found"}},
)

def get_manager_team_profile_ids(db: Session, manager_user: User) -> List[uuid.UUID]:
    if manager_user.role and manager_user.role.strip().upper() == "ADMIN":
        all_profiles = db.query(Profile.id).all()
        return [p[0] for p in all_profiles]

    managed_teams = db.query(Team.id).filter(Team.manager_user_id == manager_user.id).all()
    team_ids = [t[0] for t in managed_teams]
    if not team_ids:
        return []
    memberships = db.query(TeamMembership.profile_id).filter(
        TeamMembership.team_id.in_(team_ids),
        TeamMembership.left_at.is_(None)
    ).all()
    return [m[0] for m in memberships]

def enrich_absence_response(ar: AbsenceRecord) -> AbsenceRecordResponse:
    res = AbsenceRecordResponse.model_validate(ar)
    prof = ar.profile
    user = prof.user if prof else None
    sched = ar.schedule
    res.employee_name = user.full_name if user and user.full_name else (user.email if user else "Unknown Employee")
    res.department = prof.department if prof and prof.department else "Engineering Team"
    res.shift_start = sched.shift_start if sched else None
    res.shift_end = sched.shift_end if sched else None
    return res

@router.get("", response_model=List[AbsenceRecordResponse])
def list_team_absences(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    profile_id: Optional[uuid.UUID] = None,
    classification: Optional[str] = None,
    acknowledged: Optional[bool] = None,
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    profile_ids = get_manager_team_profile_ids(db, current_user)
    if not profile_ids:
        return []

    query = db.query(AbsenceRecord).filter(AbsenceRecord.profile_id.in_(profile_ids))

    if profile_id:
        if profile_id not in profile_ids:
            raise HTTPException(status_code=403, detail="Unauthorized access to profile absences")
        query = query.filter(AbsenceRecord.profile_id == profile_id)

    if start_date:
        query = query.filter(AbsenceRecord.absence_date >= start_date)
    if end_date:
        query = query.filter(AbsenceRecord.absence_date <= end_date)
    if classification:
        query = query.filter(AbsenceRecord.classification == classification.upper())
    if acknowledged is not None:
        if acknowledged:
            query = query.filter(AbsenceRecord.manager_acknowledged_at.isnot(None))
        else:
            query = query.filter(AbsenceRecord.manager_acknowledged_at.is_(None))

    records = query.order_by(AbsenceRecord.absence_date.desc()).offset(offset).limit(limit).all()
    return [enrich_absence_response(ar) for ar in records]

@router.patch("/{absence_id}/acknowledge", response_model=AbsenceRecordResponse)
def acknowledge_absence(
    absence_id: uuid.UUID,
    data: AbsenceAcknowledgment,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    absence = db.query(AbsenceRecord).filter(AbsenceRecord.id == absence_id).first()
    if not absence:
        raise HTTPException(status_code=404, detail="Absence record not found")

    profile_ids = get_manager_team_profile_ids(db, current_user)
    if absence.profile_id not in profile_ids:
        raise HTTPException(status_code=403, detail="Unauthorized access to absence record")

    absence.classification = data.classification.upper()
    absence.manager_acknowledged_at = datetime.now(timezone.utc)
    absence.acknowledged_by = current_user.id
    absence.notes = data.notes
    absence.updated_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(absence)
    return enrich_absence_response(absence)
