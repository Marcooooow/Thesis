from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional, List
from datetime import date, datetime, timezone, timedelta
import uuid

from ..database import get_db
from ..auth.security import get_current_active_user, log_system_activity, should_include_test_data
from ..models import User, Profile, TeamMembership, Team, RecommendationFeedback, WorkSession, Break, WorkLifeBalanceSurvey
from ..services.wellbeing_monitoring import WellbeingMonitoringService
from ..services.team_analytics_service import compute_team_analytics

router = APIRouter(
    prefix="/manager/analytics",
    tags=["manager-analytics"],
    responses={404: {"description": "Not found"}},
)


def _project_next_week(
    values: List[Optional[float]],
    lower: float,
    upper: float,
    steps_ahead: int = 1,
) -> Optional[dict]:
    """Project ahead from weekly aggregate values using a small linear trend."""
    points = [(index, float(value)) for index, value in enumerate(values) if value is not None]
    if len(points) < 3 or values[-1] is None:
        return None

    mean_x = sum(index for index, _ in points) / len(points)
    mean_y = sum(value for _, value in points) / len(points)
    denominator = sum((index - mean_x) ** 2 for index, _ in points)
    if denominator == 0:
        return None

    slope = sum((index - mean_x) * (value - mean_y) for index, value in points) / denominator
    forecast_index = len(values) - 1 + steps_ahead
    projected = mean_y + slope * (forecast_index - mean_x)
    projected = max(lower, min(upper, projected))
    return {
        "last_week": round(points[-1][1], 1),
        "projected_next_week": round(projected, 1),
        "change": round(projected - points[-1][1], 1),
        "observed_weeks": len(points),
    }


def _get_current_manager_or_admin(current_user: User = Depends(get_current_active_user)) -> User:
    if current_user.role not in ["MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to managers and administrators",
        )
    return current_user


@router.get("/team-summary")
def get_manager_team_summary(
    week_start: Optional[date] = Query(None, description="Week start Monday. Defaults to current week if no start_date."),
    start_date: Optional[date] = Query(None, description="Start date for custom range (YYYY-MM-DD). If omitted, unbounded lower bound (All time)."),
    end_date: Optional[date] = Query(None, description="End date for custom range (YYYY-MM-DD). Defaults to today."),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter."),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Manager team analytics overview.
    Requires MANAGER/ADMIN role; only exposes group aggregates for >=5 employees.
    Enforces is_test_data isolation and RBAC via TeamMembership.
    Supports flexible date range filtering (7 days, 30 days, unbounded All time / All available data).
    """
    effective_start = start_date or week_start
    analytics = compute_team_analytics(db, current_user, team_id=team_id, start_date=effective_start, end_date=end_date)
    profile_ids = analytics["profile_ids"]

    if len(profile_ids) < 5:
        return {
            "start_date": str(analytics["start_date"]) if analytics["start_date"] else None,
            "end_date": str(analytics["end_date"]),
            "team_id": str(team_id) if team_id else None,
            # Do not return an exact small-group size; it can identify members
            # in a known team roster.
            "total_employees": None if profile_ids else 0,
            "aggregate_wellbeing": None,
            "work_sustainability": None,
            "workload_summary": None,
            "work_life_balance": None,
            "recommendation_effectiveness": None,
            "privacy_suppressed": len(profile_ids) > 0,
            "note": "Not enough people to show this safely. At least 5 authorized employees are required." if len(profile_ids) > 0 else "No managed teams found.",
        }

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="MANAGER_ANALYTICS_TEAM_SUMMARY_ACCESSED",
        action_details={"start_date": str(analytics["start_date"]) if analytics["start_date"] else "unbounded", "end_date": str(analytics["end_date"]), "team_id": str(team_id) if team_id else None}
    )

    overview = analytics["overview"]
    # The monitoring service's team_summary.by_tier is a three-tier distribution
    # (green/amber/red), while its employee summaries carry the authoritative
    # five-tier classifications shown in the Well-being screen. Do not read
    # five-tier keys from the three-tier map: that silently reports all zeros.
    by_tier = {"low": 0, "moderate": 0, "high": 0, "critical": 0, "insufficient_data": 0}
    privacy_suppressed = bool(overview and overview.team_summary and overview.team_summary.privacy_suppressed)
    if overview and overview.team_summary:
        if privacy_suppressed:
            # Preserve the existing privacy behavior. Three-tier aggregates do
            # not let us distinguish high from critical, so report the combined
            # red count as high and leave critical at zero in suppressed groups.
            three_tier = overview.team_summary.by_tier or {}
            by_tier["low"] = three_tier.get("green", 0)
            by_tier["moderate"] = three_tier.get("amber", 0)
            by_tier["high"] = three_tier.get("red", 0)
            by_tier["insufficient_data"] = three_tier.get("insufficient_data", 0)
        else:
            for employee in overview.employees or []:
                # RiskTier is an IntEnum (LOW=1 ... CRITICAL=4), so `.value`
                # yields a number. Use its symbolic name for the API keys.
                risk_tier = employee.risk_tier
                tier = getattr(risk_tier, "name", None)
                if tier is None:
                    tier = str(risk_tier)
                tier = tier.lower()
                if tier.isdigit():
                    tier = {"0": "insufficient_data", "1": "low", "2": "moderate", "3": "high", "4": "critical"}.get(tier, tier)
                if tier in by_tier:
                    by_tier[tier] += 1

    # Build WSI response
    wsi_detail = analytics.get("wsi_detail", {})
    wsi_response = None
    if wsi_detail:
        wsi_response = {
            "wsi": wsi_detail.get("sustainabilityIndex"),
            "overtime_frequency": wsi_detail.get("overtimeFrequency"),
            "break_compliance": wsi_detail.get("breakCompliance"),
            "long_sessions_count": wsi_detail.get("longSessionsCount"),
            "late_shift_endings_count": wsi_detail.get("lateShiftEndingsCount"),
            "missed_breaks_count": wsi_detail.get("missedBreaksCount"),
            "total_workdays_analyzed": wsi_detail.get("totalWorkdaysAnalyzed"),
            "data_quality": "insufficient_data" if wsi_detail.get("totalWorkdaysAnalyzed", 0) == 0 else "sufficient_data"
        }

    # Build WLB response
    wlb_data = analytics.get("wlb", {})
    wlb_response = None
    if wlb_data and wlb_data.get("data_quality") != "insufficient_data":
        wlb_response = {
            "avg_score": wlb_data.get("avg_score"),
            "respondents": wlb_data.get("respondents"),
            "rating_disconnect": wlb_data.get("rating_disconnect"),
            "rating_personal_time": wlb_data.get("rating_personal_time"),
            "rating_recovery": wlb_data.get("rating_recovery"),
            "data_quality": wlb_data.get("data_quality")
        }

    return {
        "start_date": str(analytics["start_date"]) if analytics["start_date"] else None,
        "end_date": str(analytics["end_date"]),
        "team_id": str(team_id) if team_id else None,
        "total_employees": analytics["total_employees"],
        "aggregate_wellbeing": {
            "reporting_period": {
                "start_date": str(overview.week_start) if overview else None,
                "end_date": str(overview.week_end) if overview else None,
            },
            "total_monitored": analytics["total_employees"],
            "low": by_tier.get("low", 0),
            "moderate": by_tier.get("moderate", 0),
            "high": by_tier.get("high", 0),
            "critical": by_tier.get("critical", 0),
            "insufficient_data": by_tier.get("insufficient_data", 0),
            "privacy_suppressed": privacy_suppressed,
            "by_tier": by_tier,
        },
        "work_sustainability": wsi_response,
        "workload_summary": {
            "total_work_hours": analytics["total_work_hours"],
            "total_break_hours": analytics["total_break_hours"],
            "avg_work_hours_per_employee": analytics["avg_hours_per_emp"],
        },
        "work_life_balance": wlb_response,
        "recommendation_effectiveness": {
            "total_feedback": analytics["total_recs"],
            "accepted": analytics["accepted_recs"],
            "dismissed": analytics["dismissed_recs"],
            "acceptance_rate": analytics["acceptance_rate"],
        }
    }


@router.get("/predictive-outlook")
def get_manager_predictive_outlook(
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter."),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """Return privacy-protected directional projections from recent team aggregates.

    This is a transparent trend projection, not an ML inference or an individual risk score.
    Only groups with at least five authorized people are included; WLB values additionally
    require at least five survey respondents in each displayed week.
    """
    today = date.today()
    current_monday = today - timedelta(days=today.weekday())
    latest_completed_monday = current_monday - timedelta(days=7)
    forecast_week_start = current_monday + timedelta(days=7)
    week_starts = [
        latest_completed_monday - timedelta(weeks=offset)
        for offset in reversed(range(4))
    ]

    history = []
    profile_ids: List[uuid.UUID] = []
    for week_start in week_starts:
        week_end = week_start + timedelta(days=6)
        analytics = compute_team_analytics(
            db,
            current_user,
            team_id=team_id,
            start_date=week_start,
            end_date=week_end,
        )
        profile_ids = analytics["profile_ids"]
        if len(profile_ids) < 5:
            return {
                "available": False,
                "privacy_suppressed": bool(profile_ids),
                "note": (
                    "No managed team data is available."
                    if not profile_ids
                    else "Predictive outlook is hidden for groups smaller than five people."
                ),
            }

        wlb_surveys = db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= week_start,
            WorkLifeBalanceSurvey.week_start_date < week_start + timedelta(days=7),
        ).all()
        wlb_respondents = len({survey.profile_id for survey in wlb_surveys})
        wlb_score = None
        if wlb_respondents >= 5:
            wlb_score = round(sum(survey.score for survey in wlb_surveys) / len(wlb_surveys), 2)

        history.append({
            "week_start": str(week_start),
            "average_work_hours_per_person": (
                analytics["avg_hours_per_emp"] if analytics["session_count"] > 0 else None
            ),
            "work_life_balance_score": wlb_score,
        })

    work_hours = _project_next_week(
        [point["average_work_hours_per_person"] for point in history],
        0.0,
        168.0,
        steps_ahead=2,
    )
    if work_hours is not None:
        work_hours["unit"] = "hours per person per week"

    wlb_score = _project_next_week(
        [point["work_life_balance_score"] for point in history],
        0.0,
        100.0,
        steps_ahead=2,
    )
    if wlb_score is not None:
        wlb_score["unit"] = "points out of 100"

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="MANAGER_ANALYTICS_PREDICTIVE_OUTLOOK_ACCESSED",
        action_details={"team_id": str(team_id) if team_id else None, "history_weeks": 4},
    )

    return {
        "available": work_hours is not None or wlb_score is not None,
        "privacy_suppressed": False,
        "method": "Linear trend across the last four completed weeks, projected to the next full week",
        "is_machine_learning": False,
        "forecast_week_start": str(forecast_week_start),
        "history": history,
        "work_hours_per_person": work_hours,
        "work_life_balance_score": wlb_score,
        "note": (
            "Directional planning estimates only. They are not ML predictions, individual ratings, "
            "or a diagnosis. At least three weeks of data are required for each projection."
        ),
    }
