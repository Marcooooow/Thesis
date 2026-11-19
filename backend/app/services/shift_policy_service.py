"""
Shift Policy & Workload Protection Service
Provides shift-end warnings, overtime detection, continuous work duration checks,
break compliance verification, and authorized override auditing.
"""

from datetime import datetime, timezone, timedelta, time as dtime, date
from typing import Optional, Dict, Any, List
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_

from ..models import WorkSession, Break, Task, EmployeeSchedule, Profile, UserSettings
from .workload_service import get_effective_schedule


def get_shift_policy_status(db: Session, session_id: uuid.UUID) -> Dict[str, Any]:
    """Get shift policy compliance status for a session."""
    session = db.get(WorkSession, session_id)
    if not session:
        return {}
    return check_shift_policy_compliance(db, session.profile_id, session)


def check_shift_policy_compliance(
    db: Session,
    profile_id: uuid.UUID,
    active_session: WorkSession,
    max_continuous_work_minutes: int = 120,
    max_shift_duration_minutes: int = 480
) -> Dict[str, Any]:
    """
    Check current active work session for continuous work duration, overtime,
    shift duration limits, and break compliance.
    """
    now = datetime.now(timezone.utc)
    session_started = active_session.started_at
    if session_started.tzinfo is None:
        session_started = session_started.replace(tzinfo=timezone.utc)

    elapsed_minutes = int((now - session_started).total_seconds() / 60)

    # Check breaks taken in this session
    breaks = db.query(Break).filter(Break.work_session_id == active_session.id).all()
    total_break_minutes = sum(
        int(((b.ended_at or now) - b.started_at).total_seconds() / 60)
        for b in breaks
    )

    actual_work_minutes = max(0, elapsed_minutes - total_break_minutes)

    # Find last break end time or session start time for continuous work calculation
    last_break_end = session_started
    completed_breaks = [b for b in breaks if b.ended_at is not None]
    if completed_breaks:
        completed_breaks.sort(key=lambda x: x.ended_at, reverse=True)
        last_break_end = completed_breaks[0].ended_at
        if last_break_end.tzinfo is None:
            last_break_end = last_break_end.replace(tzinfo=timezone.utc)

    continuous_work_minutes = int((now - last_break_end).total_seconds() / 60)

    # Check schedule for expected end time & overtime
    today = now.date()
    schedule = get_effective_schedule(db, profile_id, today)

    scheduled_end_datetime = None
    is_overtime = False
    overtime_minutes = 0
    approaching_shift_end = False

    if schedule and schedule.shift_end:
        shift_end_t = schedule.shift_end
        scheduled_end_datetime = datetime.combine(today, shift_end_t)
        now_time = now.time()

        if now_time > shift_end_t:
            is_overtime = True
            current_mins = now_time.hour * 60 + now_time.minute
            end_mins = shift_end_t.hour * 60 + shift_end_t.minute
            overtime_minutes = current_mins - end_mins
        else:
            current_mins = now_time.hour * 60 + now_time.minute
            end_mins = shift_end_t.hour * 60 + shift_end_t.minute
            if (end_mins - current_mins) <= 30:
                approaching_shift_end = True

    elif elapsed_minutes >= max_shift_duration_minutes - 30:
        approaching_shift_end = True
        if elapsed_minutes > max_shift_duration_minutes:
            is_overtime = True
            overtime_minutes = elapsed_minutes - max_shift_duration_minutes

    continuous_work_warning = continuous_work_minutes >= max_continuous_work_minutes

    warnings = []
    if continuous_work_warning:
        warnings.append({
            "code": "CONTINUOUS_WORK_EXCEEDED",
            "message": f"You have worked continuously for {continuous_work_minutes} minutes without a break. Please take a recovery break.",
            "severity": "HIGH"
        })
    if approaching_shift_end and not is_overtime:
        warnings.append({
            "code": "APPROACHING_SHIFT_END",
            "message": "Your scheduled shift is ending soon. Please wrap up active tasks and prepare to end your shift.",
            "severity": "MEDIUM"
        })
    if is_overtime:
        warnings.append({
            "code": "OVERTIME_DETECTED",
            "message": f"You have exceeded your scheduled shift hours by {overtime_minutes} minutes. Remember to prioritize rest.",
            "severity": "HIGH"
        })

    return {
        "session_id": str(active_session.id),
        "elapsed_minutes": elapsed_minutes,
        "actual_work_minutes": actual_work_minutes,
        "total_break_minutes": total_break_minutes,
        "continuous_work_minutes": continuous_work_minutes,
        "continuous_work_warning": continuous_work_warning,
        "approaching_shift_end": approaching_shift_end,
        "is_overtime": is_overtime,
        "overtime_minutes": overtime_minutes,
        "warnings": warnings
    }
