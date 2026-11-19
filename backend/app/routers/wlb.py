from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date, datetime, timezone, timedelta
import uuid

from ..database import get_db
from ..models import User, Profile, OrganizationMembership, WorkLifeBalanceSurvey, UserSettings, Team, TeamMembership
from ..auth.security import get_current_user
from ..schemas.wlb import (
    WorkLifeBalanceSurveyCreate,
    WorkLifeBalanceSurveyResponse,
    WorkLifeBalanceCheckResponse
)
from ..services.wlb_analysis_service import WLBAnalysisService

router = APIRouter(prefix="/wlb", tags=["Work-Life Balance Survey"])

def get_employee_profile_and_org(db: Session, current_user: User) -> tuple[Profile, uuid.UUID]:
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Employee profile not found.")

    membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED"
    ).first()
    if not membership:
        raise HTTPException(status_code=403, detail="Active approved organization membership required.")

    return profile, membership.organization_id

def get_user_timezone_today(db: Session, user_id: uuid.UUID) -> date:
    settings = db.query(UserSettings).filter(UserSettings.user_id == user_id).first()
    tz_str = settings.timezone if settings and settings.timezone else None
    if tz_str:
        try:
            from zoneinfo import ZoneInfo
            now_tz = datetime.now(ZoneInfo(tz_str))
            return now_tz.date()
        except Exception:
            pass
    return datetime.now(timezone.utc).date()

@router.post("/survey", response_model=WorkLifeBalanceSurveyResponse, status_code=status.HTTP_201_CREATED)
def submit_wlb_survey(
    payload: WorkLifeBalanceSurveyCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Submit weekly employee-reported Work-Life Balance survey.
    Score calculation is computed exclusively server-side: WLB Score = ((sum of ratings - 5) / 20) * 100.
    Enforces one submission per employee per reporting week, preventing overwrites.
    """
    profile, org_id = get_employee_profile_and_org(db, current_user)

    # Check for duplicate submission for this week
    existing = db.query(WorkLifeBalanceSurvey).filter(
        WorkLifeBalanceSurvey.profile_id == profile.id,
        WorkLifeBalanceSurvey.week_start_date == payload.week_start_date
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A Work-Life Balance survey for this week has already been submitted. Overwrites are not permitted."
        )

    ratings = [
        payload.rating_disconnect,
        payload.rating_personal_time,
        payload.rating_responsibilities_balance,
        payload.rating_schedule_satisfaction,
        payload.rating_recovery
    ]

    sum_ratings = sum(ratings)
    # Server-side authoritative score calculation
    score = round(((sum_ratings - 5.0) / 20.0) * 100.0, 2)
    score = max(0.0, min(100.0, score))

    survey = WorkLifeBalanceSurvey(
        profile_id=profile.id,
        organization_id=org_id,
        week_start_date=payload.week_start_date,
        rating_disconnect=payload.rating_disconnect,
        rating_personal_time=payload.rating_personal_time,
        rating_responsibilities_balance=payload.rating_responsibilities_balance,
        rating_schedule_satisfaction=payload.rating_schedule_satisfaction,
        rating_recovery=payload.rating_recovery,
        score=score,
        submitted_at=datetime.now(timezone.utc)
    )

    db.add(survey)
    db.commit()
    db.refresh(survey)
    return survey

@router.get("/survey/history", response_model=List[WorkLifeBalanceSurveyResponse])
def get_wlb_survey_history(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Retrieve the employee's own WLB survey submission history (isolated per user)."""
    profile, _ = get_employee_profile_and_org(db, current_user)
    surveys = db.query(WorkLifeBalanceSurvey).filter(
        WorkLifeBalanceSurvey.profile_id == profile.id
    ).order_by(WorkLifeBalanceSurvey.week_start_date.desc()).all()
    return surveys

@router.get("/survey/check", response_model=WorkLifeBalanceCheckResponse)
def check_wlb_survey(
    week_start_date: Optional[date] = Query(None, description="Monday of the target week. Defaults to current week Monday in user/org timezone."),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Check whether the reporting week has already been submitted by the employee."""
    profile, _ = get_employee_profile_and_org(db, current_user)

    if not week_start_date:
        local_today = get_user_timezone_today(db, current_user.id)
        week_start_date = local_today - timedelta(days=local_today.weekday())

    survey = db.query(WorkLifeBalanceSurvey).filter(
        WorkLifeBalanceSurvey.profile_id == profile.id,
        WorkLifeBalanceSurvey.week_start_date == week_start_date
    ).first()

    return {
        "week_start_date": week_start_date,
        "submitted": survey is not None,
        "survey": survey
    }


# ============================================================================
# WLB Analysis Endpoints (Employee-facing)
# ============================================================================

@router.get("/analysis/weekly")
def get_weekly_wlb_analysis(
    week_start: Optional[date] = Query(None, description="Week start Monday (YYYY-MM-DD). Defaults to current week."),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get comprehensive WLB analysis for a specific week.
    Combines questionnaire scores with behavioral telemetry indicators.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    if not week_start:
        today = date.today()
        week_start = today - timedelta(days=today.weekday())

    service = WLBAnalysisService(db)
    return service.get_weekly_wlb_analysis(profile.id, week_start)


@router.get("/analysis/employee/{employee_id}")
def get_employee_wlb_analysis(
    employee_id: uuid.UUID,
    week_start: Optional[date] = Query(None, description="Week start date (YYYY-MM-DD). Defaults to current week."),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get an employee's classification only for an authorized manager/admin."""
    if current_user.role not in ("MANAGER", "ADMIN"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Manager or administrator access required")

    profile = db.query(Profile).filter(Profile.id == employee_id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee profile not found")

    if current_user.role != "ADMIN":
        if current_user.role != "MANAGER":
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Manager access required")
        managed_team_ids = [team_id for (team_id,) in db.query(Team.id).filter(
            Team.manager_user_id == current_user.id,
            Team.is_active.is_(True),
        ).all()]
        membership = db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.profile_id == profile.id,
            TeamMembership.left_at.is_(None),
        ).first() if managed_team_ids else None
        if membership is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this employee")

    target_week = week_start or (date.today() - timedelta(days=date.today().weekday()))
    analysis = WLBAnalysisService(db).get_weekly_wlb_analysis(profile.id, target_week)
    safe_concern_types = {
        "SUSTAINED_OVERTIME", "RECURRING_OVERTIME", "LOW_BREAK_COMPLIANCE",
        "LOW_FOCUS_RATE", "IRREGULAR_SCHEDULE",
    }
    safe_pattern_ids = {
        "RECURRING_OVERWORK", "REPEATED_SKIPPED_BREAKS", "DECLINING_MEASURABLE_FOCUS",
    }
    safe_indicator_keys = {
        "total_work_hours", "avg_daily_hours", "work_days", "overtime_days",
        "overtime_severe_days", "total_overtime_hours", "target_daily_hours",
        "break_compliance_pct", "avg_break_minutes_per_day", "avg_focus_rate",
        "work_schedule_irregularity",
    }

    work_pattern_concerns = [
        {key: value for key, value in concern.items() if key in ("type", "severity", "description", "metric_value")}
        for concern in analysis["behavioral_indicators"].get("concerns", [])
        if str(concern.get("type", "")).upper() in safe_concern_types
    ]
    # Include work_patterns evidence for safe concern types
    work_patterns_evidence = [
        {key: value for key, value in item.items() if key in ("source", "type", "description", "severity", "metric_value")}
        for item in analysis["employee_status"].get("evidence", [])
        if item.get("source") == "work_patterns"
        and str(item.get("type", "")).upper() in safe_concern_types
    ]
    # If there's a survey evidence item, include a generic employee_report indicator
    survey_evidence = [
        {"source": "employee_report", "description": "Employee-reported survey concern present."}
        for item in analysis["employee_status"].get("evidence", [])
        if item.get("source") == "survey"
    ]
    safe_evidence = survey_evidence + work_patterns_evidence
    if work_pattern_concerns:
        status_summary = {
            "classification": "NEEDS_ATTENTION",
            "data_completeness": analysis["employee_status"].get("data_completeness", "partial"),
            "evidence": safe_evidence,
            "explanation": "Some recorded work patterns may benefit from a supportive review. This is not a diagnosis or disciplinary assessment.",
            "manager_review_recommended": True,
        }
    else:
        status_summary = {
            "classification": "HEALTHY",
            "data_completeness": analysis["employee_status"].get("data_completeness", "insufficient"),
            "evidence": [],
            "explanation": "No operational work-pattern concerns were identified in the available records.",
            "manager_review_recommended": False,
        }

    safe_indicators = {
        key: value for key, value in analysis["behavioral_indicators"].items()
        if key in safe_indicator_keys
    }
    safe_indicators["concern_count"] = len(work_pattern_concerns)
    historical_patterns = []
    for pattern in analysis.get("historical_patterns", []):
        if str(pattern.get("pattern_id", "")).upper() not in safe_pattern_ids:
            continue
        measurements = pattern.get("measurements", {})
        safe_measurements = {
            key: value for key, value in measurements.items()
            if key in {
                "target_daily_hours", "overwork_days_count", "recent_daily_hours_avg",
                "sessions_exceeding_60min", "sessions_with_zero_breaks", "skipped_break_ratio",
                "baseline_median_focus_rate", "recent_average_focus_rate",
            }
        }
        historical_patterns.append({
            "pattern_id": pattern["pattern_id"],
            "evidence_strength": pattern.get("evidence_strength"),
            "measurements": safe_measurements,
            "observation_period": pattern.get("observation_period"),
            "observation_count": pattern.get("observation_count"),
            "data_limitations": "Based on recorded work-session activity; unlogged activity may not be captured.",
        })

    return {
        "profile_id": analysis["profile_id"],
        "week_start": analysis["week_start"],
        "week_end": analysis["week_end"],
        "risk_tier": None,
        "employee_status": status_summary,
        "behavioral_indicators": safe_indicators,
        "work_pattern_concerns": work_pattern_concerns,
        "historical_patterns": historical_patterns,
        "data_quality": {
            "sessions_count": analysis.get("data_quality", {}).get("sessions_count", 0),
            "has_wlb_survey": analysis.get("data_quality", {}).get("has_wlb_survey", False),
        },
    }


@router.get("/analysis/trends")
def get_wlb_trends(
    weeks: int = Query(8, ge=2, le=26, description="Number of weeks to analyze"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get WLB trends over multiple weeks."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    service = WLBAnalysisService(db)
    return service.get_wlb_trends(profile.id, weeks)
