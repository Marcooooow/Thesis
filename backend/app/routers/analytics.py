from fastapi import APIRouter, Depends, HTTPException, status, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import or_
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
import io
import statistics
from datetime import datetime, timezone, timedelta, date
from ..database import get_db
from ..auth.security import get_current_active_user, get_current_admin_user, log_system_activity, should_include_test_data
from ..services.behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from ..services.analytics_service import AnalyticsEngine
from ..models import User, Profile, UserSettings, WorkSession, Task, Break, RecommendationFeedback, SessionWellbeingCheckin, OrganizationMembership, Organization, Team, TeamMembership, WorkLifeBalanceSurvey
from ..services.wellbeing_monitoring import WellbeingMonitoringService
from ..services.organizational_insights_service import OrganizationalInsightsService
from ..services.admin_organization_report_service import AdminOrganizationReportService
from ..services.wlb_analysis_service import WLBAnalysisService
from ..analytics_utils import merge_intervals, calculate_unique_task_seconds, get_week_start_end, get_start_end_for_period, get_previous_start_end_for_period, parse_date_range

router = APIRouter(
    prefix="/analytics",
    tags=["analytics"],
    responses={404: {"description": "Not found"}},
)

def resolve_target_daily_hours(db: Session, user: User, profile: Profile) -> float:
    """
    Approved target-hours fallback resolver:
    1. Profile.target_daily_hours (User target)
    2. UserSettings.work_target_daily_hours
    3. Hardcoded default of 8.0 hours
    Uses the first valid, positive configured value (> 0).
    """
    if profile and profile.target_daily_hours is not None and profile.target_daily_hours > 0:
        return float(profile.target_daily_hours)

    settings = db.query(UserSettings).filter(UserSettings.user_id == user.id).first()
    if settings and settings.work_target_daily_hours is not None and settings.work_target_daily_hours > 0:
        return float(settings.work_target_daily_hours)

    return 8.0

def get_organization_ids_for_user(db: Session, user_id: uuid.UUID):
    """Get organization IDs for which the user has an approved membership."""
    org_ids = db.query(OrganizationMembership.organization_id).filter(
        OrganizationMembership.user_id == user_id,
        OrganizationMembership.status == "APPROVED"
    ).all()
    return [org_id for (org_id,) in org_ids]


@router.get("/today/focus-ratio")
def get_today_focus_ratio(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get today's focus ratio data.
    Returns percentages for active focus, idle (productive breaks), and non-active time.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="ANALYTICS_TODAY_FOCUS_RATIO_ACCESSED",
        action_details={}
    )

    summary = AnalyticsEngine.calculate_daily_summary(db, profile.id)
    return {
        "activeFocus": summary["activeFocus"],
        "idle": summary["idle"],
        "nonActive": summary["nonActive"]
    }


@router.get("/today/summary")
def get_today_summary(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get comprehensive summary metrics for today or a specified date range / period.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="ANALYTICS_TODAY_SUMMARY_ACCESSED",
        action_details={"start_date": start_date, "end_date": end_date, "period": period}
    )

    if start_date or end_date or period:
        start, end = parse_date_range(start_date, end_date, period, user_tz)
        return AnalyticsEngine.calculate_period_summary(db, profile.id, start, end)
    else:
        return AnalyticsEngine.calculate_daily_summary(db, profile.id)


@router.get("/daily-summary")
def get_daily_summary(
    date: Optional[str] = Query(None, description="Date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get consolidated Daily Progress Summary for an employee for a specific date (defaulting to today).
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="ANALYTICS_DAILY_SUMMARY_ACCESSED",
        action_details={"date": date}
    )

    try:
        return AnalyticsEngine.calculate_daily_progress_summary(db, profile.id, date)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.get("/weekly/focus-idle")
def get_weekly_focus_idle(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get daily focus vs idle time for a date range."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    # Get user timezone from settings
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    log_system_activity(db=db, user_id=current_user.id, action_type="ANALYTICS_WEEKLY_FOCUS_IDLE_ACCESSED", action_details={"start_date": start_date, "end_date": end_date, "period": period})

    start, end = parse_date_range(start_date, end_date, period, user_tz)

    days_list = []
    curr = start.date()
    end_date_obj = end.date()
    while curr <= end_date_obj:
        days_list.append(curr)
        curr += timedelta(days=1)

    sessions = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.started_at >= start,
        WorkSession.started_at <= end
    ).all()

    daily_focus = {d: 0.0 for d in days_list}
    daily_idle = {d: 0.0 for d in days_list}

    for s in sessions:
        metrics = AnalyticsEngine.calculate_session_metrics(db, s)
        if s.started_at:
            s_date = s.started_at.date()
            if s_date in daily_focus:
                daily_focus[s_date] += metrics["focused_seconds"]
                daily_idle[s_date] += metrics["break_seconds"]

    result = []
    for day_date in days_list:
        result.append({
            'day': day_date.strftime('%a'),
            'date': day_date.isoformat(),
            'focusHours': round(daily_focus[day_date] / 3600.0, 2),
            'idleHours': round(daily_idle[day_date] / 3600.0, 2)
        })
    return result


@router.get("/weekly/work-hours")
def get_weekly_work_hours(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get daily work hours compared to target for a date range."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    log_system_activity(db=db, user_id=current_user.id, action_type="ANALYTICS_WEEKLY_WORK_HOURS_ACCESSED", action_details={"start_date": start_date, "end_date": end_date, "period": period})

    start, end = parse_date_range(start_date, end_date, period, user_tz)

    curr = start.date()
    end_date_obj = end.date()
    days_list = []
    while curr <= end_date_obj:
        days_list.append(curr)
        curr += timedelta(days=1)

    sessions = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.started_at >= start,
        WorkSession.started_at <= end
    ).all()

    daily_worked = {d: 0.0 for d in days_list}
    target_daily_hours = resolve_target_daily_hours(db, current_user, profile)

    for s in sessions:
        metrics = AnalyticsEngine.calculate_session_metrics(db, s)
        if s.started_at:
            s_date = s.started_at.date()
            if s_date in daily_worked:
                daily_worked[s_date] += metrics["worked_seconds"]

    result = []
    for day_date in days_list:
        worked_hrs = daily_worked[day_date] / 3600.0
        result.append({
            'day': day_date.strftime('%a'),
            'date': day_date.isoformat(),
            'actualHours': round(worked_hrs, 2),
            'targetHours': target_daily_hours
        })

    return result


@router.get("/break-analysis")
def get_break_analysis(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Break type breakdown within a date range."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    start, end = parse_date_range(start_date, end_date, period, user_tz)
    result = AnalyticsEngine.calculate_break_analysis(db, profile.id, start, end)
    return result


@router.get("/session-history")
def get_session_history(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Paginated work session history."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    start, end = parse_date_range(start_date, end_date, period, user_tz)
    result = AnalyticsEngine.get_session_history(db, profile.id, start, end, skip, limit)
    return {"items": result, "count": len(result)}


@router.get("/insights")
def generate_insights(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Generate productivity and wellbeing insights for the current profile."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    log_system_activity(db=db, user_id=current_user.id, action_type="ANALYTICS_INSIGHTS_ACCESSED", action_details={})
    result = AnalyticsEngine.generate_insights(db, profile.id)
    return result


@router.get("/wellbeing-summary")
def get_wellbeing_summary(
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    period: Optional[str] = Query(None, description="Period"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get self-reported wellbeing summary check-ins for the profile within a date range."""
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    checkins = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id == current_user.id,
        SessionWellbeingCheckin.created_at >= start,
        SessionWellbeingCheckin.created_at <= end
    ).all()

    if not checkins:
        return {
            "checkinCount": 0,
            "avgOverallWellbeing": 0.0,
            "avgMentalFatigue": 0.0,
            "avgWorkloadManageability": 0.0,
            "avgPerceivedFocus": 0.0,
            "avgBreakRecovery": 0.0
        }

    return {
        "checkinCount": len(checkins),
        "avgOverallWellbeing": round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2),
        "avgMentalFatigue": round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2),
        "avgWorkloadManageability": round(sum(c.workload_manageability for c in checkins) / len(checkins), 2),
        "avgPerceivedFocus": round(sum(c.perceived_focus for c in checkins) / len(checkins), 2),
        "avgBreakRecovery": round(sum(c.break_recovery for c in checkins) / len(checkins), 2)
    }


@router.get("/what-changed")
def get_what_changed(
    period: Optional[str] = Query(None, description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Compare current period against previous period for the current user."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    curr, prev = parse_date_range(None, None, period, user_tz)
    result = AnalyticsEngine.calculate_period_comparison(db, profile.id, curr, curr, prev, prev)
    return result


@router.get("/focus-rate")
def get_focus_rate(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get focus rate percentage for the current user."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Profile not found")

    log_system_activity(db=db, user_id=current_user.id, action_type="ANALYTICS_FOCUS_RATE_ACCESSED", action_details={})
    summary = AnalyticsEngine.calculate_daily_summary(db, profile.id)
    return {"rate": summary["focusRate"]}


# ============================================================================
# ADMIN ANALYTICS ENDPOINTS
# ============================================================================

@router.get("/admin/today/focus-ratio")
def get_admin_today_focus_ratio(
    period: Optional[str] = "today",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide focus ratio data."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TODAY_FOCUS_RATIO_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"activeFocus": 0.0, "idle": 0.0, "nonActive": 0.0}

    include_test = should_include_test_data(db, current_user)
    ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        WorkSession.started_at >= start,
        WorkSession.started_at < end
    )
    if not include_test:
        ws_q = ws_q.filter(Profile.is_test_data == False)
    work_sessions = ws_q.all()

    if not work_sessions:
        return {"activeFocus": 0.0, "idle": 0.0, "nonActive": 0.0}

    productive_breaks = {'LUNCH', 'MEAL', 'BREAK', 'BREAK_1', 'BREAK_2', 'SHORT_BREAK'}
    total_work_seconds = 0.0
    productive_break_seconds = 0.0
    unproductive_break_seconds = 0.0
    total_task_seconds = 0.0

    for session in work_sessions:
        session_end = session.ended_at or datetime.now(timezone.utc)
        work_duration = (session_end - session.started_at).total_seconds()
        total_work_seconds += max(0, work_duration)

        breaks = db.query(Break).filter(Break.work_session_id == session.id, Break.ended_at.isnot(None)).all()
        for b in breaks:
            b_dur = max(0, (b.ended_at - b.started_at).total_seconds())
            if b.break_type in productive_breaks:
                productive_break_seconds += b_dur
            else:
                unproductive_break_seconds += b_dur

        tasks = db.query(Task).filter(Task.work_session_id == session.id, Task.started_at.isnot(None)).all()
        total_task_seconds += calculate_unique_task_seconds(tasks, session.started_at, session_end, breaks)

    other_seconds = max(0, total_work_seconds - productive_break_seconds - unproductive_break_seconds - total_task_seconds)
    active_focus = (total_task_seconds / total_work_seconds * 100.0) if total_work_seconds > 0 else 0.0
    idle = (productive_break_seconds / total_work_seconds * 100.0) if total_work_seconds > 0 else 0.0
    non_active = (unproductive_break_seconds + other_seconds) / total_work_seconds * 100.0 if total_work_seconds > 0 else 0.0

    return {
        "activeFocus": round(active_focus, 2),
        "idle": round(idle, 2),
        "nonActive": round(non_active, 2)
    }


@router.get("/admin/weekly/focus-idle")
def get_admin_weekly_focus_idle(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide daily focus vs idle time."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WEEKLY_FOCUS_IDLE_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    days_list = []
    curr = start.date()
    end_date = end.date()
    while curr <= end_date:
        days_list.append(curr)
        curr += timedelta(days=1)

    result = []
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        for d in days_list:
            result.append({'day': d.strftime('%a'), 'focusHours': 0.0, 'idleHours': 0.0})
        return result

    daily_data = {d: {'focus_seconds': 0, 'idle_seconds': 0} for d in days_list}

    include_test = should_include_test_data(db, current_user)
    ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        WorkSession.started_at >= start,
        WorkSession.started_at < end
    )
    if not include_test:
        ws_q = ws_q.filter(Profile.is_test_data == False)
    work_sessions = ws_q.all()

    for session in work_sessions:
        session_date = session.started_at.date()
        session_end = session.ended_at or datetime.now(timezone.utc)
        breaks = db.query(Break).filter(Break.work_session_id == session.id, Break.ended_at.isnot(None)).all()
        break_seconds = sum(max(0, (b.ended_at - b.started_at).total_seconds()) for b in breaks)
        tasks = db.query(Task).filter(Task.work_session_id == session.id, Task.started_at.isnot(None)).all()
        task_seconds = calculate_unique_task_seconds(tasks, session.started_at, session_end, breaks)

        if session_date in daily_data:
            daily_data[session_date]['focus_seconds'] += task_seconds
            daily_data[session_date]['idle_seconds'] += break_seconds

    for d in days_list:
        data = daily_data.get(d, {'focus_seconds': 0, 'idle_seconds': 0})
        result.append({
            'day': d.strftime('%a'),
            'focusHours': round(data['focus_seconds'] / 3600, 2),
            'idleHours': round(data['idle_seconds'] / 3600, 2)
        })

    return result


@router.get("/admin/focus-rate")
def get_admin_focus_rate(
    period: Optional[str] = "today",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide focus rate."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_FOCUS_RATE_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"rate": 0.0}

    include_test = should_include_test_data(db, current_user)
    ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        WorkSession.started_at >= start,
        WorkSession.started_at < end
    )
    if not include_test:
        ws_q = ws_q.filter(Profile.is_test_data == False)
    work_sessions = ws_q.all()

    if not work_sessions:
        return {"rate": 0.0}

    total_work_seconds = 0.0
    total_task_seconds = 0.0

    for session in work_sessions:
        session_end = session.ended_at or datetime.now(timezone.utc)
        work_duration = (session_end - session.started_at).total_seconds()
        total_work_seconds += max(0, work_duration)

        tasks = db.query(Task).filter(Task.work_session_id == session.id, Task.started_at.isnot(None)).all()
        breaks = db.query(Break).filter(Break.work_session_id == session.id, Break.ended_at.isnot(None)).all()
        total_task_seconds += calculate_unique_task_seconds(tasks, session.started_at, session_end, breaks)

    focus_rate = (total_task_seconds / total_work_seconds * 100.0) if total_work_seconds > 0 else 0.0
    return {"rate": round(focus_rate, 2)}


@router.get("/admin/weekly/work-hours")
def get_admin_weekly_work_hours(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide daily work hours compared to target."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WEEKLY_WORK_HOURS_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    days_list = []
    curr = start.date()
    end_date = end.date()
    while curr <= end_date:
        days_list.append(curr)
        curr += timedelta(days=1)

    result = []
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        for d in days_list:
            result.append({'day': d.strftime('%a'), 'actualHours': 0.0, 'targetHours': 8.0})
        return result

    daily_data = {d: {'task_seconds': 0} for d in days_list}

    include_test = should_include_test_data(db, current_user)
    ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        WorkSession.started_at >= start,
        WorkSession.started_at < end
    )
    if not include_test:
        ws_q = ws_q.filter(Profile.is_test_data == False)
    work_sessions = ws_q.all()

    for session in work_sessions:
        session_date = session.started_at.date()
        session_end = session.ended_at or datetime.now(timezone.utc)
        breaks = db.query(Break).filter(Break.work_session_id == session.id, Break.ended_at.isnot(None)).all()
        tasks = db.query(Task).filter(Task.work_session_id == session.id, Task.started_at.isnot(None)).all()
        task_seconds = calculate_unique_task_seconds(tasks, session.started_at, session_end, breaks)

        if session_date in daily_data:
            daily_data[session_date]['task_seconds'] += task_seconds

    for d in days_list:
        data = daily_data.get(d, {'task_seconds': 0})
        result.append({
            'day': d.strftime('%a'),
            'actualHours': round(data['task_seconds'] / 3600, 2),
            'targetHours': 8.0
        })

    return result


@router.get("/admin/work-sustainability")
def get_admin_work_sustainability(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide Work Sustainability metrics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WORK_SUSTAINABILITY_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "sustainabilityIndex": 100.0,
            "overtimeFrequency": 0.0,
            "breakCompliance": 100.0,
            "longSessionsCount": 0,
            "lateShiftEndingsCount": 0,
            "missedBreaksCount": 0,
            "totalWorkdaysAnalyzed": 0,
            "note": "No organization membership found."
        }
    include_test = should_include_test_data(db, current_user)
    return AnalyticsEngine.calculate_organization_work_sustainability(db, org_ids, start, end, include_test=include_test)


@router.get("/admin/wellbeing/today")
def get_admin_today_wellbeing(
    period: Optional[str] = "today",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide today's wellbeing analytics (admin-only)."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TODAY_WELLBEING_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    include_test = should_include_test_data(db, current_user)
    user_q = db.query(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED"
    )
    if not include_test:
        user_q = user_q.join(Profile, Profile.user_id == User.id).filter(Profile.is_test_data == False)
    users = user_q.all()
    user_ids = [u.id for u in users]

    if not user_ids:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    checkins = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id.in_(user_ids),
        SessionWellbeingCheckin.created_at >= start,
        SessionWellbeingCheckin.created_at < end
    ).all()

    if not checkins:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    respondents = len(set(c.user_id for c in checkins))
    if respondents < 3 and not include_test:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0,
            "privacy_suppressed": True
        }

    return {
        "checkinCount": len(checkins),
        "overallWellbeing": round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2),
        "mentalFatigue": round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2),
        "workloadManageability": round(sum(c.workload_manageability for c in checkins) / len(checkins), 2),
        "perceivedFocus": round(sum(c.perceived_focus for c in checkins) / len(checkins), 2),
        "breakRecovery": round(sum(c.break_recovery for c in checkins) / len(checkins), 2)
    }


@router.get("/admin/wellbeing/weekly")
def get_admin_weekly_wellbeing(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide weekly wellbeing analytics (admin-only)."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WEEKLY_WELLBEING_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    include_test = should_include_test_data(db, current_user)
    user_q = db.query(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED"
    )
    if not include_test:
        user_q = user_q.join(Profile, Profile.user_id == User.id).filter(Profile.is_test_data == False)
    users = user_q.all()
    user_ids = [u.id for u in users]

    if not user_ids:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    checkins = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id.in_(user_ids),
        SessionWellbeingCheckin.created_at >= start,
        SessionWellbeingCheckin.created_at < end
    ).all()

    if not checkins:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0
        }

    respondents = len(set(c.user_id for c in checkins))
    if respondents < 3 and not include_test:
        return {
            "checkinCount": 0,
            "overallWellbeing": 0.0,
            "mentalFatigue": 0.0,
            "workloadManageability": 0.0,
            "perceivedFocus": 0.0,
            "breakRecovery": 0.0,
            "privacy_suppressed": True
        }

    return {
        "checkinCount": len(checkins),
        "overallWellbeing": round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2),
        "mentalFatigue": round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2),
        "workloadManageability": round(sum(c.workload_manageability for c in checkins) / len(checkins), 2),
        "perceivedFocus": round(sum(c.perceived_focus for c in checkins) / len(checkins), 2),
        "breakRecovery": round(sum(c.break_recovery for c in checkins) / len(checkins), 2)
    }


@router.get("/admin/team-comparison")
def get_admin_team_comparison(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Get organization-wide team comparison metrics for admin dashboard.
    Compares teams on productivity, work sustainability (WSI), work-life balance (WLB), and wellbeing risk tiers.
    Enforces N >= 3 privacy suppression and organization tenant isolation.
    """
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TEAM_COMPARISON_ACCESSED", action_details={"period": period})
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"organization_id": None, "period": period, "teams": []}

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)
    include_test = should_include_test_data(db, current_user)

    teams = db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True).all()
    team_comparisons = []

    for team in teams:
        memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [m.profile_id for m in memberships]
        prof_q = db.query(Profile).filter(Profile.id.in_(p_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()
        profile_ids = [p.id for p in profiles]
        total_employees = len(profile_ids)

        is_suppressed = total_employees < 3

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id.in_(profile_ids),
            WorkSession.started_at >= start,
            WorkSession.started_at <= end
        ).all() if profile_ids else []

        total_work_secs = 0.0
        total_break_secs = 0.0
        for s in sessions:
            s_end = s.ended_at or datetime.now(timezone.utc)
            total_work_secs += max(0, (s_end - s.started_at).total_seconds())
            breaks = db.query(Break).filter(Break.work_session_id == s.id, Break.ended_at.isnot(None)).all()
            for b in breaks:
                total_break_secs += max(0, (b.ended_at - b.started_at).total_seconds())

        total_work_hours = round(total_work_secs / 3600.0, 2)
        total_break_hours = round(total_break_secs / 3600.0, 2)
        avg_work_hours_per_employee = round(total_work_hours / max(1, total_employees), 2)

        tasks = db.query(Task).filter(
            Task.profile_id.in_(profile_ids),
            Task.created_at >= start,
            Task.created_at <= end
        ).all() if profile_ids else []
        completed_tasks = len([t for t in tasks if t.status == 'DONE'])
        avg_completed_tasks_per_employee = round(completed_tasks / max(1, total_employees), 2)

        wsi_metrics = AnalyticsEngine.calculate_organization_work_sustainability(
            db, org_ids, start, end, include_test=include_test
        )

        week_start_date = start.date() - timedelta(days=start.date().weekday())
        surveys = db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= week_start_date - timedelta(days=21)
        ).all() if profile_ids else []

        avg_wlb_score = 0.0
        survey_respondents = len(set(s.profile_id for s in surveys))
        if surveys and not is_suppressed:
            avg_wlb_score = round(sum(s.score for s in surveys) / len(surveys), 2)

        survey_participation_rate = round((survey_respondents / max(1, total_employees)) * 100.0, 1)

        wb_service = WellbeingMonitoringService(db)
        overview = wb_service.compute_team_overview(
            manager_id=current_user.id,
            week_start=week_start_date,
            team_id=team.id
        )
        by_tier = overview.team_summary.by_tier if overview and overview.team_summary else {}

        team_comparisons.append({
            "team_id": str(team.id),
            "team_name": team.name,
            "active_employees": total_employees,
            "privacy_suppressed": is_suppressed,
            "productivity": {
                "total_work_hours": total_work_hours,
                "total_break_hours": total_break_hours,
                "avg_work_hours_per_employee": avg_work_hours_per_employee,
                "completed_tasks": completed_tasks,
                "avg_completed_tasks_per_employee": avg_completed_tasks_per_employee,
            },
            "work_sustainability": {
                "sustainability_index": wsi_metrics.get("sustainabilityIndex", 100.0),
                "overtime_frequency": wsi_metrics.get("overtimeFrequency", 0.0),
                "break_compliance": wsi_metrics.get("breakCompliance", 100.0),
                "late_shift_endings_count": wsi_metrics.get("lateShiftEndingsCount", 0),
                "long_sessions_count": wsi_metrics.get("longSessionsCount", 0),
            },
            "work_life_balance": {
                "avg_wlb_score": None if is_suppressed else avg_wlb_score,
                "survey_respondents": survey_respondents,
                "survey_participation_rate": survey_participation_rate,
            },
            "wellbeing_tiers": {
                "low": 0 if is_suppressed else by_tier.get("low", 0),
                "moderate": 0 if is_suppressed else by_tier.get("moderate", 0),
                "high": 0 if is_suppressed else by_tier.get("high", 0),
                "critical": 0 if is_suppressed else by_tier.get("critical", 0),
                "insufficient_data": 0 if is_suppressed else by_tier.get("insufficient_data", total_employees),
            }
        })

    return {
        "organization_id": str(org_ids[0]) if org_ids else None,
        "period": period,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "teams": team_comparisons
    }


@router.get("/admin/recommendation-effectiveness")
def get_admin_recommendation_effectiveness(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team ID filter"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Get organization-wide and team-level recommendation effectiveness metrics.
    Includes generated, accepted, dismissed, expired/pending counts, acceptance/dismissal rates,
    action effectiveness, category breakdown, and historical trends.
    Enforces N >= 3 privacy suppression and organization tenant isolation.
    """
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_RECOMMENDATION_EFFECTIVENESS_ACCESSED", action_details={"period": period})
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "organization_id": None,
            "period": period,
            "generated_count": 0,
            "accepted_count": 0,
            "dismissed_count": 0,
            "expired_count": 0,
            "pending_count": 0,
            "total_feedback": 0,
            "acceptance_rate": None,
            "dismissal_rate": None,
            "action_rate": None,
            "feedback_coverage": 0.0,
            "category_breakdown": {},
            "historical_trends": [],
            "teams": []
        }

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)
    include_test = should_include_test_data(db, current_user)

    team_query = db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True)
    if team_id:
        team_query = team_query.filter(Team.id == team_id)
    teams = team_query.all()

    team_data_list = []
    for team in teams:
        memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [m.profile_id for m in memberships]
        prof_q = db.query(Profile).filter(Profile.id.in_(p_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()
        t_profile_ids = [p.id for p in profiles]
        total_employees = len(t_profile_ids)
        is_suppressed = total_employees < 3

        user_ids = [p.user_id for p in profiles]
        feedback_q = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_id.in_(user_ids),
            RecommendationFeedback.timestamp >= start,
            RecommendationFeedback.timestamp <= end
        ) if user_ids else db.query(RecommendationFeedback).filter(False)
        feedback_records = feedback_q.all()

        recs_map = {}
        for f in feedback_records:
            r_id = f.recommendation_id
            if r_id not in recs_map or (f.timestamp and recs_map[r_id].timestamp and f.timestamp > recs_map[r_id].timestamp):
                recs_map[r_id] = f
        unique_feedback_list = list(recs_map.values())

        t_gen = len(unique_feedback_list)
        unique_feedback_recs = len([f for f in unique_feedback_list if f.user_action is not None])
        unique_gen_recs = t_gen
        t_accepted = len([f for f in unique_feedback_list if f.user_action == 'accepted'])
        t_dismissed = len([f for f in unique_feedback_list if f.user_action == 'dismissed'])
        t_expired = len([f for f in unique_feedback_list if f.user_action == 'ignored'])
        t_pending = len([f for f in unique_feedback_list if f.user_action is None])

        denom = t_accepted + t_dismissed
        t_acc_rate = round((t_accepted / denom * 100.0), 1) if denom > 0 else None
        t_dis_rate = round((t_dismissed / denom * 100.0), 1) if denom > 0 else None

        trackable_types = {'SHORT_BREAK', 'WALK', 'LUNCH', 'STRETCH'}
        trackable_accepted = [f for f in unique_feedback_list if f.user_action == 'accepted' and f.recommendation_type in trackable_types]
        t_action_count = len([f for f in trackable_accepted if f.break_started_at is not None])
        t_action_rate = round((t_action_count / len(trackable_accepted) * 100.0), 1) if trackable_accepted else None

        t_categories = {}
        for f in unique_feedback_list:
            cat = f.recommendation_type or "OTHER"
            t_categories[cat] = t_categories.get(cat, 0) + 1

        team_data_list.append({
            "team_id": str(team.id),
            "team_name": team.name,
            "active_employees": total_employees,
            "privacy_suppressed": is_suppressed,
            "generated_count": None if is_suppressed else t_gen,
            "accepted_count": None if is_suppressed else t_accepted,
            "dismissed_count": None if is_suppressed else t_dismissed,
            "expired_count": None if is_suppressed else t_expired,
            "pending_count": None if is_suppressed else t_pending,
            "total_feedback": None if is_suppressed else unique_feedback_recs,
            "acceptance_rate": None if is_suppressed else t_acc_rate,
            "dismissal_rate": None if is_suppressed else t_dis_rate,
            "action_rate": None if is_suppressed else t_action_rate,
            "feedback_coverage": None if is_suppressed else round(min(100.0, (unique_feedback_recs / max(1, unique_gen_recs)) * 100.0), 1),
            "category_breakdown": None if is_suppressed else t_categories
        })

    org_user_ids = [u.id for u in db.query(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED"
    ).all()]

    if team_id and teams:
        org_user_ids = [p.user_id for team in teams for m in db.query(TeamMembership).filter(TeamMembership.team_id == team.id, TeamMembership.left_at.is_(None)).all() for p in db.query(Profile).filter(Profile.id == m.profile_id).all()]

    feedback_query = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.user_id.in_(org_user_ids),
        RecommendationFeedback.timestamp >= start,
        RecommendationFeedback.timestamp <= end
    ) if org_user_ids else db.query(RecommendationFeedback).filter(False)
    org_feedback = feedback_query.all()

    org_recs_map = {}
    for f in org_feedback:
        r_id = f.recommendation_id
        if r_id not in org_recs_map or (f.timestamp and org_recs_map[r_id].timestamp and f.timestamp > org_recs_map[r_id].timestamp):
            org_recs_map[r_id] = f
    unique_org_feedback_list = list(org_recs_map.values())

    gen_count = len(unique_org_feedback_list)
    unique_org_feedback_recs = len([f for f in unique_org_feedback_list if f.user_action is not None])
    unique_org_gen_recs = gen_count
    accepted_count = len([f for f in unique_org_feedback_list if f.user_action == 'accepted'])
    dismissed_count = len([f for f in unique_org_feedback_list if f.user_action == 'dismissed'])
    expired_count = len([f for f in unique_org_feedback_list if f.user_action == 'ignored'])
    pending_count = len([f for f in unique_org_feedback_list if f.user_action is None])
    total_feedback = unique_org_feedback_recs

    denom_org = accepted_count + dismissed_count
    acceptance_rate = round((accepted_count / denom_org * 100.0), 1) if denom_org > 0 else None
    dismissal_rate = round((dismissed_count / denom_org * 100.0), 1) if denom_org > 0 else None

    org_trackable_accepted = [f for f in unique_org_feedback_list if f.user_action == 'accepted' and f.recommendation_type in {'SHORT_BREAK', 'WALK', 'LUNCH', 'STRETCH'}]
    action_count = len([f for f in org_trackable_accepted if f.break_started_at is not None])
    action_rate = round((action_count / len(org_trackable_accepted) * 100.0), 1) if org_trackable_accepted else None
    feedback_coverage = round(min(100.0, (unique_org_feedback_recs / max(1, unique_org_gen_recs)) * 100.0), 1) if unique_org_gen_recs > 0 else 0.0

    category_breakdown = {}
    for f in unique_org_feedback_list:
        cat = f.recommendation_type or "OTHER"
        category_breakdown[cat] = category_breakdown.get(cat, 0) + 1

    days_list = []
    curr = start.date()
    end_date_obj = end.date()
    while curr <= end_date_obj:
        days_list.append(curr)
        curr += timedelta(days=1)

    daily_map = {d: {"generated": 0, "accepted": 0, "dismissed": 0, "expired": 0} for d in days_list}
    for f in unique_org_feedback_list:
        if f.timestamp:
            f_date = f.timestamp.date()
            if f_date in daily_map:
                daily_map[f_date]["generated"] += 1
                if f.user_action == 'accepted':
                    daily_map[f_date]["accepted"] += 1
                elif f.user_action == 'dismissed':
                    daily_map[f_date]["dismissed"] += 1
                elif f.user_action == 'ignored':
                    daily_map[f_date]["expired"] += 1

    historical_trends = []
    for d in days_list:
        counts = daily_map[d]
        d_denom = counts["accepted"] + counts["dismissed"]
        d_acc_rate = round((counts["accepted"] / d_denom * 100.0), 1) if d_denom > 0 else None
        historical_trends.append({
            "date": d.isoformat(),
            "day": d.strftime('%a'),
            "generated": counts["generated"],
            "accepted": counts["accepted"],
            "dismissed": counts["dismissed"],
            "expired": counts["expired"],
            "acceptance_rate": d_acc_rate
        })

    return {
        "organization_id": str(org_ids[0]) if org_ids else None,
        "period": period,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "generated_count": gen_count,
        "accepted_count": accepted_count,
        "dismissed_count": dismissed_count,
        "expired_count": expired_count,
        "pending_count": pending_count,
        "total_feedback": total_feedback,
        "acceptance_rate": acceptance_rate,
        "dismissal_rate": dismissal_rate,
        "action_rate": action_rate,
        "feedback_coverage": feedback_coverage,
        "category_breakdown": category_breakdown,
        "historical_trends": historical_trends,
        "teams": team_data_list
    }


def _friendly_pattern_name(pattern_id: str) -> str:
    mapping = {
        "RECURRING_OVERWORK": "Extended Work Hours",
        "INSUFFICIENT_RECOVERY": "Break Recovery Trend",
        "REPEATED_SKIPPED_BREAKS": "Skipped Break Pattern",
        "DECLINING_MEASURABLE_FOCUS": "Focus Pace Shift",
        "RECURRING_FATIGUE_STRESS": "Recovery and Wellbeing Pattern"
    }
    return mapping.get(pattern_id, "Work Habit Observation")


def _friendly_evidence_label(evidence: str) -> str:
    if evidence == "HIGH":
        return "Strong confidence"
    elif evidence == "MEDIUM":
        return "Moderate confidence"
    else:
        return "Limited confidence"


def _friendly_wlb_risk_label(risk_tier: str) -> str:
    """Convert WLB risk tier to user-friendly label."""
    labels = {
        "LOW": "Healthy Balance",
        "MODERATE": "Needs Attention",
        "HIGH": "At Risk",
        "CRITICAL": "Critical"
    }
    return labels.get(risk_tier, "Unknown")


def _sanitize_wlb_message(message: str) -> str:
    """Sanitize message for display (replace technical terms)."""
    sanitized = message
    sanitized = sanitized.replace('RECURRING_FATIGUE_STRESS', 'Recovery and Wellbeing Pattern')
    sanitized = sanitized.replace('RECURRING_OVERWORK', 'Extended Work Hours')
    sanitized = sanitized.replace('INSUFFICIENT_RECOVERY', 'Break Recovery Trend')
    sanitized = sanitized.replace('REPEATED_SKIPPED_BREAKS', 'Skipped Break Pattern')
    sanitized = sanitized.replace('DECLINING_MEASURABLE_FOCUS', 'Focus Pace Shift')
    return sanitized


@router.get("/wellness/summary")
def get_wellness_summary(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Enhanced wellness summary combining:
    - Behavioral pattern detection (existing)
    - WLB questionnaire analysis (new)
    - Unified risk classification with explainable evidence
    - Habit-focused recommendations (distinct from break coaching)
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    # 1. Existing behavioral analytics
    baselines = calculate_personal_baselines(db, profile.id, days=30)
    patterns = detect_behavioral_patterns(db, profile.id)
    detected = [p for p in patterns if p.get("detected") and p.get("evidence_strength") in ("MEDIUM", "HIGH")]
    is_cold_start = baselines.get("is_cold_start", True)

    # 2. WLB Analysis for current reporting week
    today = date.today()
    current_monday = today - timedelta(days=today.weekday())
    wlb_service = WLBAnalysisService(db)
    wlb_analysis = wlb_service.get_weekly_wlb_analysis(profile.id, current_monday)

    # 2b. Get most recent WLB survey (any week) for last survey date display
    latest_survey = db.query(WorkLifeBalanceSurvey).filter(
        WorkLifeBalanceSurvey.profile_id == profile.id
    ).order_by(WorkLifeBalanceSurvey.submitted_at.desc()).first()
    if latest_survey:
        wlb_analysis["last_survey_date"] = latest_survey.submitted_at.date().isoformat()
        wlb_analysis["last_survey_message"] = f"Your last survey was completed on {latest_survey.submitted_at.strftime('%B %d, %Y')}"
    else:
        wlb_analysis["last_survey_date"] = None
        wlb_analysis["last_survey_message"] = "No WLB survey completed yet. Complete your weekly survey to get personalized insights."

    # 3. Determine overall status combining behavioral + WLB
    has_wlb_survey = wlb_analysis.get("has_survey", False)
    wlb_risk = wlb_analysis.get("risk_tier", "LOW")
    behavioral_concerns = len(detected)
    wlb_concerns = len(wlb_analysis.get("behavioral_indicators", {}).get("concerns", []))
    total_concerns = behavioral_concerns + wlb_concerns

    if is_cold_start and not has_wlb_survey:
        status = "insufficient_data"
        message = "Not enough data yet. Complete a weekly WLB survey and log work sessions to get personalized insights."
    elif total_concerns == 0 and (not has_wlb_survey or wlb_risk == "LOW"):
        status = "healthy"
        message = "Your work-life balance indicators are healthy. No significant concerns detected."
    elif wlb_risk in ("HIGH", "CRITICAL") or behavioral_concerns >= 2:
        status = "concern"
        # Build combined message
        parts = []
        if has_wlb_survey:
            wlb_score = wlb_analysis.get("wlb_survey", {}).get("score")
            if wlb_score is not None:
                parts.append(f"WLB score: {wlb_score}/100")
        if wlb_concerns > 0:
            parts.append(f"{wlb_concerns} work pattern concern(s)")
        if behavioral_concerns > 0:
            friendly_names = [_friendly_pattern_name(p["pattern_id"]) for p in detected]
            parts.append(f"behavioral: {', '.join(friendly_names)}")
        message = "Areas for attention: " + "; ".join(parts) if parts else "Review your work-life balance."
    else:
        status = "attention"
        message = "Some indicators suggest attention needed. Review weekly WLB survey and work patterns."

    # 4. Combine evidence from both sources
    all_evidence = []

    # WLB evidence
    for ev in wlb_analysis.get("evidence", []):
        all_evidence.append({
            "source": "wlb_questionnaire" if ev["type"].startswith("WLB_") else "behavioral_telemetry",
            "type": ev["type"],
            "title": ev.get("title", ev["type"].replace("_", " ").title()),
            "description": (
                ev.get("description", "")
                if not ev["type"].startswith("WLB_QUESTION_LOW")
                else "One or more weekly survey areas may benefit from attention."
            ),
            "severity": ev.get("severity", "MEDIUM"),
            "metric_value": (
                ev.get("metric_value")
                if not ev["type"].startswith("WLB_QUESTION_LOW")
                else None
            ),
            "threshold": ev.get("threshold") if not ev["type"].startswith("WLB_QUESTION_LOW") else None
        })

    # Behavioral pattern evidence (from existing detected patterns)
    for p in detected:
        all_evidence.append({
            "source": "behavioral_pattern",
            "type": p["pattern_id"],
            "title": _friendly_pattern_name(p["pattern_id"]),
            "description": p.get("measurement", ""),
            "severity": p.get("evidence_strength", "MEDIUM"),
            "metric_value": None,
            "threshold": None
        })

    # 5. WLB-specific recommendations (habit changes, NOT break coaching)
    wlb_recommendations = wlb_analysis.get("recommendations", [])
    trend_data = wlb_service.get_wlb_trends(profile.id, weeks=8)
    trends = trend_data.get("weekly_data", [])
    previous_week = trends[-2] if len(trends) >= 2 else None
    current_week = trends[-1] if trends else None
    weekly_comparison = {
        "previous_week": previous_week,
        "current_week": current_week,
        "has_comparison": bool(
            previous_week and current_week
            and previous_week.get("has_survey")
            and current_week.get("has_survey")
        ),
        "score_change": (
            round(current_week["wlb_score"] - previous_week["wlb_score"], 1)
            if previous_week and current_week
            and previous_week.get("wlb_score") is not None
            and current_week.get("wlb_score") is not None
            else None
        ),
    }
    safe_survey = wlb_analysis.get("wlb_survey")
    if safe_survey is not None:
        safe_survey = {key: value for key, value in safe_survey.items() if key != "responses"}

    # 6. Build response compatible with existing AIWellnessCard
    # The card expects: status, message, cold_start, detection_count, detected_patterns, observation_sessions, note
    # We add: wlb_analysis, combined_evidence, wlb_recommendations
    return {
        # Existing fields (for backward compatibility with AIWellnessCard)
        "status": status,
        "message": _sanitize_wlb_message(message),
        "cold_start": is_cold_start and not has_wlb_survey,
        "detection_count": total_concerns,
        "detected_patterns": [{
            "pattern_id": p["pattern_id"],
            "display_name": _friendly_pattern_name(p["pattern_id"]),
            "evidence": _friendly_evidence_label(p["evidence_strength"])
        } for p in detected],
        "observation_sessions": baselines.get("observation_count_sessions", 0),
        "note": "Based on logged work session and break data only; task activity measures active task logging, not psychological focus. Not a medical or psychological assessment.",

        # NEW: WLB-specific enhancements
        "wlb_analysis": {
            "has_survey": has_wlb_survey,
            "survey": safe_survey,
            "risk_tier": wlb_risk,
            "risk_label": _friendly_wlb_risk_label(wlb_risk),
            "behavioral_indicators": wlb_analysis.get("behavioral_indicators"),
            "trend": trend_data.get("trend", "stable"),
            "weekly_comparison": weekly_comparison,
            "last_survey_date": wlb_analysis.get("last_survey_date"),
            "last_survey_message": wlb_analysis.get("last_survey_message"),
        },
        "combined_evidence": all_evidence,
        "wlb_recommendations": [{
            **recommendation,
            "id": str(uuid.uuid5(
                uuid.NAMESPACE_URL,
                f"intellibreak:wlb:{profile.id}:{current_monday.isoformat()}:{recommendation['id']}",
            )),
        } for recommendation in wlb_recommendations],
        "recommendation_note": "These are weekly habit recommendations for work-life balance. For real-time break suggestions during active sessions, see Break Coach."
    }


@router.get("/admin/recommendations/today")
def get_admin_today_recommendations(
    period: Optional[str] = "today",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide recommendation analytics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TODAY_RECOMMENDATIONS_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"total": 0, "accepted": 0, "dismissed": 0, "expired": 0, "acceptanceRate": 0.0, "byType": []}

    include_test = should_include_test_data(db, current_user)
    fb_q = db.query(RecommendationFeedback).join(User, RecommendationFeedback.user_id == User.id).join(OrganizationMembership, User.id == OrganizationMembership.user_id).join(Profile, User.id == Profile.user_id).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        RecommendationFeedback.timestamp >= start,
        RecommendationFeedback.timestamp < end
    )
    if not include_test:
        fb_q = fb_q.filter(Profile.is_test_data == False)
    feedback = fb_q.all()

    total = len(feedback)
    accepted = len([f for f in feedback if f.user_action == "accepted"])
    dismissed = len([f for f in feedback if f.user_action == "dismissed"])
    acceptance_rate = (accepted / total * 100) if total > 0 else 0.0

    type_counts = {}
    for f in feedback:
        rec_type = f.recommendation_type
        type_counts[rec_type] = type_counts.get(rec_type, 0) + 1

    by_type = [{"type": rt, "count": cnt} for rt, cnt in type_counts.items()]

    return {
        "total": total,
        "accepted": accepted,
        "dismissed": dismissed,
        "expired": 0,
        "acceptanceRate": round(acceptance_rate, 2),
        "byType": by_type
    }


@router.get("/admin/recommendations/weekly")
def get_admin_weekly_recommendations(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide weekly recommendation analytics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WEEKLY_RECOMMENDATIONS_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"total": 0, "accepted": 0, "dismissed": 0, "expired": 0, "acceptanceRate": 0.0, "byType": []}

    include_test = should_include_test_data(db, current_user)
    fb_q = db.query(RecommendationFeedback).join(User, RecommendationFeedback.user_id == User.id).join(OrganizationMembership, User.id == OrganizationMembership.user_id).join(Profile, User.id == Profile.user_id).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        RecommendationFeedback.timestamp >= start,
        RecommendationFeedback.timestamp < end
    )
    if not include_test:
        fb_q = fb_q.filter(Profile.is_test_data == False)
    feedback = fb_q.all()

    total = len(feedback)
    accepted = len([f for f in feedback if f.user_action == "accepted"])
    dismissed = len([f for f in feedback if f.user_action == "dismissed"])
    acceptance_rate = (accepted / total * 100) if total > 0 else 0.0

    type_counts = {}
    for f in feedback:
        rec_type = f.recommendation_type
        type_counts[rec_type] = type_counts.get(rec_type, 0) + 1

    by_type = [{"type": rt, "count": cnt} for rt, cnt in type_counts.items()]

    return {
        "total": total,
        "accepted": accepted,
        "dismissed": dismissed,
        "expired": 0,
        "acceptanceRate": round(acceptance_rate, 2),
        "byType": by_type
    }


@router.get("/admin/wellbeing/today")
def get_admin_today_wellbeing(
    period: Optional[str] = "today",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide wellbeing analytics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TODAY_WELLBEING_ACCESSED", action_details={"period": period})
    start, end = get_start_end_for_period(period)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"overallWellbeing": 0.0, "mentalFatigue": 0.0, "workloadManageability": 0.0, "perceivedFocus": 0.0, "breakRecovery": 0.0, "checkinCount": 0}

    include_test = should_include_test_data(db, current_user)
    chk_q = db.query(SessionWellbeingCheckin).join(User, SessionWellbeingCheckin.user_id == User.id).join(OrganizationMembership, User.id == OrganizationMembership.user_id).join(Profile, User.id == Profile.user_id).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        SessionWellbeingCheckin.created_at >= start,
        SessionWellbeingCheckin.created_at < end
    )
    if not include_test:
        chk_q = chk_q.filter(Profile.is_test_data == False)
    checkins = chk_q.all()

    count = len(checkins)
    if count == 0:
        return {"overallWellbeing": 0.0, "mentalFatigue": 0.0, "workloadManageability": 0.0, "perceivedFocus": 0.0, "breakRecovery": 0.0, "checkinCount": 0}

    return {
        "overallWellbeing": round(sum(c.overall_wellbeing for c in checkins) / count, 2),
        "mentalFatigue": round(sum(c.mental_fatigue for c in checkins) / count, 2),
        "workloadManageability": round(sum(c.workload_manageability for c in checkins) / count, 2),
        "perceivedFocus": round(sum(c.perceived_focus for c in checkins) / count, 2),
        "breakRecovery": round(sum(c.break_recovery for c in checkins) / count, 2),
        "checkinCount": count
    }


@router.get("/admin/organizational-insights")
def get_admin_organizational_insights(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    category: Optional[str] = Query(None, description="Optional category filter: productivity, sustainability, wlb, wellbeing, teams, recommendations"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Get automated, rule-based organizational insights for Admin Organization Analytics.
    Analyzes productivity, work sustainability, work-life balance, wellbeing risk, team performance,
    and recommendation effectiveness against configurable thresholds.
    Enforces Admin RBAC, tenant isolation, and N >= 3 privacy suppression.
    """
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ORGANIZATIONAL_INSIGHTS_ACCESSED", action_details={"period": period, "category": category})
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "period": period or "this_week",
            "start_date": None,
            "end_date": None,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "total_insights": 0,
            "severity_counts": {"informational": 0, "positive": 0, "warning": 0, "critical": 0},
            "insights": [],
            "data_quality_indicator": "insufficient_data"
        }

    return OrganizationalInsightsService.generate_organizational_insights(
        db=db,
        current_user=current_user,
        period=period,
        start_date=start_date,
        end_date=end_date,
        category_filter=category
    )

def get_admin_weekly_wellbeing(
    period: Optional[str] = "this_week",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide weekly wellbeing analytics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WEEKLY_WELLBEING_ACCESSED", action_details={"period": period})
    start, end = get_start_end_for_period(period)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"overallWellbeing": 0.0, "mentalFatigue": 0.0, "workloadManageability": 0.0, "perceivedFocus": 0.0, "breakRecovery": 0.0, "checkinCount": 0}

    include_test = should_include_test_data(db, current_user)
    chk_q = db.query(SessionWellbeingCheckin).join(User, SessionWellbeingCheckin.user_id == User.id).join(OrganizationMembership, User.id == OrganizationMembership.user_id).join(Profile, User.id == Profile.user_id).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        SessionWellbeingCheckin.created_at >= start,
        SessionWellbeingCheckin.created_at < end
    )
    if not include_test:
        chk_q = chk_q.filter(Profile.is_test_data == False)
    checkins = chk_q.all()

    count = len(checkins)
    if count == 0:
        return {"overallWellbeing": 0.0, "mentalFatigue": 0.0, "workloadManageability": 0.0, "perceivedFocus": 0.0, "breakRecovery": 0.0, "checkinCount": 0}

    return {
        "overallWellbeing": round(sum(c.overall_wellbeing for c in checkins) / count, 2),
        "mentalFatigue": round(sum(c.mental_fatigue for c in checkins) / count, 2),
        "workloadManageability": round(sum(c.workload_manageability for c in checkins) / count, 2),
        "perceivedFocus": round(sum(c.perceived_focus for c in checkins) / count, 2),
        "breakRecovery": round(sum(c.break_recovery for c in checkins) / count, 2),
        "checkinCount": count
    }


@router.get("/admin/what-changed")
def get_admin_what_changed(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide comparison between current period and previous period."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_WHAT_CHANGED_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})

    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {
            "focusRateChange": None,
            "workHoursChange": None,
            "wellbeingChange": None,
            "recommendationAcceptanceChange": None
        }

    curr_start, curr_end = parse_date_range(start_date, end_date, period, user_tz)
    prev_start, prev_end = get_previous_start_end_for_period(period, user_tz)

    def compute_metrics(start, end):
        sessions = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
            WorkSession.started_at < end,
            or_(WorkSession.ended_at == None, WorkSession.ended_at >= start)
        ).all()

        total_work_secs = 0.0
        total_task_secs = 0.0
        for s in sessions:
            s_end = s.ended_at or datetime.now(timezone.utc)
            dur = (s_end - s.started_at).total_seconds()
            total_work_secs += max(0, dur)
            tasks = db.query(Task).filter(Task.work_session_id == s.id, Task.started_at.isnot(None)).all()
            breaks = db.query(Break).filter(Break.work_session_id == s.id, Break.ended_at.isnot(None)).all()
            total_task_secs += calculate_unique_task_seconds(tasks, s.started_at, s_end, breaks)

        focus_rate = (total_task_secs / total_work_secs * 100.0) if total_work_secs > 0 else 0.0
        work_hours = total_work_secs / 3600.0

        checkins = db.query(SessionWellbeingCheckin).join(User).join(OrganizationMembership).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
            SessionWellbeingCheckin.created_at >= start,
            SessionWellbeingCheckin.created_at < end
        ).all()
        wb_score = (sum(c.overall_wellbeing for c in checkins) / len(checkins)) if checkins else 0.0

        recs = db.query(RecommendationFeedback).join(User).join(OrganizationMembership).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
            RecommendationFeedback.timestamp >= start,
            RecommendationFeedback.timestamp < end
        ).all()
        total_recs = len(recs)
        accepted_recs = sum(1 for r in recs if r.user_action == 'accepted')
        rec_acc_rate = (accepted_recs / total_recs * 100.0) if total_recs > 0 else 0.0

        return {
            "focus_rate": focus_rate,
            "work_hours": work_hours,
            "wellbeing": wb_score,
            "recommendation_acceptance": rec_acc_rate,
            "has_data": len(sessions) > 0 or len(checkins) > 0 or len(recs) > 0
        }

    curr = compute_metrics(curr_start, curr_end)
    prev = compute_metrics(prev_start, prev_end)

    def format_change(curr_val, prev_val, has_prev_data, suffix="%"):
        if not has_prev_data:
            return None
        diff = curr_val - prev_val
        if abs(diff) < 0.05:
            return "0.0%" if suffix == "%" else "0.0h"
        sign = "+" if diff > 0 else ""
        return f"{sign}{diff:.1f}{suffix}"

    has_prev = prev["has_data"]

    return {
        "focusRateChange": format_change(curr["focus_rate"], prev["focus_rate"], has_prev, "%"),
        "workHoursChange": format_change(curr["work_hours"], prev["work_hours"], has_prev, "h"),
        "wellbeingChange": format_change(curr["wellbeing"], prev["wellbeing"], has_prev, ""),
        "recommendationAcceptanceChange": format_change(curr["recommendation_acceptance"], prev["recommendation_acceptance"], has_prev, "%")
    }


@router.get("/admin/break-patterns")
def get_admin_break_patterns(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get organization-wide break type breakdown."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_BREAK_PATTERNS_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"byType": [], "totalBreaks": 0, "totalBreakHours": 0.0}

    include_test = should_include_test_data(db, current_user)
    ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
        WorkSession.started_at < end,
        or_(WorkSession.ended_at == None, WorkSession.ended_at >= start)
    )
    if not include_test:
        ws_q = ws_q.filter(Profile.is_test_data == False)
    work_sessions = ws_q.all()

    if not work_sessions:
        return {"byType": [], "totalBreaks": 0, "totalBreakHours": 0.0}

    session_ids = [s.id for s in work_sessions]
    breaks = db.query(Break).filter(
        Break.work_session_id.in_(session_ids),
        Break.started_at >= start,
        Break.started_at <= end,
        Break.ended_at.isnot(None)
    ).all()

    type_counts = {}
    type_seconds = {}
    for b in breaks:
        b_type = b.break_type or "OTHER"
        dur = max(0, (b.ended_at - b.started_at).total_seconds())
        type_counts[b_type] = type_counts.get(b_type, 0) + 1
        type_seconds[b_type] = type_seconds.get(b_type, 0.0) + dur

    by_type = []
    for b_type, count in type_counts.items():
        by_type.append({
            "type": b_type,
            "count": count,
            "totalHours": round(type_seconds.get(b_type, 0.0) / 3600.0, 2),
            "avgMinutes": round((type_seconds.get(b_type, 0.0) / count) / 60.0, 1) if count > 0 else 0.0
        })

    by_type.sort(key=lambda x: x["count"], reverse=True)

    total_breaks = len(breaks)
    total_break_hours = round(sum(type_seconds.values()) / 3600.0, 2)

    return {
        "byType": by_type,
        "totalBreaks": total_breaks,
        "totalBreakHours": total_break_hours
    }


@router.get("/admin/team-comparison-chart")
def get_admin_team_comparison_chart(
    period: Optional[str] = "this_week",
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get simplified team comparison data for charting (respects N>=3 privacy)."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_ANALYTICS_TEAM_COMPARISON_CHART_ACCESSED", action_details={"period": period, "start_date": start_date, "end_date": end_date})
    settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    user_tz = settings.timezone if settings and settings.timezone else "UTC"
    start, end = parse_date_range(start_date, end_date, period, user_tz)

    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        return {"teams": [], "period": period, "start_date": start.isoformat(), "end_date": end.isoformat()}

    include_test = should_include_test_data(db, current_user)
    teams = db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True).all()

    week_start_date = start.date() - timedelta(days=start.date().weekday())

    team_data = []
    for team in teams:
        memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [m.profile_id for m in memberships]
        prof_q = db.query(Profile).filter(Profile.id.in_(p_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()
        profile_ids = [p.id for p in profiles]
        total_employees = len(profile_ids)
        is_suppressed = total_employees < 3

        if is_suppressed:
            team_data.append({
                "team_id": str(team.id),
                "team_name": team.name,
                "active_employees": total_employees,
                "privacy_suppressed": True,
                "total_work_hours": None,
                "avg_work_hours_per_employee": None,
                "sustainability_index": None,
                "avg_wlb_score": None,
                "completed_tasks": None
            })
            continue

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id.in_(profile_ids),
            WorkSession.started_at >= start,
            WorkSession.started_at <= end
        ).all()

        total_work_secs = sum(max(0, ((s.ended_at or datetime.now(timezone.utc)) - s.started_at).total_seconds()) for s in sessions)
        total_work_hours = round(total_work_secs / 3600.0, 2)
        avg_hours = round(total_work_hours / max(1, total_employees), 2)

        tasks = db.query(Task).filter(
            Task.profile_id.in_(profile_ids),
            Task.created_at >= start,
            Task.created_at <= end
        ).all()
        completed_tasks = len([t for t in tasks if t.status == 'DONE'])

        wsi_metrics = AnalyticsEngine.calculate_organization_work_sustainability(db, org_ids, start, end, include_test=include_test)

        surveys = db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= week_start_date - timedelta(days=21)
        ).all()
        avg_wlb = round(sum(s.score for s in surveys) / len(surveys), 2) if surveys else 0.0

        team_data.append({
            "team_id": str(team.id),
            "team_name": team.name,
            "active_employees": total_employees,
            "privacy_suppressed": False,
            "total_work_hours": total_work_hours,
            "avg_work_hours_per_employee": avg_hours,
            "sustainability_index": wsi_metrics.get("sustainabilityIndex", 100.0),
            "avg_wlb_score": avg_wlb,
            "completed_tasks": completed_tasks
        })

    return {
        "teams": team_data,
        "period": period,
        "start_date": start.isoformat(),
        "end_date": end.isoformat()
    }


@router.get("/admin/reports/preview")
def get_admin_reports_preview(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Get comprehensive JSON preview of organization-level report (all 9 sections)."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_REPORT_PREVIEW_ACCESSED", action_details={"period": period})
    service = AdminOrganizationReportService(db, current_user)
    return service.generate_preview(period=period, start_date=start_date, end_date=end_date)


@router.get("/admin/reports/export/pdf", response_class=StreamingResponse)
def export_admin_reports_pdf(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Export comprehensive professional PDF report for organization analytics."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_PDF_REPORT_EXPORTED", action_details={"period": period})
    service = AdminOrganizationReportService(db, current_user)
    pdf_bytes = service.generate_pdf(period=period, start_date=start_date, end_date=end_date)
    filename = f"intellibreak_admin_report_{date.today()}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@router.get("/admin/reports/export/xlsx", response_class=StreamingResponse)
def export_admin_reports_xlsx(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Export multi-sheet Excel workbook (.xlsx) covering all 9 report sections."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_XLSX_REPORT_EXPORTED", action_details={"period": period})
    service = AdminOrganizationReportService(db, current_user)
    xlsx_bytes = service.generate_excel(period=period, start_date=start_date, end_date=end_date)
    filename = f"intellibreak_admin_report_{date.today()}.xlsx"
    return StreamingResponse(
        io.BytesIO(xlsx_bytes),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@router.get("/admin/reports/export/csv", response_class=StreamingResponse)
def export_admin_reports_csv(
    period: Optional[str] = Query("this_week", description="Period: today, yesterday, this_week, last_week, this_month, last_month"),
    start_date: Optional[str] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, description="End date (YYYY-MM-DD)"),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """Export multi-section CSV reports packaged as a ZIP archive (.zip)."""
    log_system_activity(db=db, user_id=current_user.id, action_type="ADMIN_CSV_REPORT_EXPORTED", action_details={"period": period})
    service = AdminOrganizationReportService(db, current_user)
    zip_bytes = service.generate_csv_zip(period=period, start_date=start_date, end_date=end_date)
    filename = f"intellibreak_admin_reports_{date.today()}.zip"
    return StreamingResponse(
        io.BytesIO(zip_bytes),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )
