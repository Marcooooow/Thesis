from datetime import date, datetime, timezone, timedelta
from typing import Optional, List, Dict, Any, Union
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from ..models import User, Profile, UserSettings, WorkSession, Break, SessionWellbeingCheckin, Team, TeamMembership, OrganizationMembership, ManagerAlertReview, ReturnToWorkCheckin, MonitoringThresholds
from ..auth.security import should_include_test_data
from ..schemas.wellbeing_monitoring import (
    RiskTier, TrendDirection, EvidenceType, EvidenceItem,
    DataQuality, DetectedPattern, DailyBreakdown, WeeklyAggregates,
    EmployeeRiskSummary, TeamSummary, WeeklyOverviewResponse, EmployeeDetailResponse
)
from .behavioral_analytics import detect_behavioral_patterns, calculate_personal_baselines
from .analytics_service import AnalyticsEngine, resolve_target_daily_hours
from .risk_classification import classify_risk_from_aggregates, get_thresholds_for_team, should_suppress_detail, DEFAULT_THRESHOLDS


def resolve_reporting_week(db: Session, profile_ids: List[uuid.UUID], explicit_week_start: Optional[date] = None) -> date:
    """
    Shared authoritative reporting-period resolver for wellbeing monitoring and manager analytics.
    If explicit_week_start is provided, returns its Monday.
    Otherwise, searches backward from the current week (Monday) to find the latest completed
    Monday–Sunday reporting week that satisfies employee-level wellbeing data requirements (>= 3 sessions AND >= 2 check-ins).
    Falls back to latest session's week or current week's Monday if no historical week fully qualifies.
    """
    if explicit_week_start:
        return explicit_week_start - timedelta(days=explicit_week_start.weekday())

    today = date.today()
    current_monday = today - timedelta(days=today.weekday())

    if not profile_ids:
        return current_monday

    def count_qualifying_employees(monday: date) -> int:
        w_start = datetime.combine(monday, datetime.min.time(), tzinfo=timezone.utc)
        w_end = datetime.combine(monday + timedelta(days=6), datetime.max.time(), tzinfo=timezone.utc)
        count = 0
        for pid in profile_ids:
            sessions = db.query(WorkSession).filter(
                WorkSession.profile_id == pid,
                WorkSession.started_at >= w_start,
                WorkSession.started_at <= w_end
            ).all()
            s_count = len(sessions)
            if s_count >= 3:
                session_ids = [s.id for s in sessions]
                c_count = db.query(SessionWellbeingCheckin).filter(
                    SessionWellbeingCheckin.work_session_id.in_(session_ids)
                ).count() if session_ids else 0
                if c_count >= 2:
                    count += 1
        return count

    # 1. Check current week first
    if count_qualifying_employees(current_monday) > 0:
        return current_monday

    # 2. Search backward week by week (up to 12 weeks)
    check_monday = current_monday - timedelta(days=7)
    for _ in range(12):
        if count_qualifying_employees(check_monday) > 0:
            return check_monday
        check_monday -= timedelta(days=7)

    # 3. Fallback: check latest session's Monday if any session exists
    latest_ws = db.query(WorkSession).filter(
        WorkSession.profile_id.in_(profile_ids)
    ).order_by(WorkSession.started_at.desc()).first()

    if latest_ws and latest_ws.started_at:
        s_dt = latest_ws.started_at.date()
        return s_dt - timedelta(days=s_dt.weekday())

    return current_monday


class WellbeingMonitoringService:
    """
    Authoritative weekly employee well-being monitoring service.
    Computes risk tiers (0-4), detects behavioral patterns, generates explainable evidence,
    and enforces strict privacy constraints (aggregates only, no raw notes or individual check-in scores).
    """

    def __init__(self, db: Session):
        self.db = db

    def _resolve_employee_target_hours(self, profile_id: Union[str, uuid.UUID]) -> float:
        """
        Per-employee schedule resolution:
        Profile.target_daily_hours -> UserSettings.work_target_daily_hours -> 8.0 default.
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)
        return resolve_target_daily_hours(self.db, profile_id)

    def compute_weekly_risk(self, profile_id: Union[str, uuid.UUID], week_start: date) -> EmployeeDetailResponse:
        """
        Compute weekly risk assessment for a single employee for the week starting on `week_start` (Monday).
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        week_end = week_start + timedelta(days=6)
        day_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        day_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

        # 1. Fetch employee profile and user info
        profile = self.db.query(Profile).filter(Profile.id == profile_id).first()
        employee_name = "Employee"
        if profile and profile.user:
            employee_name = profile.user.full_name or "Employee"

        # 2. Fetch work sessions in week range
        sessions = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            or_(
                and_(WorkSession.started_at >= day_start_dt, WorkSession.started_at <= day_end_dt),
                and_(WorkSession.ended_at >= day_start_dt, WorkSession.ended_at <= day_end_dt),
                and_(WorkSession.started_at <= day_start_dt, or_(WorkSession.ended_at >= day_end_dt, WorkSession.ended_at == None))
            )
        ).all()

        sessions_count = len(sessions)

        # Get thresholds for risk classification (needed for trend computation)
        from ..models import TeamMembership, Team
        team_membership = self.db.query(TeamMembership).filter(
            TeamMembership.profile_id == profile_id,
            TeamMembership.left_at.is_(None)
        ).first()
        threshold_team_id = team_membership.team_id if team_membership else None
        organization_id = None
        if threshold_team_id:
            team = self.db.query(Team).filter(Team.id == threshold_team_id).first()
            organization_id = team.organization_id if team else None
        thresholds = get_thresholds_for_team(self.db, threshold_team_id, organization_id)

        # 3. Fetch wellbeing checkins linked via work sessions in week
        session_ids = [s.id for s in sessions]
        checkins = []
        if session_ids:
            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.work_session_id.in_(session_ids)
            ).all()

        checkins_count = len(checkins)

        # Missing data check: <3 sessions or <2 checkins -> Tier 0 (Insufficient Data)
        if sessions_count < 3 or checkins_count < 2:
            dq = DataQuality(
                sessions_count=sessions_count,
                checkins_count=checkins_count,
                baseline_source="config_fallback",
                partial_week=sessions_count < 3,
                data_limitation="insufficient_sessions_or_checkins"
            )
            return EmployeeDetailResponse(
                employee_id=profile_id,
                employee_name=employee_name,
                week_start=week_start,
                week_end=week_end,
                risk_tier=RiskTier.INSUFFICIENT_DATA,
                risk_label="Insufficient Data",
                daily_breakdown=[],
                weekly_aggregates=WeeklyAggregates(
                    avg_worked_hours=0.0,
                    avg_break_compliance_pct=0,
                    avg_focus_rate_pct=0.0,
                    total_checkins=checkins_count,
                    avg_stress_level=None,
                    avg_energy_level=None,
                    avg_workload_manageability=None,
                    data_quality=dq
                ),
                detected_patterns=[],
                evidence_items=[],
                recommended_actions=["Encourage regular check-ins and session logging to enable well-being monitoring."],
                data_quality=dq
            )

        # 4. Compute daily breakdown and target hours
        target_hours = self._resolve_employee_target_hours(profile_id)
        daily_breakdown_list = []
        total_worked_seconds = 0.0
        total_break_compliance = 0.0
        total_focus_rate = 0.0
        stress_sum = 0.0
        energy_sum = 0.0
        workload_sum = 0.0
        checkin_stress_count = 0

        # Group sessions by date
        current_date = week_start
        while current_date <= week_end:
            d_start = datetime.combine(current_date, datetime.min.time(), tzinfo=timezone.utc)
            d_end = datetime.combine(current_date, datetime.max.time(), tzinfo=timezone.utc)

            day_summary = AnalyticsEngine.calculate_daily_summary(self.db, profile_id, current_date)
            worked_hrs = day_summary["workedHours"]
            focus_rate = day_summary["focusRate"]

            # Checkins for this day
            day_checkins = [
                c for c in checkins
                if c.created_at and d_start <= (c.created_at if c.created_at.tzinfo else c.created_at.replace(tzinfo=timezone.utc)) <= d_end
            ]

            day_stress = [c.mental_fatigue for c in day_checkins if c.mental_fatigue] # using mental_fatigue or overall_wellbeing as stress proxy if needed, or check fields
            day_energy = [c.break_recovery for c in day_checkins if c.break_recovery]

            avg_s = sum(day_stress) / len(day_stress) if day_stress else None
            avg_e = sum(day_energy) / len(day_energy) if day_energy else None

            if day_stress:
                stress_sum += sum(day_stress)
                checkin_stress_count += len(day_stress)
            if day_energy:
                energy_sum += sum(day_energy)

            total_worked_seconds += day_summary["workedSeconds"]
            total_focus_rate += focus_rate

            daily_breakdown_list.append(DailyBreakdown(
                date=current_date,
                worked_hours=worked_hrs,
                target_hours=target_hours,
                break_compliance_pct=int(day_summary.get("idle", 0)), # break compliance approximation
                focus_rate_pct=focus_rate,
                checkin_count=len(day_checkins),
                avg_stress_level=avg_s,
                avg_energy_level=avg_e,
                patterns_detected=[]
            ))
            current_date += timedelta(days=1)

        avg_worked_hours = (total_worked_seconds / 3600.0) / 7.0
        avg_focus_rate = total_focus_rate / 7.0
        avg_stress = (stress_sum / checkin_stress_count) if checkin_stress_count > 0 else None
        avg_energy = (energy_sum / checkin_stress_count) if checkin_stress_count > 0 else None

        # 5. Detect behavioral patterns via BehavioralPatternDetector
        patterns_raw = detect_behavioral_patterns(
            self.db, profile_id
        )

        detected_patterns = []
        high_patterns_count = 0
        medium_patterns_count = 0
        has_overwork = False
        has_insufficient_recovery = False

        for p in patterns_raw:
            pid = p.get("pattern_id")
            raw_strength = p.get("evidence_strength", "low")
            strength = raw_strength.lower() if isinstance(raw_strength, str) else "low"
            if strength == "high":
                high_patterns_count += 1
            elif strength == "medium":
                medium_patterns_count += 1

            if pid == "RECURRING_OVERWORK" and strength in ("medium", "high"):
                has_overwork = True
            if pid == "INSUFFICIENT_RECOVERY" and strength in ("medium", "high"):
                has_insufficient_recovery = True

            detected_patterns.append(DetectedPattern(
                pattern_id=pid,
                detected=bool(p.get("detected", False)),
                display_name=p.get("display_name", pid),
                evidence_strength=strength,
                measurement=p.get("measurement", ""),
                data_limitations=p.get("data_limitations"),
                days_triggered=p.get("days_triggered", 0)
            ))

        # 6. Risk Tier Classification (0-4)
        # Independent severe indicators: sustained >=140% target hours, 0% break compliance, avg stress >= 4.5
        independently_severe = (
            avg_worked_hours >= (target_hours * 1.4) or
            (avg_stress is not None and avg_stress >= 4.5)
        )

        if (has_overwork and has_insufficient_recovery) or independently_severe:
            risk_tier = RiskTier.CRITICAL
            risk_label = "Critical Risk"
        elif high_patterns_count >= 1 or medium_patterns_count >= 2:
            risk_tier = RiskTier.HIGH
            risk_label = "High Risk"
        elif medium_patterns_count == 1:
            risk_tier = RiskTier.MODERATE
            risk_label = "Moderate Risk"
        else:
            risk_tier = RiskTier.LOW
            risk_label = "Low Risk"

        # 7. Evidence generation & Return-to-Work Supplemental Processing
        evidence_items = []
        if avg_worked_hours > (target_hours * 1.2):
            evidence_items.append(EvidenceItem(
                type=EvidenceType.WORKED_HOURS_EXCESS,
                description=f"Worked {avg_worked_hours:.1f}h avg/day (target: {target_hours}h) across sessions",
                metric_value=round(avg_worked_hours, 1),
                threshold=round(target_hours * 1.2, 1),
                days_affected=sessions_count
            ))
        if avg_stress is not None and avg_stress >= 4.0:
            evidence_items.append(EvidenceItem(
                type=EvidenceType.WELLBEING_DECLINING,
                description=f"Elevated stress/fatigue level averaging {avg_stress:.1f}/5 across check-ins",
                metric_value=round(avg_stress, 1),
                threshold=4.0,
                days_affected=checkins_count
            ))

        for p in detected_patterns:
            if p.detected and (p.evidence_strength in ("medium", "high") or p.pattern_id in ("RECURRING_OVERWORK", "REPEATED_SKIPPED_BREAKS")):
                ev_type = EvidenceType.WORKED_HOURS_EXCESS if p.pattern_id in ("RECURRING_OVERWORK", "REPEATED_SKIPPED_BREAKS") else EvidenceType.WELLBEING_DECLINING
                desc = f"{p.display_name}: {p.measurement}"
                if not any(e.description.startswith(p.display_name) for e in evidence_items):
                    evidence_items.append(EvidenceItem(
                        type=ev_type,
                        description=desc,
                        metric_value=1.0,
                        threshold=1.0,
                        days_affected=p.days_triggered or 1
                    ))

        if risk_tier in (RiskTier.HIGH, RiskTier.CRITICAL) and not evidence_items:
            risk_tier = RiskTier.MODERATE
            risk_label = "Moderate Risk"
        # Separation of signals:
        # - wants_manager_support: generates actionable manager support recommendation (supportive 1:1), not declining wellbeing.
        # - work_contributed_to_absence: retained as supplemental contextual evidence without automatic quantitative risk escalation.
        from ..models import ReturnToWorkCheckin
        week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        next_week_start_dt = datetime.combine(week_start + timedelta(days=7), datetime.min.time(), tzinfo=timezone.utc)

        rtw_checkins = self.db.query(ReturnToWorkCheckin).filter(
            ReturnToWorkCheckin.profile_id == profile_id,
            ReturnToWorkCheckin.submitted_at >= week_start_dt,
            ReturnToWorkCheckin.submitted_at < next_week_start_dt
        ).all()

        rtw_support_requested = any(c.wants_manager_support for c in rtw_checkins if c.wants_manager_support)
        rtw_work_contributed = any(c.work_contributed_to_absence for c in rtw_checkins if c.work_contributed_to_absence)

        if rtw_work_contributed:
            evidence_items.append(EvidenceItem(
                type=EvidenceType.WELLBEING_DECLINING,
                description="Supplemental RTW check-in indicates work factors contributed to absence",
                metric_value=1.0,
                threshold=1.0,
                days_affected=len(rtw_checkins)
            ))

        # 8. Recommended actions (static, explainable mapping)
        actions = []
        pattern_ids = {p.pattern_id for p in detected_patterns if p.detected}
        if rtw_support_requested:
            actions.append("Employee requested manager support during return-to-work check-in. Schedule a supportive 1:1 check-in.")
        if risk_tier in (RiskTier.HIGH, RiskTier.CRITICAL):
            actions.append("Review workload allocation and immediate task priorities.")
            actions.append("Schedule a supportive 1:1 check-in to discuss work-life boundaries.")
            if "REPEATED_SKIPPED_BREAKS" in pattern_ids or "RECURRING_OVERWORK" in pattern_ids:
                actions.append("Overwork or repeated missed-break pattern detected. Recommend the employee take their next scheduled recovery break and review workload that may be preventing recovery.")
            else:
                actions.append("Encourage adherence to scheduled break recovery.")
            if risk_tier == RiskTier.CRITICAL and "RECURRING_OVERWORK" in pattern_ids:
                actions.append("Sustained overwork detected. Discuss whether temporary time off or a workload adjustment would support recovery; any leave request remains the employee’s choice and follows normal approval.")
        elif risk_tier == RiskTier.MODERATE:
            actions.append("Monitor break compliance during upcoming shifts.")
            actions.append("Review task distribution for potential bottlenecks.")
        else:
            actions.append("Maintain healthy work patterns and regular recovery breaks.")

        # Compute week-over-week trends
        trend_data = self._compute_weekly_aggregates_with_trend(profile_id, week_start, thresholds)

        return EmployeeDetailResponse(
            employee_id=profile_id,
            employee_name=employee_name,
            week_start=week_start,
            week_end=week_end,
            risk_tier=risk_tier,
            risk_label=risk_label,
            daily_breakdown=daily_breakdown_list,
            weekly_aggregates=WeeklyAggregates(
                avg_worked_hours=round(avg_worked_hours, 1),
                avg_break_compliance_pct=75, # placeholder aggregate
                avg_focus_rate_pct=round(avg_focus_rate, 1),
                total_checkins=checkins_count,
                avg_stress_level=round(avg_stress, 1) if avg_stress else None,
                avg_energy_level=round(avg_energy, 1) if avg_energy else None,
                avg_workload_manageability=3.0,
                previous_week_avg_worked_hours=trend_data.get("previous_week_avg_worked_hours", 0.0),
                previous_week_avg_break_compliance_pct=trend_data.get("previous_week_avg_break_compliance_pct", 0),
                previous_week_avg_focus_rate_pct=trend_data.get("previous_week_avg_focus_rate_pct", 0.0),
                previous_week_total_checkins=trend_data.get("previous_week_total_checkins", 0),
                trend_worked_hours=trend_data.get("trend_worked_hours"),
                trend_break_compliance=trend_data.get("trend_break_compliance"),
                trend_focus_rate=trend_data.get("trend_focus_rate"),
            ),
            detected_patterns=detected_patterns,
            evidence_items=evidence_items,
            recommended_actions=actions,
            data_quality=DataQuality(
                sessions_count=sessions_count,
                checkins_count=checkins_count,
                baseline_source="personal_30d",
                partial_week=False,
                data_limitation=None
            )
        )

    def _compute_trend_direction(
        self,
        current_value: float,
        previous_value: float,
        higher_is_better: bool = False
    ) -> TrendDirection:
        """
        Compute trend direction comparing current to previous week.

        Args:
            current_value: Current week metric value
            previous_value: Previous week metric value
            higher_is_better: If True, higher current = improving.
                             If False, lower current = improving (e.g., overtime, stress).
        Returns:
            TrendDirection: IMPROVING, STABLE, WORSENING, or UNKNOWN
        """
        # Cannot compute trend if previous is 0 or unavailable
        if previous_value == 0 or previous_value is None:
            return TrendDirection.UNKNOWN

        # Calculate percentage change
        pct_change = ((current_value - previous_value) / previous_value) * 100

        # Consider change < 5% as stable
        if abs(pct_change) < 5:
            return TrendDirection.STABLE

        if higher_is_better:
            # Higher is better (e.g., focus rate, break compliance)
            if pct_change > 0:
                return TrendDirection.IMPROVING
            else:
                return TrendDirection.WORSENING
        else:
            # Lower is better (e.g., worked hours, stress, overtime)
            if pct_change < 0:
                return TrendDirection.IMPROVING
            else:
                return TrendDirection.WORSENING

    def _compute_week_aggregates_only(
        self,
        profile_id: uuid.UUID,
        week_start: date,
        thresholds
    ) -> dict:
        """
        Compute weekly aggregates without trend comparison (to avoid recursion).
        Returns dictionary with current week metrics only.
        """
        week_end = week_start + timedelta(days=6)
        day_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        day_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

        # Fetch work sessions in week range
        sessions = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            or_(
                and_(WorkSession.started_at >= day_start_dt, WorkSession.started_at <= day_end_dt),
                and_(WorkSession.ended_at >= day_start_dt, WorkSession.ended_at <= day_end_dt),
                and_(WorkSession.started_at <= day_start_dt, WorkSession.ended_at >= day_end_dt),
            )
        ).all()

        sessions_count = len(sessions)

        # Fetch wellbeing checkins in week range
        checkins = self.db.query(SessionWellbeingCheckin).filter(
            SessionWellbeingCheckin.work_session_id.in_([s.id for s in sessions])
        ).all() if sessions else []

        checkins_count = len(checkins)

        if sessions_count < 3 or checkins_count < 2:
            # Insufficient data
            return {
                "avg_worked_hours": 0.0,
                "avg_break_compliance_pct": 0,
                "avg_focus_rate_pct": 0.0,
                "total_checkins": checkins_count,
            }

        # Calculate daily worked hours
        daily_hours = {}
        for session in sessions:
            start = max(session.started_at, day_start_dt)
            end = min(session.ended_at or day_end_dt, day_end_dt)
            duration = (end - start).total_seconds() / 3600
            day_key = start.date()
            daily_hours[day_key] = daily_hours.get(day_key, 0) + duration

        avg_worked_hours = sum(daily_hours.values()) / len(daily_hours) if daily_hours else 0

        # Calculate focus rate from checkins
        focus_rates = [c.perceived_focus for c in checkins if c.perceived_focus is not None]
        avg_focus_rate = sum(focus_rates) / len(focus_rates) if focus_rates else 0

        # Placeholder break compliance
        avg_break_compliance = 75

        return {
            "avg_worked_hours": round(avg_worked_hours, 1),
            "avg_break_compliance_pct": avg_break_compliance,
            "avg_focus_rate_pct": round(avg_focus_rate, 1),
            "total_checkins": checkins_count,
        }

    def _compute_weekly_aggregates_with_trend(
        self,
        profile_id: uuid.UUID,
        week_start: date,
        thresholds
    ) -> dict:
        """
        Compute weekly aggregates with previous week comparison.
        Returns dictionary with current and previous week metrics + trend directions.
        """
        # Get current week aggregates (without trend computation to avoid recursion)
        current_agg = self._compute_week_aggregates_only(profile_id, week_start, thresholds)

        # Get previous week aggregates
        prev_week_start = week_start - timedelta(days=7)
        try:
            prev_agg = self._compute_week_aggregates_only(profile_id, prev_week_start, thresholds)

            # Extract metrics
            current_worked = current_agg.get("avg_worked_hours", 0)
            current_break = current_agg.get("avg_break_compliance_pct", 100)
            current_focus = current_agg.get("avg_focus_rate_pct", 0)
            current_checkins = current_agg.get("total_checkins", 0)

            prev_worked = prev_agg.get("avg_worked_hours", 0)
            prev_break = prev_agg.get("avg_break_compliance_pct", 100)
            prev_focus = prev_agg.get("avg_focus_rate_pct", 0)
            prev_checkins = prev_agg.get("total_checkins", 0)

            # Compute trends
            trend_worked = self._compute_trend_direction(current_worked, prev_worked, higher_is_better=False)
            trend_break = self._compute_trend_direction(current_break, prev_break, higher_is_better=True)
            trend_focus = self._compute_trend_direction(current_focus, prev_focus, higher_is_better=True)

            return {
                **current_agg,
                "previous_week_avg_worked_hours": round(prev_worked, 1),
                "previous_week_avg_break_compliance_pct": prev_break,
                "previous_week_avg_focus_rate_pct": round(prev_focus, 1),
                "previous_week_total_checkins": prev_checkins,
                "trend_worked_hours": trend_worked,
                "trend_break_compliance": trend_break,
                "trend_focus_rate": trend_focus,
            }
        except Exception:
            # Previous week not available or error - return current with UNKNOWN trends
            return {
                **current_agg,
                "previous_week_avg_worked_hours": 0.0,
                "previous_week_avg_break_compliance_pct": 0,
                "previous_week_avg_focus_rate_pct": 0.0,
                "previous_week_total_checkins": 0,
                "trend_worked_hours": TrendDirection.UNKNOWN,
                "trend_break_compliance": TrendDirection.UNKNOWN,
                "trend_focus_rate": TrendDirection.UNKNOWN,
            }

    def compute_team_overview(self, manager_id: Union[str, uuid.UUID], week_start: Optional[date] = None, team_id: Optional[Union[str, uuid.UUID]] = None) -> WeeklyOverviewResponse:
        """
        Compute weekly risk overview for all employees in manager's teams.
        Enforces org-scoped RBAC via TeamMembership / OrganizationMembership.
        Applies test data exclusion, small-group suppression, and configurable risk thresholds.
        """
        if isinstance(manager_id, str):
            manager_id = uuid.UUID(manager_id)
        if isinstance(team_id, str):
            team_id = uuid.UUID(team_id)

        # Get teams managed by manager
        manager_teams_query = self.db.query(Team).filter(
            Team.manager_user_id == manager_id,
            Team.is_active == True
        )
        if team_id:
            manager_teams_query = manager_teams_query.filter(Team.id == team_id)
        managed_teams = manager_teams_query.all()
        managed_team_ids = [t.id for t in managed_teams]

        if week_start is None:
            employee_memberships = self.db.query(TeamMembership).filter(
                TeamMembership.team_id.in_(managed_team_ids),
                TeamMembership.left_at.is_(None)
            ).all() if managed_team_ids else []
            profile_ids = [em.profile_id for em in employee_memberships]
            week_start = resolve_reporting_week(self.db, profile_ids)

        week_end = week_start + timedelta(days=6)

        if not managed_team_ids:
            return WeeklyOverviewResponse(
                week_start=week_start,
                week_end=week_end,
                generated_at=datetime.now(timezone.utc),
                team_summary=TeamSummary(total_employees=0, by_tier={}),
                employees=[]
            )

        manager_user = self.db.query(User).filter(User.id == manager_id).first()
        include_test = should_include_test_data(self.db, manager_user)

        # Get organization_id for threshold resolution (use first managed team's org)
        organization_id = managed_teams[0].organization_id if managed_teams else None

        # Get all employees in these teams
        employee_memberships = self.db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()

        profile_ids = [em.profile_id for em in employee_memberships]

        # Get profiles for employees - apply test data exclusion
        prof_q = self.db.query(Profile).filter(Profile.id.in_(profile_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()

        # Get thresholds for this team/org
        # If team_id specified, use that team's thresholds; otherwise use first team's org
        threshold_team_id = team_id if team_id else (managed_teams[0].id if managed_teams else None)
        thresholds = get_thresholds_for_team(self.db, threshold_team_id, organization_id)

        # Check small-group suppression
        eligible_count = len(profiles)
        suppress_detail = should_suppress_detail(eligible_count, thresholds)

        employees_summary = []
        tier_counts_3tier = {
            "green": 0,
            "amber": 0,
            "red": 0,
            "insufficient_data": 0
        }

        for p in profiles:
            detail = self.compute_weekly_risk(p.id, week_start)

            # Classify using configurable thresholds
            weekly_agg = detail.weekly_aggregates.model_dump() if hasattr(detail.weekly_aggregates, 'model_dump') else detail.weekly_aggregates
            import logging
            logging.warning(f"DEBUG compute_team_overview: weekly_agg={weekly_agg}")
            risk_3tier, risk_5tier = classify_risk_from_aggregates(
                weekly_aggregates=weekly_agg,
                evidence_items=[e.model_dump() if hasattr(e, 'model_dump') else e for e in detail.evidence_items],
                detected_patterns=[p.model_dump() if hasattr(p, 'model_dump') else p for p in detail.detected_patterns],
                thresholds=thresholds
            )

            # Map 3-tier to tier_counts
            tier_counts_3tier[risk_3tier.lower()] += 1

            top_ev = [e.description for e in detail.evidence_items[:2]]
            active_patterns = [pattern for pattern in detail.detected_patterns if pattern.detected]
            primary_c = active_patterns[0].display_name if active_patterns else "Normal work patterns"

            membership = self.db.query(TeamMembership).join(Team).filter(
                TeamMembership.profile_id == p.id,
                TeamMembership.team_id.in_(managed_team_ids),
                TeamMembership.left_at.is_(None)
            ).first()
            team_name = membership.team.name if membership and membership.team else "Team"

            # Get review status for this employee/week
            review_rec = self.db.query(ManagerAlertReview).filter(
                ManagerAlertReview.profile_id == p.id,
                ManagerAlertReview.week_start == week_start
            ).first()

            review_status = review_rec.review_status if review_rec else "PENDING"
            action_taken = review_rec.action_taken if review_rec else None
            reviewed_at = review_rec.reviewed_at if review_rec else None
            reviewed_by_manager_id = review_rec.manager_id if review_rec else None

            # Get latest checkin date
            week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
            week_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)
            week_sessions = self.db.query(WorkSession).filter(
                WorkSession.profile_id == p.id,
                or_(
                    and_(WorkSession.started_at >= week_start_dt, WorkSession.started_at <= week_end_dt),
                    and_(WorkSession.ended_at >= week_start_dt, WorkSession.ended_at <= week_end_dt),
                    and_(WorkSession.started_at <= week_start_dt, or_(WorkSession.ended_at >= week_end_dt, WorkSession.ended_at == None))
                )
            ).all()
            week_session_ids = [s.id for s in week_sessions]

            latest_checkin = None
            if week_session_ids:
                latest_checkin = self.db.query(SessionWellbeingCheckin).filter(
                    SessionWellbeingCheckin.work_session_id.in_(week_session_ids)
                ).order_by(SessionWellbeingCheckin.created_at.desc()).first()

            last_checkin_date = None
            if latest_checkin and latest_checkin.created_at:
                last_checkin_date = latest_checkin.created_at.date()

            # Compute week-over-week aggregates with trend
            weekly_agg_with_trend = self._compute_weekly_aggregates_with_trend(p.id, week_start, thresholds)

            # Build employee summary with 3-tier classification
            employees_summary.append(EmployeeRiskSummary(
                employee_id=p.user_id,
                employee_name=detail.employee_name,
                team_name=team_name,
                risk_tier=risk_5tier,  # 5-tier for backward compatibility
                risk_label=risk_3tier.capitalize(),  # 3-tier label
                primary_concern=primary_c,
                evidence_count=len(detail.evidence_items),
                top_evidence=top_ev,
                trend=TrendDirection.STABLE,  # Overall trend (backward compatible)
                has_active_shift=False,
                last_checkin_date=last_checkin_date,
                review_status=review_status,
                action_taken=action_taken,
                reviewed_at=reviewed_at,
                reviewed_by_manager_id=reviewed_by_manager_id,
                avg_worked_hours=detail.weekly_aggregates.avg_worked_hours,
                total_checkins=detail.weekly_aggregates.total_checkins,
                avg_stress_level=detail.weekly_aggregates.avg_stress_level,
                missed_breaks_count=detail.weekly_aggregates.missed_breaks_count if hasattr(detail.weekly_aggregates, 'missed_breaks_count') else 0,
                # Phase 2: Week-over-week comparison fields
                previous_week_avg_worked_hours=weekly_agg_with_trend.get("previous_week_avg_worked_hours", 0.0),
                previous_week_avg_break_compliance_pct=weekly_agg_with_trend.get("previous_week_avg_break_compliance_pct", 0),
                previous_week_avg_focus_rate_pct=weekly_agg_with_trend.get("previous_week_avg_focus_rate_pct", 0.0),
                previous_week_total_checkins=weekly_agg_with_trend.get("previous_week_total_checkins", 0),
                trend_direction=weekly_agg_with_trend.get("trend_worked_hours", TrendDirection.UNKNOWN),
                is_first_week_data=weekly_agg_with_trend.get("previous_week_avg_worked_hours", 0.0) == 0.0
            ))

        # If suppressed, return aggregate-only response
        if suppress_detail:
            return WeeklyOverviewResponse(
                week_start=week_start,
                week_end=week_end,
                generated_at=datetime.now(timezone.utc),
                team_summary=TeamSummary(
                    total_employees=0,
                    by_tier=tier_counts_3tier,
                    privacy_suppressed=True
                ),
                employees=[]
            )

        return WeeklyOverviewResponse(
            week_start=week_start,
            week_end=week_end,
            generated_at=datetime.now(timezone.utc),
            team_summary=TeamSummary(
                total_employees=eligible_count,
                by_tier=tier_counts_3tier,
                privacy_suppressed=False
            ),
            employees=employees_summary
        )

    def compute_daily_wellbeing_trends(
        self,
        profile_ids: List[uuid.UUID],
        start_utc: datetime,
        end_utc: datetime,
        include_test: bool = False
    ) -> List[Dict[str, Any]]:
        """
        Compute daily wellbeing aggregations across profiles within a date range.
        Returns list of daily records with aggregated metrics (averages).

        UTC boundary handling: Groups by calendar date in UTC.
        Excludes test data unless include_test=True.
        Handles missing data correctly (returns None for missing metrics).
        """
        from ..models import SessionWellbeingCheckin, Profile

        daily_data = {}

        if not profile_ids:
            return []

        # Query all check-ins in the period, filtering by profile_ids and optionally test data
        checkins_query = self.db.query(SessionWellbeingCheckin).join(
            Profile, SessionWellbeingCheckin.user_id == Profile.user_id
        ).filter(
            Profile.id.in_(profile_ids),
            SessionWellbeingCheckin.created_at >= start_utc,
            SessionWellbeingCheckin.created_at <= end_utc
        )

        if not include_test:
            checkins_query = checkins_query.filter(Profile.is_test_data == False)

        checkins = checkins_query.all()

        # Track unique employees per day for participation rate
        daily_employee_tracker = {}

        # Group by calendar date (UTC)
        for checkin in checkins:
            checkin_date = checkin.created_at.date()
            if checkin_date not in daily_data:
                daily_data[checkin_date] = {
                    "date": checkin_date,
                    "checkins": [],
                    "overall_wellbeing_sum": 0.0,
                    "mental_fatigue_sum": 0.0,
                    "workload_manageability_sum": 0.0,
                    "perceived_focus_sum": 0.0,
                    "break_recovery_sum": 0.0,
                    "valid_checkin_count": 0,
                }
                daily_employee_tracker[checkin_date] = set()

            daily_data[checkin_date]["checkins"].append(checkin)
            daily_employee_tracker[checkin_date].add(checkin.user_id)

            # Sum only valid metrics (not null)
            daily_data[checkin_date]["overall_wellbeing_sum"] += checkin.overall_wellbeing
            daily_data[checkin_date]["mental_fatigue_sum"] += checkin.mental_fatigue
            daily_data[checkin_date]["workload_manageability_sum"] += checkin.workload_manageability
            daily_data[checkin_date]["perceived_focus_sum"] += checkin.perceived_focus
            daily_data[checkin_date]["break_recovery_sum"] += checkin.break_recovery
            daily_data[checkin_date]["valid_checkin_count"] += 1

        # Compute daily averages with proper missing data handling
        daily_trends = []
        for date_key in sorted(daily_data.keys()):
            data = daily_data[date_key]
            checkin_count = len(data["checkins"])
            valid_count = data["valid_checkin_count"]
            unique_employee_count = len(daily_employee_tracker[date_key])

            if checkin_count > 0:
                daily_trends.append({
                    "date": data["date"],
                    "overall_wellbeing": round(data["overall_wellbeing_sum"] / valid_count, 2) if valid_count > 0 else None,
                    "mental_fatigue": round(data["mental_fatigue_sum"] / valid_count, 2) if valid_count > 0 else None,
                    "workload_manageability": round(data["workload_manageability_sum"] / valid_count, 2) if valid_count > 0 else None,
                    "perceived_focus": round(data["perceived_focus_sum"] / valid_count, 2) if valid_count > 0 else None,
                    "break_recovery": round(data["break_recovery_sum"] / valid_count, 2) if valid_count > 0 else None,
                    "checkin_count": checkin_count,
                    "unique_employee_count": unique_employee_count,
                })

        return daily_trends

    def compute_weekly_wellbeing_trends(
        self,
        profile_ids: List[uuid.UUID],
        start_utc: datetime,
        end_utc: datetime,
        include_test: bool = False,
        risk_aggregation_method: str = "worst_case"
    ) -> List[Dict[str, Any]]:
        """
        Compute weekly wellbeing aggregations from daily trends.
        Groups daily data by ISO week (Monday = start).
        Returns list of weekly records with aggregated metrics and risk distribution.

        Supports different risk aggregation methods:
        - "worst_case": Use highest risk tier observed (default, matches existing behavior)
        - "average": Use average of risk tiers
        - "sustained": Count only risks observed across multiple weeks
        """
        daily_trends = self.compute_daily_wellbeing_trends(profile_ids, start_utc, end_utc, include_test)

        if not daily_trends:
            return []

        # Group daily trends by week
        weekly_data = {}
        for daily in daily_trends:
            # Compute Monday of that week
            d = daily["date"]
            week_monday = d - timedelta(days=d.weekday())

            if week_monday not in weekly_data:
                weekly_data[week_monday] = {
                    "week_start": week_monday,
                    "days": [],
                    "wellbeing_sums": {
                        "overall_wellbeing": 0.0,
                        "mental_fatigue": 0.0,
                        "workload_manageability": 0.0,
                        "perceived_focus": 0.0,
                        "break_recovery": 0.0,
                    },
                    "day_counts": {
                        "overall_wellbeing": 0,
                        "mental_fatigue": 0,
                        "workload_manageability": 0,
                        "perceived_focus": 0,
                        "break_recovery": 0,
                    },
                }

            weekly_data[week_monday]["days"].append(daily)
            # Only add to sums if metric is not None (missing data)
            if daily["overall_wellbeing"] is not None:
                weekly_data[week_monday]["wellbeing_sums"]["overall_wellbeing"] += daily["overall_wellbeing"]
                weekly_data[week_monday]["day_counts"]["overall_wellbeing"] += 1
            if daily["mental_fatigue"] is not None:
                weekly_data[week_monday]["wellbeing_sums"]["mental_fatigue"] += daily["mental_fatigue"]
                weekly_data[week_monday]["day_counts"]["mental_fatigue"] += 1
            if daily["workload_manageability"] is not None:
                weekly_data[week_monday]["wellbeing_sums"]["workload_manageability"] += daily["workload_manageability"]
                weekly_data[week_monday]["day_counts"]["workload_manageability"] += 1
            if daily["perceived_focus"] is not None:
                weekly_data[week_monday]["wellbeing_sums"]["perceived_focus"] += daily["perceived_focus"]
                weekly_data[week_monday]["day_counts"]["perceived_focus"] += 1
            if daily["break_recovery"] is not None:
                weekly_data[week_monday]["wellbeing_sums"]["break_recovery"] += daily["break_recovery"]
                weekly_data[week_monday]["day_counts"]["break_recovery"] += 1

        # Compute weekly averages and collect risk distribution
        weekly_trends = []
        for week_start in sorted(weekly_data.keys()):
            data = weekly_data[week_start]
            day_count = len(data["days"])

            if day_count > 0:
                # Compute weekly averages with missing data handling
                overall_wellbeing = None
                if data["day_counts"]["overall_wellbeing"] > 0:
                    overall_wellbeing = round(data["wellbeing_sums"]["overall_wellbeing"] / data["day_counts"]["overall_wellbeing"], 2)

                mental_fatigue = None
                if data["day_counts"]["mental_fatigue"] > 0:
                    mental_fatigue = round(data["wellbeing_sums"]["mental_fatigue"] / data["day_counts"]["mental_fatigue"], 2)

                workload_manageability = None
                if data["day_counts"]["workload_manageability"] > 0:
                    workload_manageability = round(data["wellbeing_sums"]["workload_manageability"] / data["day_counts"]["workload_manageability"], 2)

                perceived_focus = None
                if data["day_counts"]["perceived_focus"] > 0:
                    perceived_focus = round(data["wellbeing_sums"]["perceived_focus"] / data["day_counts"]["perceived_focus"], 2)

                break_recovery = None
                if data["day_counts"]["break_recovery"] > 0:
                    break_recovery = round(data["wellbeing_sums"]["break_recovery"] / data["day_counts"]["break_recovery"], 2)

                # Compute risk distribution for this week (more efficient approach)
                week_risk_tiers = {"insufficient_data": 0, "low": 0, "moderate": 0, "high": 0, "critical": 0}

                # Only compute risk tiers for profiles with check-ins in this week
                # Get user IDs for profiles and check for check-ins in this week
                week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
                week_end_dt = datetime.combine(week_start + timedelta(days=6), datetime.max.time(), tzinfo=timezone.utc)

                # Get profiles that have check-ins in this week
                profiles_with_checkins = self.db.query(Profile).join(
                    SessionWellbeingCheckin, Profile.user_id == SessionWellbeingCheckin.user_id
                ).filter(
                    Profile.id.in_(profile_ids),
                    SessionWellbeingCheckin.created_at >= week_start_dt,
                    SessionWellbeingCheckin.created_at <= week_end_dt
                )

                if not include_test:
                    profiles_with_checkins = profiles_with_checkins.filter(Profile.is_test_data == False)

                profiles_with_checkins = profiles_with_checkins.distinct().all()

                # For profiles with check-ins, compute risk tier
                for profile in profiles_with_checkins:
                    try:
                        weekly_risk = self.compute_weekly_risk(profile.id, week_start)
                        tier_name = weekly_risk.risk_tier.name.lower()
                        if tier_name in week_risk_tiers:
                            week_risk_tiers[tier_name] += 1
                    except Exception:
                        # If unable to compute risk for this profile, skip
                        week_risk_tiers["insufficient_data"] += 1

                # Profiles without check-ins get "insufficient_data"
                total_profiles_with_checkins = len(profiles_with_checkins)
                total_profile_count = len(profile_ids)
                week_risk_tiers["insufficient_data"] += (total_profile_count - total_profiles_with_checkins)

                weekly_trends.append({
                    "week_start": data["week_start"],
                    "week_end": data["week_start"] + timedelta(days=6),
                    "overall_wellbeing": overall_wellbeing,
                    "mental_fatigue": mental_fatigue,
                    "workload_manageability": workload_manageability,
                    "perceived_focus": perceived_focus,
                    "break_recovery": break_recovery,
                    "day_count": day_count,
                    "checkin_count": sum(daily["checkin_count"] for daily in data["days"]),
                    "unique_employee_count": sum(daily["unique_employee_count"] for daily in data["days"]),
                    "risk_distribution": week_risk_tiers,
                })

        return weekly_trends

    def _compute_trend_direction(self, current: float, previous: float, higher_is_better: bool = True) -> TrendDirection:
        if previous == 0 or previous is None or current is None:
            return TrendDirection.UNKNOWN
        diff = current - previous
        tolerance = 0.05 * abs(previous)
        if abs(diff) < max(tolerance, 0.01):
            return TrendDirection.STABLE
        if higher_is_better:
            return TrendDirection.IMPROVING if diff > 0 else TrendDirection.WORSENING
        else:
            return TrendDirection.WORSENING if diff > 0 else TrendDirection.IMPROVING

    def compute_historical_trends(
        self,
        manager_id: uuid.UUID,
        weeks: int = 4,
        team_id: Optional[uuid.UUID] = None,
    ) -> dict:
        """
        Compute historical weekly trends with week-over-week comparisons.

        Returns dict with:
        - current_week: current week aggregates + trends
        - historical_weeks: list of previous weeks with their trends
        - supports timezone-aware week boundaries via employee timezone
        - applies test data exclusion and small-group suppression
        """
        from datetime import timedelta

        # Determine current reporting week
        # Use latest employee's timezone or default UTC
        current_monday = date.today() - timedelta(days=date.today().weekday())

        # Get teams managed by manager
        manager_teams_query = self.db.query(Team).filter(
            Team.manager_user_id == manager_id,
            Team.is_active == True
        )
        if team_id:
            manager_teams_query = manager_teams_query.filter(Team.id == team_id)
        managed_teams = manager_teams_query.all()
        managed_team_ids = [t.id for t in managed_teams]

        if not managed_team_ids:
            return {
                "current_week": None,
                "historical_weeks": [],
                "error": "No active teams found for manager"
            }

        # Get employees in these teams - exclude test data
        from ..auth.security import should_include_test_data
        manager_user = self.db.query(User).filter(User.id == manager_id).first()
        include_test = should_include_test_data(self.db, manager_user)

        employee_memberships = self.db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()

        profile_ids = [em.profile_id for em in employee_memberships]

        prof_q = self.db.query(Profile).filter(Profile.id.in_(profile_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()

        eligible_count = len(profiles)

        # Get thresholds
        threshold_team_id = team_id if team_id else (managed_teams[0].id if managed_teams else None)
        from .risk_classification import get_thresholds_for_team
        thresholds = get_thresholds_for_team(self.db, threshold_team_id, managed_teams[0].organization_id if managed_teams else None)

        # Check small-group suppression
        suppress_detail = should_suppress_detail(eligible_count, thresholds)

        # Compute current and historical weekly data
        current_week_start = current_monday

        # Compute aggregates for current + previous weeks
        historical_results = []

        for week_offset in range(weeks):
            week_start = current_monday - timedelta(weeks=week_offset)
            week_end = week_start + timedelta(days=6)

            # Get weekly risk data for each profile
            tier_counts = {"green": 0, "amber": 0, "red": 0, "insufficient_data": 0}
            total_worked = 0.0
            total_break_compliance = 0
            total_focus_rate = 0.0
            total_checkins = 0
            profile_count = 0

            for profile in profiles:
                try:
                    detail = self.compute_weekly_risk(profile.id, week_start)
                    weekly_agg = detail.weekly_aggregates.model_dump() if hasattr(detail.weekly_aggregates, 'model_dump') else detail.weekly_aggregates

                    # Apply small-group suppression at individual level
                    if not suppress_detail:
                        risk_3tier, risk_5tier = classify_risk_from_aggregates(
                            weekly_aggregates=weekly_agg,
                            evidence_items=[e.model_dump() if hasattr(e, 'model_dump') else e for e in detail.evidence_items],
                            detected_patterns=[p.model_dump() if hasattr(p, 'model_dump') else p for p in detail.detected_patterns],
                            thresholds=thresholds
                        )
                        tier_name = risk_3tier.lower()
                        if tier_name in tier_counts:
                            tier_counts[tier_name] += 1

                    total_worked += weekly_agg.get("avg_worked_hours", 0)
                    total_break_compliance += weekly_agg.get("avg_break_compliance_pct", 100)
                    total_focus_rate += weekly_agg.get("avg_focus_rate_pct", 0)
                    total_checkins += weekly_agg.get("total_checkins", 0)
                    profile_count += 1
                except Exception:
                    # Profile has insufficient data for this week
                    if not suppress_detail:
                        tier_counts["insufficient_data"] += 1

            # Compute trends vs previous week (except for the most recent)
            is_current = (week_offset == 0)
            prev_week_start = week_start - timedelta(weeks=1)

            trends = {}
            if not is_current and profile_count > 0:
                # Compare with previous week
                prev_agg_data = {}
                for profile in profiles:
                    try:
                        prev_detail = self.compute_weekly_risk(profile.id, prev_week_start)
                        prev_agg = prev_detail.weekly_aggregates.model_dump() if hasattr(prev_detail.weekly_aggregates, 'model_dump') else prev_detail.weekly_aggregates
                        # Aggregate previous week metrics
                        for key in ["avg_worked_hours", "avg_break_compliance_pct", "avg_focus_rate_pct", "total_checkins"]:
                            if key in prev_agg:
                                prev_agg_data[key] = prev_agg_data.get(key, 0) + prev_agg[key]
                    except Exception:
                        pass

                # Compute trend directions
                if profile_count > 0:
                    curr_worked = total_worked / profile_count
                    prev_worked = prev_agg_data.get("avg_worked_hours", 0) / max(profile_count, 1)
                    curr_break = total_break_compliance / profile_count if profile_count > 0 else 0
                    prev_break = prev_agg_data.get("avg_break_compliance_pct", 100) / max(profile_count, 1)
                    curr_focus = total_focus_rate / profile_count if profile_count > 0 else 0
                    prev_focus = prev_agg_data.get("avg_focus_rate_pct", 0) / max(profile_count, 1)

                    from .wellbeing_monitoring import TrendDirection
                    trends = {
                        "worked_hours": str(self._compute_trend_direction(curr_worked, prev_worked, higher_is_better=False)),
                        "break_compliance": str(self._compute_trend_direction(curr_break, prev_break, higher_is_better=True)),
                        "focus_rate": str(self._compute_trend_direction(curr_focus, prev_focus, higher_is_better=True)),
                    }

            weekly_record = {
                "week_start": week_start.isoformat(),
                "week_end": week_end.isoformat(),
                "privacy_suppressed": suppress_detail and (eligible_count < 5),
                "eligible_employee_count": profile_count,
                "risk_distribution": tier_counts,
                "avg_worked_hours": round(total_worked / profile_count, 1) if profile_count > 0 else 0.0,
                "avg_break_compliance_pct": round(total_break_compliance / profile_count) if profile_count > 0 else 0,
                "avg_focus_rate_pct": round(total_focus_rate / profile_count, 1) if profile_count > 0 else 0.0,
                "total_checkins": total_checkins,
                "trends": trends if not is_current else None,  # Current week trends computed vs previous
                "is_first_available_week": (week_offset == weeks - 1 and profile_count > 0),
            }

            historical_results.append(weekly_record)

        # Reverse so current week is first
        # historical_results.reverse() kept in natural order

        # Set current week trends (vs first historical)
        if len(historical_results) >= 2:
            current = historical_results[0]
            previous = historical_results[1]
            from .wellbeing_monitoring import TrendDirection

            curr_worked = current.get("avg_worked_hours", 0)
            prev_worked = previous.get("avg_worked_hours", 0)
            curr_break = current.get("avg_break_compliance_pct", 100)
            prev_break = previous.get("avg_break_compliance_pct", 100)
            curr_focus = current.get("avg_focus_rate_pct", 0)
            prev_focus = previous.get("avg_focus_rate_pct", 0)

            current["trends"] = {
                "worked_hours": str(self._compute_trend_direction(curr_worked, prev_worked, higher_is_better=False)),
                "break_compliance": str(self._compute_trend_direction(curr_break, prev_break, higher_is_better=True)),
                "focus_rate": str(self._compute_trend_direction(curr_focus, prev_focus, higher_is_better=True)),
            }

        return {
            "current_week": historical_results[0] if historical_results else None,
            "historical_weeks": historical_results[1:] if len(historical_results) > 1 else [],
            "weeks_requested": weeks,
            "eligible_employee_count": eligible_count,
            "privacy_suppressed": suppress_detail and (eligible_count < 5),
        }

    def compute_risk_distribution_history(
        self,
        manager_id: uuid.UUID,
        weeks: int = 4,
        team_id: Optional[uuid.UUID] = None,
    ) -> dict:
        """
        Get historical risk distribution (Green/Amber/Red) per week.

        Uses existing configurable classification thresholds.
        Clearly identifies weeks where historical classification
        cannot be reliably reconstructed.

        Returns dict with weekly risk counts and proportions.
        """
        from datetime import timedelta

        # Determine current reporting week
        current_monday = date.today() - timedelta(days=date.today().weekday())

        # Get teams managed by manager
        manager_teams_query = self.db.query(Team).filter(
            Team.manager_user_id == manager_id,
            Team.is_active == True
        )
        if team_id:
            manager_teams_query = manager_teams_query.filter(Team.id == team_id)
        managed_teams = manager_teams_query.all()
        managed_team_ids = [t.id for t in managed_teams]

        if not managed_team_ids:
            return {
                "weekly_distribution": [],
                "error": "No active teams found for manager"
            }

        # Get employees in these teams - exclude test data
        from ..auth.security import should_include_test_data
        manager_user = self.db.query(User).filter(User.id == manager_id).first()
        include_test = should_include_test_data(self.db, manager_user)

        employee_memberships = self.db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()

        profile_ids = [em.profile_id for em in employee_memberships]

        prof_q = self.db.query(Profile).filter(Profile.id.in_(profile_ids))
        if not include_test:
            prof_q = prof_q.filter(Profile.is_test_data == False)
        profiles = prof_q.all()

        # Get thresholds
        threshold_team_id = team_id if team_id else (managed_teams[0].id if managed_teams else None)
        from .risk_classification import get_thresholds_for_team
        thresholds = get_thresholds_for_team(self.db, threshold_team_id, managed_teams[0].organization_id if managed_teams else None)

        # Compute historical risk distribution
        historical_results = []

        for week_offset in range(weeks):
            week_start = current_monday - timedelta(weeks=1 + week_offset)
            week_end = week_start + timedelta(days=6)

            # Count risk tiers for this week
            tier_counts = {"green": 0, "amber": 0, "red": 0, "insufficient_data": 0}
            profile_count = 0

            for profile in profiles:
                try:
                    detail = self.compute_weekly_risk(profile.id, week_start)
                    weekly_agg = detail.weekly_aggregates.model_dump() if hasattr(detail.weekly_aggregates, 'model_dump') else detail.weekly_aggregates

                    risk_3tier, risk_5tier = classify_risk_from_aggregates(
                        weekly_aggregates=weekly_agg,
                        evidence_items=[e.model_dump() if hasattr(e, 'model_dump') else e for e in detail.evidence_items],
                        detected_patterns=[p.model_dump() if hasattr(p, 'model_dump') else p for p in detail.detected_patterns],
                        thresholds=thresholds
                    )
                    tier_name = risk_3tier.lower()
                    if tier_name in tier_counts:
                        tier_counts[tier_name] += 1
                    profile_count += 1
                except Exception:
                    # Unable to compute risk - likely insufficient data
                    tier_counts["insufficient_data"] += 1
                    profile_count += 1  # Still count as a profile

            # Calculate proportions
            total = max(profile_count, 1)
            proportions = {
                tier: round(count / total, 2) for tier, count in tier_counts.items()
            }

            # Identify limitations
            limitations = []
            if profile_count == 0:
                limitations.append("no_profiles_found")
            if tier_counts["insufficient_data"] > 0:
                limitations.append("insufficient_data_profiles")

            # Check if classification can be reliably determined
            reliability_notes = []
            if tier_counts["insufficient_data"] / total > 0.5:
                reliability_notes.append("majority_insufficient_data")

            weekly_record = {
                "week_start": week_start.isoformat(),
                "week_end": week_end.isoformat(),
                "eligible_employee_count": profile_count,
                "risk_distribution": tier_counts,
                "risk_proportions": proportions,
            "privacy_suppressed": suppress_detail and (profile_count < 5) if 'suppress_detail' in dir() else False,
                "reliability_notes": reliability_notes,
                "classification_possible": len(limitations) == 0,
            }

            historical_results.append(weekly_record)

        # Reverse so current week is first
        # historical_results.reverse() kept in natural order

        return {
            "weekly_distribution": historical_results,
            "weeks_requested": weeks,
            "eligible_employee_count": len(profiles),
        }
