"""
Workload Calculation Service
Calculates employee available capacity from schedule and current workload from assigned tasks.
"""

from datetime import datetime, timezone, timedelta, time as dtime, date
from typing import Optional, List, Dict, Any, Tuple
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func

from ..models import (
    Profile, Task, EmployeeSchedule, WorkSession, Break, User, Team, TeamMembership
)
from ..services.analytics_service import resolve_target_daily_hours, AnalyticsEngine


def get_effective_schedule(db: Session, profile_id: uuid.UUID, target_date: date) -> Optional[EmployeeSchedule]:
    """Get the effective schedule for a profile on a specific date."""
    return db.query(EmployeeSchedule).filter(
        EmployeeSchedule.profile_id == profile_id,
        EmployeeSchedule.effective_from <= target_date,
        or_(EmployeeSchedule.effective_until.is_(None), EmployeeSchedule.effective_until >= target_date)
    ).order_by(EmployeeSchedule.effective_from.desc()).first()


def calculate_scheduled_work_minutes(
    db: Session,
    profile_id: uuid.UUID,
    target_date: date,
    schedule: Optional[EmployeeSchedule] = None
) -> int:
    """
    Calculate scheduled working minutes for a specific date from employee schedule.
    Excludes scheduled breaks and lunch.

    Returns: minutes of scheduled work time
    """
    if schedule is None:
        schedule = get_effective_schedule(db, profile_id, target_date)

    if not schedule:
        # Fallback to profile shift times or default 8 hours
        profile = db.query(Profile).filter(Profile.id == profile_id).first()
        if profile and profile.shift_start_time and profile.shift_end_time:
            start_minutes = profile.shift_start_time.hour * 60 + profile.shift_start_time.minute
            end_minutes = profile.shift_end_time.hour * 60 + profile.shift_end_time.minute
            total_minutes = max(0, end_minutes - start_minutes)
            # Subtract standard 1 hour lunch
            return max(0, total_minutes - 60)
        return 8 * 60 - 60  # 7 hours default

    # Check if target date is a work day
    day_name = target_date.strftime("%A").lower()
    work_days = [d.lower() for d in (schedule.work_days or [])]
    if day_name not in work_days:
        return 0

    shift_start = schedule.shift_start
    shift_end = schedule.shift_end

    if not shift_start or not shift_end:
        return 8 * 60 - 60

    start_minutes = shift_start.hour * 60 + shift_start.minute
    end_minutes = shift_end.hour * 60 + shift_end.minute
    total_shift_minutes = max(0, end_minutes - start_minutes)

    # Subtract scheduled breaks (standard 1 hour lunch + 2 x 15 min breaks = 90 min)
    # In future: make this configurable per schedule
    scheduled_break_minutes = 90  # 60 lunch + 15 break1 + 15 break2

    return max(0, total_shift_minutes - scheduled_break_minutes)


def calculate_available_capacity_minutes(
    db: Session,
    profile_id: uuid.UUID,
    start_date: date,
    end_date: date
) -> int:
    """
    Calculate total available working minutes in a date range.

    Returns: total minutes of available capacity
    """
    total_minutes = 0
    current = start_date
    while current <= end_date:
        total_minutes += calculate_scheduled_work_minutes(db, profile_id, current)
        current += timedelta(days=1)
    return total_minutes


def get_pending_workload(
    db: Session,
    profile_id: uuid.UUID,
    as_of: Optional[datetime] = None
) -> Dict[str, Any]:
    """
    Calculate current pending workload for an employee.
    Only counts WORK tasks (manager-assigned) with status TODO, IN_PROGRESS, or PENDING.

    Returns: dict with task counts and total estimated minutes
    """
    if as_of is None:
        as_of = datetime.now(timezone.utc)

    # Get pending/in-progress WORK tasks
    pending_tasks = db.query(Task).filter(
        Task.profile_id == profile_id,
        Task.task_type == "WORK",
        Task.status.in_(["TODO", "IN_PROGRESS", "PENDING", "OPEN"])
    ).all()

    total_estimated = 0
    overdue_count = 0
    due_today_count = 0
    due_this_week_count = 0

    as_of_date = as_of.date()
    week_end = as_of_date + timedelta(days=7)

    task_details = []
    for task in pending_tasks:
        est = task.estimated_minutes or 0
        total_estimated += est

        is_overdue = False
        is_due_today = False
        is_due_this_week = False

        if task.deadline:
            deadline_date = task.deadline.date() if task.deadline.tzinfo else task.deadline.date()
            if deadline_date < as_of_date:
                is_overdue = True
                overdue_count += 1
            elif deadline_date == as_of_date:
                is_due_today = True
                due_today_count += 1
            elif deadline_date <= week_end:
                is_due_this_week = True
                due_this_week_count += 1

        task_details.append({
            "task_id": str(task.id),
            "title": task.title,
            "status": task.status,
            "priority": task.priority,
            "deadline": task.deadline.isoformat() if task.deadline else None,
            "estimated_minutes": est,
            "is_overdue": is_overdue,
            "is_due_today": is_due_today,
            "is_due_this_week": is_due_this_week
        })

    return {
        "total_pending_tasks": len(pending_tasks),
        "total_estimated_minutes": total_estimated,
        "total_estimated_hours": round(total_estimated / 60.0, 2),
        "overdue_count": overdue_count,
        "due_today_count": due_today_count,
        "due_this_week_count": due_this_week_count,
        "tasks": task_details
    }


def calculate_workload_for_assignment(
    db: Session,
    profile_id: uuid.UUID,
    new_task_estimated_minutes: int,
    new_task_deadline: Optional[datetime] = None,
    horizon_days: int = 7
) -> Dict[str, Any]:
    """
    Calculate workload impact of a new task assignment.

    Args:
        profile_id: Employee profile
        new_task_estimated_minutes: Estimated minutes for the new task
        new_task_deadline: Deadline for the new task
        horizon_days: Look ahead window for capacity calculation (default 7 days)

    Returns: Complete workload analysis with warnings
    """
    as_of = datetime.now(timezone.utc)
    today = as_of.date()
    horizon_end = today + timedelta(days=horizon_days)

    # 1. Calculate available capacity
    available_minutes = calculate_available_capacity_minutes(db, profile_id, today, horizon_end)

    # 2. Calculate existing pending workload
    existing_workload = get_pending_workload(db, profile_id, as_of)
    existing_minutes = existing_workload["total_estimated_minutes"]

    # 3. Calculate new total
    new_total_minutes = existing_minutes + new_task_estimated_minutes

    # 4. Calculate utilization
    utilization_pct = (new_total_minutes / available_minutes * 100.0) if available_minutes > 0 else 0.0

    # 5. Determine workload status
    if utilization_pct >= 120:
        status = "OVERALLOCATED"
        severity = "HIGH"
    elif utilization_pct >= 100:
        status = "AT_CAPACITY"
        severity = "MEDIUM"
    elif utilization_pct >= 80:
        status = "APPROACHING_CAPACITY"
        severity = "LOW"
    else:
        status = "NORMAL"
        severity = "NONE"

    # 6. Generate explainable warnings
    warnings = []

    if severity == "HIGH":
        warnings.append({
            "code": "WORKLOAD_EXCEEDS_CAPACITY",
            "message": f"Assignment would exceed employee's available capacity by {utilization_pct - 100:.0f}%",
            "details": {
                "available_minutes": available_minutes,
                "existing_minutes": existing_minutes,
                "new_task_minutes": new_task_estimated_minutes,
                "total_minutes": new_total_minutes,
                "utilization_pct": round(utilization_pct, 1)
            },
            "severity": "HIGH"
        })
    elif severity == "MEDIUM":
        warnings.append({
            "code": "WORKLOAD_AT_CAPACITY",
            "message": "Assignment would bring employee to full capacity",
            "details": {
                "available_minutes": available_minutes,
                "existing_minutes": existing_minutes,
                "new_task_minutes": new_task_estimated_minutes,
                "total_minutes": new_total_minutes,
                "utilization_pct": round(utilization_pct, 1)
            },
            "severity": "MEDIUM"
        })
    elif severity == "LOW":
        warnings.append({
            "code": "WORKLOAD_APPROACHING_CAPACITY",
            "message": f"Employee will be at {utilization_pct:.0f}% capacity",
            "details": {
                "available_minutes": available_minutes,
                "existing_minutes": existing_minutes,
                "new_task_minutes": new_task_estimated_minutes,
                "total_minutes": new_total_minutes,
                "utilization_pct": round(utilization_pct, 1)
            },
            "severity": "LOW"
        })

    # 7. Check for overdue tasks
    if existing_workload["overdue_count"] > 0:
        warnings.append({
            "code": "HAS_OVERDUE_TASKS",
            "message": f"Employee has {existing_workload['overdue_count']} overdue task(s)",
            "details": {
                "overdue_count": existing_workload["overdue_count"]
            },
            "severity": "MEDIUM"
        })

    # 8. Check for tasks due today
    if existing_workload["due_today_count"] > 0:
        warnings.append({
            "code": "HAS_TASKS_DUE_TODAY",
            "message": f"Employee has {existing_workload['due_today_count']} task(s) due today",
            "details": {
                "due_today_count": existing_workload["due_today_count"]
            },
            "severity": "LOW"
        })

    # 9. Check if new task is urgent (due soon)
    if new_task_deadline:
        deadline_date = new_task_deadline.date() if new_task_deadline.tzinfo else new_task_deadline.date()
        days_until = (deadline_date - today).days
        if days_until <= 1:
            warnings.append({
                "code": "URGENT_DEADLINE",
                "message": f"New task deadline is {'today' if days_until == 0 else 'tomorrow'}",
                "details": {
                    "days_until_deadline": days_until,
                    "deadline": new_task_deadline.isoformat()
                },
                "severity": "HIGH" if days_until == 0 else "MEDIUM"
            })

    return {
        "profile_id": str(profile_id),
        "analysis_date": today.isoformat(),
        "horizon_days": horizon_days,
        "available_minutes": available_minutes,
        "available_hours": round(available_minutes / 60.0, 2),
        "existing_workload": existing_workload,
        "new_task_estimated_minutes": new_task_estimated_minutes,
        "new_total_minutes": new_total_minutes,
        "new_total_hours": round(new_total_minutes / 60.0, 2),
        "utilization_pct": round(utilization_pct, 1),
        "status": status,
        "severity": severity,
        "warnings": warnings,
        "recommendations": _generate_recommendations(warnings, existing_workload, new_task_estimated_minutes)
    }


def _generate_recommendations(
    warnings: List[Dict],
    existing_workload: Dict,
    new_task_minutes: int
) -> List[Dict[str, Any]]:
    """Generate actionable recommendations based on workload analysis."""
    recommendations = []

    # Check severity
    has_high = any(w["severity"] == "HIGH" for w in warnings)
    has_medium = any(w["severity"] == "MEDIUM" for w in warnings)

    if has_high:
        recommendations.append({
            "action": "REDUCE_SCOPE",
            "label": "Reduce task scope or split into smaller tasks",
            "description": "Consider breaking this task into multiple smaller tasks with staggered deadlines"
        })
        recommendations.append({
            "action": "EXTEND_DEADLINE",
            "label": "Extend deadline",
            "description": "Give the employee more time to complete this work without overtime"
        })
        recommendations.append({
            "action": "REDISTRIBUTE",
            "label": "Redistribute to another team member",
            "description": "Assign this task to another employee with available capacity"
        })
    elif has_medium:
        recommendations.append({
            "action": "EXTEND_DEADLINE",
            "label": "Consider extending deadline",
            "description": "Adding buffer time reduces pressure to work overtime"
        })
        recommendations.append({
            "action": "REDUCE_PRIORITY",
            "label": "Lower priority if not urgent",
            "description": "If this task is not time-critical, consider lowering priority to MEDIUM or LOW"
        })

    if existing_workload["overdue_count"] > 0:
        recommendations.append({
            "action": "ADDRESS_OVERDUE",
            "label": "Address overdue tasks first",
            "description": f"Employee has {existing_workload['overdue_count']} overdue task(s). Consider completing these before adding new work."
        })

    # Default recommendation if no specific issues
    if not recommendations:
        recommendations.append({
            "action": "PROCEED",
            "label": "Proceed with assignment",
            "description": "Employee has sufficient capacity for this task"
        })

    return recommendations


def get_team_workload_overview(
    db: Session,
    manager_user_id: uuid.UUID
) -> List[Dict[str, Any]]:
    """
    Get workload overview for all employees in manager's teams.

    Returns: List of employee workload summaries
    """
    # Get manager's teams
    manager_teams = db.query(Team).filter(Team.manager_user_id == manager_user_id).all()
    manager_team_ids = [t.id for t in manager_teams]

    if not manager_team_ids:
        return []

    # Get active team members
    memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id.in_(manager_team_ids),
        TeamMembership.left_at.is_(None)
    ).all()

    profile_ids = [m.profile_id for m in memberships]

    # Get profiles
    profiles = db.query(Profile).filter(Profile.id.in_(profile_ids)).all()

    overview = []
    as_of = datetime.now(timezone.utc)

    for profile in profiles:
        workload = get_pending_workload(db, profile.id, as_of)

        # Calculate 7-day capacity
        today = as_of.date()
        week_end = today + timedelta(days=7)
        available_minutes = calculate_available_capacity_minutes(db, profile.id, today, week_end)

        utilization_pct = (workload["total_estimated_minutes"] / available_minutes * 100.0) if available_minutes > 0 else 0.0

        if utilization_pct >= 120:
            status = "OVERALLOCATED"
        elif utilization_pct >= 100:
            status = "AT_CAPACITY"
        elif utilization_pct >= 80:
            status = "APPROACHING_CAPACITY"
        else:
            status = "NORMAL"

        # Get active shift status
        active_session = db.query(WorkSession).filter(
            WorkSession.profile_id == profile.id,
            WorkSession.ended_at.is_(None)
        ).first()

        overview.append({
            "profile_id": str(profile.id),
            "employee_name": profile.full_name or "Unknown",
            "employee_email": profile.user.email if profile.user else None,
            "shift_status": "ACTIVE" if active_session else "OFF_SHIFT",
            "pending_tasks": workload["total_pending_tasks"],
            "overdue_tasks": workload["overdue_count"],
            "due_today": workload["due_today_count"],
            "estimated_workload_minutes": workload["total_estimated_minutes"],
            "estimated_workload_hours": workload["total_estimated_hours"],
            "available_minutes": available_minutes,
            "available_hours": round(available_minutes / 60.0, 2),
            "utilization_pct": round(utilization_pct, 1),
            "status": status
        })

    return overview