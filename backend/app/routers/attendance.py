from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional
from datetime import date

from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User, Profile, EmployeeSchedule, AbsenceRecord, LeaveRequest
from ..services.return_to_work import ReturnToWorkService

router = APIRouter(
    prefix="/attendance",
    tags=["attendance"],
    responses={404: {"description": "Not found"}},
)

@router.get("/my")
def get_my_attendance(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    today = date.today()
    schedule = db.query(EmployeeSchedule).filter(
        EmployeeSchedule.profile_id == profile.id,
        EmployeeSchedule.effective_from <= today,
        (EmployeeSchedule.effective_until.is_(None) | (EmployeeSchedule.effective_until >= today))
    ).order_by(EmployeeSchedule.effective_from.desc()).first()

    if not schedule:
        from datetime import time
        start_t = time(8, 0)
        end_t = time(17, 0)
        if profile.shift_start_time:
            try:
                start_t = time.fromisoformat(profile.shift_start_time) if isinstance(profile.shift_start_time, str) else profile.shift_start_time
            except Exception:
                pass
        if profile.shift_end_time:
            try:
                end_t = time.fromisoformat(profile.shift_end_time) if isinstance(profile.shift_end_time, str) else profile.shift_end_time
            except Exception:
                pass
        schedule = EmployeeSchedule(
            profile_id=profile.id,
            effective_from=profile.hire_date or today,
            effective_until=None,
            work_days=profile.work_days or ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
            shift_start=start_t,
            shift_end=end_t,
            timezone='Asia/Manila',
            created_by=current_user.id
        )
        db.add(schedule)
        db.commit()
        db.refresh(schedule)
    else:
        # Self-healing synchronization with profile
        updated = False
        if profile.shift_start_time:
            p_start = time.fromisoformat(profile.shift_start_time) if isinstance(profile.shift_start_time, str) else profile.shift_start_time
            if schedule.shift_start != p_start:
                schedule.shift_start = p_start
                updated = True
        if profile.shift_end_time:
            p_end = time.fromisoformat(profile.shift_end_time) if isinstance(profile.shift_end_time, str) else profile.shift_end_time
            if schedule.shift_end != p_end:
                schedule.shift_end = p_end
                updated = True
        if profile.work_days and schedule.work_days != profile.work_days:
            schedule.work_days = profile.work_days
            updated = True
        if updated:
            db.commit()
            db.refresh(schedule)

    abs_query = db.query(AbsenceRecord).filter(AbsenceRecord.profile_id == profile.id)
    if start_date:
        abs_query = abs_query.filter(AbsenceRecord.absence_date >= start_date)
    if end_date:
        abs_query = abs_query.filter(AbsenceRecord.absence_date <= end_date)
    absences = abs_query.order_by(AbsenceRecord.absence_date.desc()).all()

    leave_query = db.query(LeaveRequest).filter(LeaveRequest.profile_id == profile.id)
    leave_requests = leave_query.order_by(LeaveRequest.created_at.desc()).all()

    rtw_svc = ReturnToWorkService(db)
    pending_rtw = rtw_svc.check_pending_rtw(profile.id)

    return {
        "schedule": schedule,
        "absences": absences,
        "leave_requests": leave_requests,
        "pending_rtw": pending_rtw or {"has_pending": False}
    }
