import uuid
from typing import Optional, List, Dict, Any
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
import statistics

from ..models import User, Profile, TeamMembership, Team, WorkSession, Break, Task, SessionWellbeingCheckin, RecommendationFeedback, OrganizationMembership, WorkLifeBalanceSurvey
from ..auth.security import should_include_test_data
from .wellbeing_monitoring import WellbeingMonitoringService, resolve_reporting_week
from .analytics_service import AnalyticsEngine
from .cache_service import analytics_cache
from ..analytics_utils import ensure_utc, calculate_unique_task_seconds


def calculate_team_recommendation_statistics(
    db: Session,
    team_id: uuid.UUID,
    start_dt: datetime,
    end_dt: datetime,
    include_test: bool = False
) -> Dict[str, Any]:
    """
    Calculate team-level recommendation statistics with category breakdown.
    Includes: counts by status, acceptance rates by category, model distribution.
    """
    # Get team members (current only)
    memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id == team_id,
        TeamMembership.left_at.is_(None)
    ).all()

    profile_ids = [m.profile_id for m in memberships]

    if not profile_ids:
        return {
            "total_generated": 0,
            "total_accepted": 0,
            "total_dismissed": 0,
            "acceptance_rate": 0.0,
            "category_breakdown": {},
            "data_quality": "insufficient_data"
        }

    # Get user IDs from profiles
    profiles = db.query(Profile).filter(Profile.id.in_(profile_ids)).all()

    # Filter test data if needed
    if not include_test:
        profiles = [p for p in profiles if not p.is_test_data]

    if not profiles:
        return {
            "total_generated": 0,
            "total_accepted": 0,
            "total_dismissed": 0,
            "acceptance_rate": 0.0,
            "category_breakdown": {},
            "data_quality": "insufficient_data"
        }

    user_ids = [p.user_id for p in profiles]

    # Query recommendation feedback for team members in date range
    feedbacks = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.user_id.in_(user_ids),
        RecommendationFeedback.timestamp >= start_dt,
        RecommendationFeedback.timestamp <= end_dt
    ).all()

    # Overall counts
    total_generated = len(feedbacks)
    total_accepted = sum(1 for f in feedbacks if f.user_action == "accepted")
    total_dismissed = sum(1 for f in feedbacks if f.user_action == "dismissed")

    # Acceptance rate
    acceptance_rate = round((total_accepted / total_generated * 100.0), 2) if total_generated > 0 else 0.0

    # Category breakdown with per-category acceptance rates
    category_stats = {}
    candidate_types = ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]
    for rec_type in candidate_types:
        type_feedbacks = [f for f in feedbacks if f.recommendation_type == rec_type]
        if type_feedbacks:
            type_generated = len(type_feedbacks)
            type_accepted = sum(1 for f in type_feedbacks if f.user_action == "accepted")
            type_acceptance_rate = round((type_accepted / type_generated * 100.0), 2)

            category_stats[rec_type] = {
                "generated": type_generated,
                "accepted": type_accepted,
                "acceptance_rate": type_acceptance_rate
            }

    return {
        "total_generated": total_generated,
        "total_accepted": total_accepted,
        "total_dismissed": total_dismissed,
        "acceptance_rate": acceptance_rate,
        "category_breakdown": category_stats,
        "data_quality": "sufficient_data" if total_generated > 0 else "insufficient_data"
    }


def compute_team_analytics(
    db: Session,
    current_user: User,
    team_id: Optional[uuid.UUID] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
) -> Dict[str, Any]:
    """
    Shared authoritative aggregation layer for Manager Analytics and Report Exports (PDF, Excel, CSV).
    Ensures 100% consistent team scope, profile resolution, date filtering, test-data isolation,
    work hours, tasks, recommendation feedback, and wellbeing metrics.
    """
    today = date.today()
    if start_date:
        effective_start = start_date
        effective_end = end_date or today
        has_start_bound = True
    else:
        effective_start = None
        effective_end = end_date or today
        has_start_bound = False

    start_dt = datetime.combine(effective_start, datetime.min.time(), tzinfo=timezone.utc) if has_start_bound else None
    end_dt = datetime.combine(effective_end, datetime.max.time(), tzinfo=timezone.utc)

    include_test = should_include_test_data(db, current_user)

    # Resolve authorized teams
    manager_teams = db.query(Team).filter(
        Team.manager_user_id == current_user.id,
        Team.is_active == True
    )
    if current_user.role == "ADMIN":
        admin_org_ids = [m.organization_id for m in db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == current_user.id,
            OrganizationMembership.status == "APPROVED",
        ).all()]
        if not admin_org_ids:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin has no approved organization membership")
        manager_teams = manager_teams.filter(Team.organization_id.in_(admin_org_ids))
    if team_id:
        manager_teams = manager_teams.filter(Team.id == team_id)
    managed_teams = manager_teams.all()
    if team_id and not managed_teams:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this team")
    managed_team_ids = [t.id for t in managed_teams]

    profile_ids = []
    if not managed_team_ids and current_user.role == "ADMIN":
        org_ids = [m.organization_id for m in db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == current_user.id,
            OrganizationMembership.status == "APPROVED"
        ).all()]
        if not org_ids:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin has no approved organization membership",
            )
        prof_q = db.query(Profile).join(User, Profile.user_id == User.id).join(OrganizationMembership, Profile.user_id == OrganizationMembership.user_id).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
            User.role != "ADMIN"
        )
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()
        profile_ids = [p.id for p in profiles]
    elif managed_team_ids:
        memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [m.profile_id for m in memberships]
        prof_q = db.query(Profile).filter(Profile.id.in_(p_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()
        profile_ids = [p.id for p in profiles]
    else:
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if profile:
            profile_ids = [profile.id]

    total_employees = len(profile_ids)

    # Cache lookup after RBAC and profile scope resolution
    cache_key = (
        str(current_user.id),
        current_user.role,
        str(team_id) if team_id else None,
        str(effective_start) if effective_start else None,
        str(effective_end) if effective_end else None,
        include_test,
        tuple(sorted(profile_ids))
    )
    cached_result = analytics_cache.get(cache_key)
    if cached_result is not None:
        return cached_result

    # Work sessions & breaks
    session_query = db.query(WorkSession).filter(
        WorkSession.profile_id.in_(profile_ids),
        WorkSession.started_at <= end_dt
    ) if profile_ids else db.query(WorkSession).filter(False)
    if has_start_bound and start_dt:
        session_query = session_query.filter(WorkSession.started_at >= start_dt)
    sessions = session_query.all()

    total_work_secs = 0.0
    total_break_secs = 0.0
    session_ids = [s.id for s in sessions]
    session_breaks = {}
    if session_ids:
        all_breaks = db.query(Break).filter(
            Break.work_session_id.in_(session_ids),
            Break.ended_at.isnot(None)
        ).all()
        for b in all_breaks:
            session_breaks.setdefault(b.work_session_id, []).append(b)

    for s in sessions:
        s_start = ensure_utc(s.started_at)
        s_end = ensure_utc(s.ended_at) or datetime.now(timezone.utc)
        if s_start:
            total_work_secs += max(0, (s_end - s_start).total_seconds())
        breaks = session_breaks.get(s.id, [])
        for b in breaks:
            b_start = ensure_utc(b.started_at)
            b_end = ensure_utc(b.ended_at)
            if b_start and b_end:
                total_break_secs += max(0, (b_end - b_start).total_seconds())

    # Deduct breaks from total work seconds
    total_work_secs = max(0.0, total_work_secs - total_break_secs)
    total_work_hours = round(total_work_secs / 3600.0, 2)
    total_break_hours = round(total_break_secs / 3600.0, 2)
    avg_hours_per_emp = round(total_work_hours / max(1, total_employees), 2)

    # Tasks (fetched early for batched session focus calculation)
    task_query = db.query(Task).filter(
        Task.profile_id.in_(profile_ids),
        Task.created_at <= end_dt
    ) if profile_ids else db.query(Task).filter(False)
    if has_start_bound and start_dt:
        task_query = task_query.filter(Task.created_at >= start_dt)
    tasks = task_query.all()

    session_tasks = {}
    for t in tasks:
        if t.work_session_id:
            session_tasks.setdefault(t.work_session_id, []).append(t)

    total_focused_secs = 0.0
    for s in sessions:
        s_start = ensure_utc(s.started_at)
        s_end = ensure_utc(s.ended_at) or datetime.now(timezone.utc)
        s_breaks = session_breaks.get(s.id, [])
        s_t = session_tasks.get(s.id, [])
        if s_start:
            total_focused_secs += calculate_unique_task_seconds(s_t, s_start, s_end, s_breaks)
    focus_rate = round((total_focused_secs / total_work_secs * 100.0) if total_work_secs > 0 else 0.0, 1)
    total_tasks = len(tasks)
    completed_tasks = len([t for t in tasks if t.status == 'DONE'])
    completion_rate = round((completed_tasks / total_tasks * 100.0) if total_tasks > 0 else 0.0, 1)

    # Recommendation feedback
    feedback_query = db.query(RecommendationFeedback).join(User, RecommendationFeedback.user_id == User.id).join(Profile, User.id == Profile.user_id).filter(
        Profile.id.in_(profile_ids),
        RecommendationFeedback.timestamp <= end_dt
    ) if profile_ids else db.query(RecommendationFeedback).filter(False)
    if not include_test:
        feedback_query = feedback_query.filter(Profile.is_test_data == False)
    if has_start_bound and start_dt:
        feedback_query = feedback_query.filter(RecommendationFeedback.timestamp >= start_dt)
    feedback = feedback_query.all()

    total_recs = len(feedback)
    accepted_recs = len([f for f in feedback if f.user_action == 'accepted'])
    dismissed_recs = len([f for f in feedback if f.user_action == 'dismissed'])
    acceptance_rate = round((accepted_recs / total_recs * 100.0) if total_recs > 0 else 0.0, 1)

    # Wellbeing overview - resolve reporting week via shared authoritative resolver
    overview_week_start = resolve_reporting_week(db, profile_ids, start_date)

    wb_service = WellbeingMonitoringService(db)
    overview = wb_service.compute_team_overview(
        manager_id=current_user.id,
        week_start=overview_week_start,
        team_id=team_id
    )

    # Team-level Work Sustainability Index
    team_ids = [t.id for t in managed_teams] if managed_team_ids else []
    wsi_data = {}
    if team_ids and has_start_bound and start_dt:
        wsi_data = AnalyticsEngine.calculate_team_work_sustainability(
            db, team_ids, start_dt, end_dt, include_test=include_test
        )
    elif team_ids:
        # No start bound: still calculate but indicate lack of explicit bounds
        wsi_data = AnalyticsEngine.calculate_team_work_sustainability(
            db, team_ids, start_dt, end_dt, include_test=include_test
        )

    # Team-level Work-Life Balance aggregation
    wlb_surveys_query = db.query(WorkLifeBalanceSurvey).filter(
        WorkLifeBalanceSurvey.profile_id.in_(profile_ids)
    )
    if has_start_bound and start_dt:
        lookback_start = (start_dt.date() if isinstance(start_dt, datetime) else start_dt) - timedelta(days=21)
        wlb_surveys_query = wlb_surveys_query.filter(
            WorkLifeBalanceSurvey.week_start_date >= lookback_start
        )
    wlb_surveys = wlb_surveys_query.all() if profile_ids else []

    from .admin_organization_report_service import AdminOrganizationReportService
    wlb_data = AdminOrganizationReportService.compute_wlb_aggregates(wlb_surveys)

    result = {
        "profile_ids": profile_ids,
        "total_employees": total_employees,
        "sessions": sessions,
        "session_count": len(sessions),
        "total_work_hours": total_work_hours,
        "total_break_hours": total_break_hours,
        "avg_hours_per_emp": avg_hours_per_emp,
        "focus_rate": focus_rate,
        "tasks": tasks,
        "total_tasks": total_tasks,
        "completed_tasks": completed_tasks,
        "completion_rate": completion_rate,
        "feedback": feedback,
        "total_recs": total_recs,
        "accepted_recs": accepted_recs,
        "dismissed_recs": dismissed_recs,
        "acceptance_rate": acceptance_rate,
        "overview": overview,
        "wsi": wsi_data.get("sustainabilityIndex") if wsi_data else None,
        "wsi_detail": wsi_data,
        "wlb": wlb_data,
        "start_date": effective_start,
        "end_date": effective_end,
    }

    analytics_cache.set(cache_key, result)
    return result

