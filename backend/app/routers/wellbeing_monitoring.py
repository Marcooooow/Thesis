from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import Optional, List
from datetime import date, datetime, timezone, timedelta
import uuid

from ..database import get_db
from ..auth.security import get_current_active_user, log_system_activity, get_organization_ids_for_user
from ..models import User, Profile, TeamMembership, Team, WorkSession, ManagerAlertReview, MonitoringThresholds
from ..schemas.wellbeing_monitoring import (
    WeeklyOverviewResponse, EmployeeDetailResponse, HealthResponse, RiskTier,
    ManagerAlertReviewRequest, ManagerAlertReviewResponse,
    TeamRiskDistribution, MonitoringThresholdsRead, MonitoringThresholdsUpdate,
    TeamWellnessAdvisorResponse
)
from ..services.wellbeing_monitoring import WellbeingMonitoringService, resolve_reporting_week
from ..services.team_wellness_advisor_service import generate_team_wellness_advisor_report
from ..services.notification_dispatch_service import NotificationDispatchService
from sqlalchemy.exc import IntegrityError

router = APIRouter(
    prefix="/manager/wellbeing",
    tags=["manager-wellbeing"],
    responses={404: {"description": "Not found"}},
)


def _get_current_manager_or_admin(current_user: User = Depends(get_current_active_user)) -> User:
    if current_user.role not in ["MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to managers and administrators",
        )
    return current_user


@router.get("/health", response_model=HealthResponse)
def get_wellbeing_health(
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Check well-being monitoring system health, freshness, and monitored employee count.
    """
    total_employees = db.query(Profile).count()
    return HealthResponse(
        status="operational",
        data_freshness=datetime.now(timezone.utc),
        employees_monitored=total_employees,
        last_full_computation=datetime.now(timezone.utc)
    )

@router.get("/weekly", response_model=WeeklyOverviewResponse)
def get_weekly_overview(
    week_start: Optional[date] = Query(None, description="Start of week (Monday). Defaults to current week's Monday."),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter ID"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get weekly well-being risk overview for all employees in manager's authorized teams.
    Enforces RBAC and tenant/team scoping.
    Applies test data exclusion, small-group suppression, and configurable risk thresholds.
    """
    service = WellbeingMonitoringService(db)
    overview = service.compute_team_overview(current_user.id, week_start, team_id)

    # Notify the manager when a fully assessed employee has critical risk with
    # recurring overwork. This is a prompt to discuss support/time off, never a
    # decision about entitlement or an automatic leave request.
    if not overview.team_summary.privacy_suppressed:
        notifications_created = False
        for employee in overview.employees:
            risk_tier = employee.risk_tier
            tier_name = getattr(risk_tier, "name", "").lower()
            is_critical = tier_name == "critical" or risk_tier == RiskTier.CRITICAL
            has_recurring_overwork = any(
                "recurring overwork" in evidence.lower()
                for evidence in employee.top_evidence
            )
            if not (is_critical and has_recurring_overwork):
                continue

            name = employee.employee_name or "An employee"
            NotificationDispatchService.dispatch(
                db=db,
                recipient_user_id=current_user.id,
                title=f"Time-off discussion suggested: {name}",
                message=(
                    f"{name}'s weekly wellbeing assessment indicates critical risk with recurring overwork. "
                    "Please discuss whether time off, a recovery break, or a workload adjustment would help. "
                    "This is advisory; the employee chooses whether to request leave, which follows normal approval."
                ),
                notification_type="WELLNESS_REMINDER",
                priority="STANDARD",
                idempotency_key=(
                    f"wellbeing-time-off:{current_user.id}:{employee.employee_id}:{overview.week_start.isoformat()}"
                ),
            )
            notifications_created = True

        if notifications_created:
            db.commit()

    return overview


@router.get("/team-risk-distribution", response_model=TeamRiskDistribution)
def get_team_risk_distribution(
    week_start: Optional[date] = Query(None, description="Start of week (Monday). Defaults to current week's Monday."),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter ID"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get simplified team risk distribution (Green/Amber/Red counts) for dashboard widgets.
    Suppresses detail when fewer than 3 eligible employees contribute.
    """
    service = WellbeingMonitoringService(db)
    overview = service.compute_team_overview(current_user.id, week_start, team_id)

    # Build simplified distribution from overview
    team_summary = overview.team_summary
    if team_summary.privacy_suppressed:
        return TeamRiskDistribution(
            week_start=overview.week_start,
            week_end=overview.week_end,
            total_employees=team_summary.total_employees,
            green_count=0,
            amber_count=0,
            red_count=0,
            insufficient_data_count=0,
            privacy_suppressed=True
        )

    # Count from by_tier dict
    by_tier = team_summary.by_tier or {}
    return TeamRiskDistribution(
        week_start=overview.week_start,
        week_end=overview.week_end,
        total_employees=team_summary.total_employees,
        green_count=by_tier.get("green", 0),
        amber_count=by_tier.get("amber", 0),
        red_count=by_tier.get("red", 0),
        insufficient_data_count=by_tier.get("insufficient_data", 0),
        privacy_suppressed=False
    )


@router.get("/advisor", response_model=TeamWellnessAdvisorResponse)
def get_team_wellness_advisor(
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter ID"),
    start_date: Optional[date] = Query(None, description="Analysis period start date"),
    end_date: Optional[date] = Query(None, description="Analysis period end date"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get evidence-based Team Wellness Advisor report with dynamic insights,
    recommendations, data coverage, and model metadata.
    """
    return generate_team_wellness_advisor_report(db, current_user, team_id=team_id, start_date=start_date, end_date=end_date)


@router.get("/{employee_id}/detail", response_model=EmployeeDetailResponse)
def get_employee_detail(
    employee_id: uuid.UUID,
    week_start: Optional[date] = Query(None, description="Start of week (Monday). Defaults to current week's Monday."),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get detailed weekly risk assessment, evidence, and daily breakdown for a specific employee.
    Enforces authorization check ensuring manager has access to the employee's team.
    """
    if not week_start:
        today = date.today()
        week_start = today - timedelta(days=today.weekday())

    # Verify employee exists and resolve profile_id
    profile = db.query(Profile).filter(Profile.id == employee_id).first()
    if not profile:
        # Try finding by user_id
        profile = db.query(Profile).filter(Profile.user_id == employee_id).first()

    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee profile not found",
        )

    target_profile_id = profile.id

    # RBAC authorization check
    if current_user.role != "ADMIN":
        # Check if manager manages any team containing this employee profile
        manager_teams = db.query(Team).filter(
            Team.manager_user_id == current_user.id,
            Team.is_active == True
        ).all()
        managed_team_ids = [t.id for t in manager_teams]

        has_access = False
        if managed_team_ids:
            membership = db.query(TeamMembership).filter(
                TeamMembership.team_id.in_(managed_team_ids),
                TeamMembership.profile_id == target_profile_id,
                TeamMembership.left_at.is_(None)
            ).first()
            if membership:
                has_access = True

        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to access wellbeing details for this employee",
            )

    service = WellbeingMonitoringService(db)
    detail = service.compute_weekly_risk(target_profile_id, week_start)

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="WELLBEING_EMPLOYEE_DETAIL_ACCESSED",
        action_details={"employee_id": str(employee_id), "week_start": str(week_start)}
    )

    return detail

@router.get("/historical-trends", response_model=dict)
def get_historical_trends(
    weeks: int = Query(4, ge=1, le=12, description="Number of historical weeks to return (max 12)"),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter ID"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get historical weekly trends for team wellbeing metrics.
    Returns week-over-week comparisons for:
    - Total team working hours
    - Average daily working hours
    - Overtime hours
    - Break compliance
    - Average break duration
    - Wellbeing check-in averages
    - Behavioral pattern frequency
    - Green/Amber/Red risk distribution

    Applies test data exclusion, small-group suppression, and manager authorization.
    """
    service = WellbeingMonitoringService(db)
    return service.compute_historical_trends(current_user.id, weeks, team_id)


@router.get("/risk-distribution-history", response_model=dict)
def get_risk_distribution_history(
    weeks: int = Query(4, ge=1, le=12, description="Number of historical weeks to return (max 12)"),
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter ID"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get historical risk distribution (Green/Amber/Red counts and proportions) per week.
    Uses existing configurable classification thresholds.
    Clearly identifies weeks where historical classification cannot be reconstructed.
    """
    service = WellbeingMonitoringService(db)
    return service.compute_risk_distribution_history(current_user.id, weeks, team_id)


@router.get("/thresholds", response_model=MonitoringThresholdsRead)
def get_monitoring_thresholds(
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get current monitoring thresholds for the user's team/org.
    Admin can view/set org-wide thresholds; managers see team-specific or org defaults.
    """
    org_ids = get_organization_ids_for_user(db, current_user.id)

    if current_user.role == "ADMIN":
        # Admin: use first org's thresholds if set
        if org_ids:
            org_id = org_ids[0]
            thresholds = db.query(MonitoringThresholds).filter(
                MonitoringThresholds.organization_id == org_id,
                MonitoringThresholds.team_id.is_(None),
                MonitoringThresholds.is_active == True
            ).first()
            if thresholds:
                return _thresholds_model_to_read(thresholds)
        # Return defaults
        return _default_thresholds_to_read()

    # Manager: use team thresholds
    manager_teams = db.query(Team).filter(
        Team.manager_user_id == current_user.id,
        Team.is_active == True
    ).all()

    if manager_teams:
        team_thresholds = db.query(MonitoringThresholds).filter(
            MonitoringThresholds.team_id == manager_teams[0].id,
            MonitoringThresholds.is_active == True
        ).first()
        if team_thresholds:
            return _thresholds_model_to_read(team_thresholds)

    # Fall back to org or defaults
    if org_ids:
        org_thresholds = db.query(MonitoringThresholds).filter(
            MonitoringThresholds.organization_id == org_ids[0],
            MonitoringThresholds.team_id.is_(None),
            MonitoringThresholds.is_active == True
        ).first()
        if org_thresholds:
            return _thresholds_model_to_read(org_thresholds)

    return _default_thresholds_to_read()


@router.put("/thresholds", response_model=MonitoringThresholdsRead)
def update_monitoring_thresholds(
    thresholds_data: MonitoringThresholdsUpdate,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Update monitoring thresholds.
    Admin can set org-wide thresholds. Managers can set team-specific thresholds.
    """
    if current_user.role == "ADMIN":
        # Admin sets org-wide thresholds
        org_ids = get_organization_ids_for_user(db, current_user.id)
        if not org_ids:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No organizations found for current user"
            )

        org_id = org_ids[0]
        thresholds = db.query(MonitoringThresholds).filter(
            MonitoringThresholds.organization_id == org_id,
            MonitoringThresholds.team_id.is_(None)
        ).first()

        if not thresholds:
            thresholds = MonitoringThresholds(organization_id=org_id, created_by=current_user.id)

        # Apply updates (only non-None values)
        update_data = thresholds_data.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(thresholds, key, value)

        thresholds.updated_at = datetime.now(timezone.utc)
        db.add(thresholds)
        try:
            db.commit()
        except IntegrityError as e:
            db.rollback()
            if "ck_thresholds_overtime_order" in str(e):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="overtime_multiplier_amber must be less than overtime_multiplier_red"
                )
            if "ck_thresholds_break_compliance_order" in str(e):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="break_compliance_red must be less than break_compliance_amber"
                )
            if "ck_thresholds_fatigue_order" in str(e):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="fatigue_amber must be less than fatigue_red"
                )
            if "ck_thresholds_pattern_order" in str(e):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="pattern_count_amber must be less than or equal to pattern_count_red"
                )
            if "ck_thresholds_min_employees" in str(e):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="min_employees_for_detail must be >= 5"
                )
            raise
        db.refresh(thresholds)
        return _thresholds_model_to_read(thresholds)

    # Manager: set team-specific thresholds
    manager_teams = db.query(Team).filter(
        Team.manager_user_id == current_user.id,
        Team.is_active == True
    ).all()

    if not manager_teams:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active teams found for current manager"
        )

    team_id = manager_teams[0].id
    thresholds = db.query(MonitoringThresholds).filter(
        MonitoringThresholds.team_id == team_id
    ).first()

    if not thresholds:
        thresholds = MonitoringThresholds(team_id=team_id, created_by=current_user.id)

    # Apply updates
    update_data = thresholds_data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(thresholds, key, value)

    thresholds.updated_at = datetime.now(timezone.utc)
    db.add(thresholds)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        if "ck_thresholds_overtime_order" in str(e):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="overtime_multiplier_amber must be less than overtime_multiplier_red"
            )
        if "ck_thresholds_break_compliance_order" in str(e):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="break_compliance_red must be less than break_compliance_amber"
            )
        if "ck_thresholds_fatigue_order" in str(e):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="fatigue_amber must be less than fatigue_red"
            )
        if "ck_thresholds_pattern_order" in str(e):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="pattern_count_amber must be less than or equal to pattern_count_red"
            )
        if "ck_thresholds_min_employees" in str(e):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="min_employees_for_detail must be >= 5"
            )
        raise
    db.refresh(thresholds)
    return _thresholds_model_to_read(thresholds)


def _thresholds_model_to_read(model: MonitoringThresholds) -> MonitoringThresholdsRead:
    """Convert MonitoringThresholds model to read schema."""
    return MonitoringThresholdsRead(
        id=model.id,
        team_id=model.team_id,
        organization_id=model.organization_id,
        overtime_multiplier_amber=model.overtime_multiplier_amber,
        overtime_multiplier_red=model.overtime_multiplier_red,
        break_compliance_amber=model.break_compliance_amber,
        break_compliance_red=model.break_compliance_red,
        fatigue_amber=model.fatigue_amber,
        fatigue_red=model.fatigue_red,
        pattern_count_amber=model.pattern_count_amber,
        pattern_count_red=model.pattern_count_red,
        min_employees_for_detail=max(5, model.min_employees_for_detail),
        map_green_to_tier=model.map_green_to_tier,
        map_amber_to_tier=model.map_amber_to_tier,
        map_red_to_tier=model.map_red_to_tier,
        is_active=model.is_active,
        created_at=model.created_at,
        updated_at=model.updated_at,
    )


def _default_thresholds_to_read() -> MonitoringThresholdsRead:
    """Return default thresholds as read schema."""
    return MonitoringThresholdsRead(
        id=uuid.uuid4(),
        team_id=None,
        organization_id=None,
        overtime_multiplier_amber=1.1,
        overtime_multiplier_red=1.3,
        break_compliance_amber=80,
        break_compliance_red=60,
        fatigue_amber=2.5,
        fatigue_red=3.5,
        pattern_count_amber=1,
        pattern_count_red=2,
        min_employees_for_detail=5,
        map_green_to_tier=1,
        map_amber_to_tier=2,
        map_red_to_tier=4,
        is_active=True,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
    )


@router.get("/alerts/history", response_model=List[dict])
def get_manager_alert_history(
    week_start: Optional[date] = Query(None, description="Filter by week start date"),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Get manager alert review history.
    """
    from ..models import ManagerAlertReview

    query = db.query(ManagerAlertReview)

    if week_start:
        query = query.filter(ManagerAlertReview.week_start == week_start)

    # Filter to manager's authorized employees
    manager_teams = db.query(Team).filter(
        Team.manager_user_id == current_user.id,
        Team.is_active == True
    ).all()
    managed_team_ids = [t.id for t in manager_teams]

    # Get authorized profile IDs directly from team memberships
    authorized_profile_ids = db.query(TeamMembership.profile_id).filter(
        TeamMembership.team_id.in_(managed_team_ids),
        TeamMembership.left_at.is_(None)
    ).all()
    authorized_profile_ids = [pid[0] for pid in authorized_profile_ids]

    query = query.filter(ManagerAlertReview.profile_id.in_(authorized_profile_ids))

    history = query.order_by(ManagerAlertReview.created_at.desc()).all()

    return [
        {
            "id": str(h.id),
            "employee_id": str(h.profile_id),
            "week_start": str(h.week_start),
            "risk_tier_5tier": h.risk_tier,
            "risk_label": ["INSUFFICIENT_DATA", "LOW", "MODERATE", "HIGH", "CRITICAL"][h.risk_tier] if 0 <= h.risk_tier <= 4 else "UNKNOWN",
            "review_status": h.review_status,
            "action_taken": h.action_taken,
            "reviewed_at": h.reviewed_at.isoformat() if h.reviewed_at else None,
            "created_at": h.created_at.isoformat() if h.created_at else None,
        }
        for h in history
    ]


@router.post("/reviews", response_model=ManagerAlertReviewResponse)
def save_alert_review(
    review_data: ManagerAlertReviewRequest,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db),
):
    """
    Mark an employee wellbeing alert as reviewed and record follow-up action.
    Enforces manager authorization and team access.
    """
    profile = db.query(Profile).filter(Profile.id == review_data.employee_id).first()
    if not profile:
        profile = db.query(Profile).filter(Profile.user_id == review_data.employee_id).first()
    if not profile:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee profile not found")

    target_profile_id = profile.id

    if current_user.role != "ADMIN":
        manager_teams = db.query(Team).filter(
            Team.manager_user_id == current_user.id,
            Team.is_active == True
        ).all()
        managed_team_ids = [t.id for t in manager_teams]
        membership = db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.profile_id == target_profile_id,
            TeamMembership.left_at.is_(None)
        ).first() if managed_team_ids else None
        if not membership:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to review alerts for this employee")

    service = WellbeingMonitoringService(db)
    detail = service.compute_weekly_risk(target_profile_id, review_data.week_start)

    existing = db.query(ManagerAlertReview).filter(
        ManagerAlertReview.profile_id == target_profile_id,
        ManagerAlertReview.week_start == review_data.week_start
    ).first()

    now = datetime.now(timezone.utc)
    if existing:
        existing.manager_id = current_user.id
        existing.risk_tier = int(detail.risk_tier)
        existing.review_status = review_data.review_status
        existing.action_taken = review_data.action_taken
        existing.action_notes = review_data.action_notes
        existing.reviewed_at = now if review_data.review_status == "REVIEWED" else None
        db.add(existing)
        db.commit()
        db.refresh(existing)
        review_obj = existing
    else:
        new_rev = ManagerAlertReview(
            profile_id=target_profile_id,
            manager_id=current_user.id,
            week_start=review_data.week_start,
            risk_tier=int(detail.risk_tier),
            review_status=review_data.review_status,
            action_taken=review_data.action_taken,
            action_notes=review_data.action_notes,
            reviewed_at=now if review_data.review_status == "REVIEWED" else None
        )
        db.add(new_rev)
        db.commit()
        db.refresh(new_rev)
        review_obj = new_rev

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="WELLBEING_ALERT_REVIEWED",
        action_details={
            "employee_id": str(target_profile_id),
            "week_start": str(review_data.week_start),
            "review_status": review_data.review_status,
            "action_taken": review_data.action_taken
        }
    )

    return ManagerAlertReviewResponse(
        id=review_obj.id,
        profile_id=review_obj.profile_id,
        manager_id=review_obj.manager_id,
        week_start=review_obj.week_start,
        risk_tier=review_obj.risk_tier,
        review_status=review_obj.review_status,
        action_taken=review_obj.action_taken,
        action_notes=review_obj.action_notes,
        reviewed_at=review_obj.reviewed_at,
        created_at=review_obj.created_at,
        updated_at=review_obj.updated_at,
    )
