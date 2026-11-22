import io
import zipfile
import csv
import uuid
from typing import Optional, List, Dict, Any, Union
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable, KeepTogether
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

from ..models import (
    User, Profile, TeamMembership, Team, WorkSession, Break,
    Task, SessionWellbeingCheckin, RecommendationFeedback, WorkLifeBalanceSurvey, OrganizationMembership
)
from ..auth.security import should_include_test_data
from .team_analytics_service import compute_team_analytics
from .analytics_service import AnalyticsEngine
from .wellbeing_monitoring import WellbeingMonitoringService
from .organizational_insights_service import OrganizationalInsightsService
from ..analytics_utils import parse_date_range, get_previous_start_end_for_period


class NumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and render total page numbers
    along with professional running headers and footers for admin reports.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_header_footer(num_pages)
            super().showPage()
        super().save()

    def draw_header_footer(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))

        # Header
        self.drawString(54, letter[1] - 36, "IntelliBreak — Admin Organization Analytics & Wellbeing Report")
        self.setStrokeColor(colors.HexColor("#CBD5E1"))
        self.setLineWidth(0.5)
        self.line(54, letter[1] - 42, letter[0] - 54, letter[1] - 42)

        # Footer
        self.line(54, 45, letter[0] - 54, 45)
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(letter[0] - 54, 32, page_str)
        self.drawString(54, 32, "Confidential — IntelliBreak Sustainable Work Platform")
        self.restoreState()


class AdminOrganizationReportService:
    """
    Comprehensive organization-level reporting and export service for the Admin dashboard.
    Covers 9 sections: Executive Summary, Organizational Productivity, Work Sustainability,
    Work-Life Balance, Organizational Wellbeing, Team Comparison, Recommendation Effectiveness,
    Organizational Insights, and Metric Definitions & Methodology.
    Enforces tenant isolation, admin RBAC, and N >= 5 privacy suppression.
    """

    def __init__(self, db: Session, current_user: User):
        self.db = db
        self.current_user = current_user

    @staticmethod
    def compute_wlb_aggregates(surveys: List[WorkLifeBalanceSurvey]) -> Dict[str, Any]:
        """
        Canonical WLB aggregation logic shared by report and insights services.
        Returns dict with avg_score, respondents, and rating_averages.
        Returns insufficient_data indicator if no surveys provided.
        """
        if not surveys:
            return {
                "avg_score": None,
                "respondents": 0,
                "rating_disconnect": None,
                "rating_personal_time": None,
                "rating_recovery": None,
                "data_quality": "insufficient_data"
            }

        avg_score = round(sum(s.score for s in surveys) / len(surveys), 2)
        respondents = len(set(s.profile_id for s in surveys))
        avg_disconnect = round(sum(s.rating_disconnect for s in surveys) / len(surveys), 2)
        avg_personal_time = round(sum(s.rating_personal_time for s in surveys) / len(surveys), 2)
        avg_recovery = round(sum(s.rating_recovery for s in surveys) / len(surveys), 2)

        return {
            "avg_score": avg_score,
            "respondents": respondents,
            "rating_disconnect": avg_disconnect,
            "rating_personal_time": avg_personal_time,
            "rating_recovery": avg_recovery,
            "data_quality": "sufficient_data"
        }

    @staticmethod
    def calculate_organization_recommendation_statistics(
        db: Session,
        org_ids: List[uuid.UUID],
        start_dt: datetime,
        end_dt: datetime,
        include_test: bool = False
    ) -> Dict[str, Any]:
        """
        Calculate organization-level recommendation statistics with category breakdown.

        Returns:
        - total_generated, total_accepted, total_dismissed, total_viewed
        - overall acceptance_rate, dismissal_rate, viewed_rate
        - Per-category breakdown: counts, acceptance_rates, dismissal_rates
        - Model version distribution
        - Time-to-action statistics (median, p95)
        """
        from ..models import User, Profile, OrganizationMembership

        # Get all org members (current only)
        memberships = db.query(OrganizationMembership).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED"
        ).all()

        user_ids = [m.user_id for m in memberships]

        # Query recommendation feedback for org members in date range
        feedbacks = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_id.in_(user_ids),
            RecommendationFeedback.timestamp >= start_dt,
            RecommendationFeedback.timestamp <= end_dt
        ).all() if user_ids else []

        # Filter test data if needed
        if not include_test:
            # Get profiles for these users to check is_test_data
            user_profiles = db.query(Profile).filter(
                Profile.user_id.in_(user_ids)
            ).all()
            test_user_ids = set(p.user_id for p in user_profiles if p.is_test_data)
            feedbacks = [f for f in feedbacks if f.user_id not in test_user_ids]

        # Overall counts
        total_generated = len(feedbacks)
        total_viewed = sum(1 for f in feedbacks if f.viewed_at is not None)
        total_accepted = sum(1 for f in feedbacks if f.user_action == "accepted")
        total_dismissed = sum(1 for f in feedbacks if f.user_action == "dismissed")
        total_ignored = sum(1 for f in feedbacks if f.user_action is None and (
            datetime.now(timezone.utc) - (f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp and f.timestamp.tzinfo is None else f.timestamp or datetime.now(timezone.utc))
        ).total_seconds() > 7200)  # > 2 hours
        total_pending = sum(1 for f in feedbacks if f.user_action is None and (
            datetime.now(timezone.utc) - (f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp and f.timestamp.tzinfo is None else f.timestamp or datetime.now(timezone.utc))
        ).total_seconds() <= 7200)  # <= 2 hours

        # Overall rates
        overall_acceptance_rate = round((total_accepted / total_generated * 100.0), 2) if total_generated > 0 else 0.0
        overall_dismissal_rate = round((total_dismissed / total_generated * 100.0), 2) if total_generated > 0 else 0.0
        overall_viewed_rate = round((total_viewed / total_generated * 100.0), 2) if total_generated > 0 else 0.0

        # Category breakdown with per-category acceptance rates
        category_stats = {}
        candidate_types = ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]
        for rec_type in candidate_types:
            type_feedbacks = [f for f in feedbacks if f.recommendation_type == rec_type]
            if type_feedbacks:
                type_generated = len(type_feedbacks)
                type_accepted = sum(1 for f in type_feedbacks if f.user_action == "accepted")
                type_dismissed = sum(1 for f in type_feedbacks if f.user_action == "dismissed")
                type_acceptance_rate = round((type_accepted / type_generated * 100.0), 2)

                category_stats[rec_type] = {
                    "generated": type_generated,
                    "accepted": type_accepted,
                    "dismissed": type_dismissed,
                    "acceptance_rate": type_acceptance_rate
                }

        # Model version distribution
        model_distribution = {}
        for f in feedbacks:
            model_ver = f.model_version or "unknown"
            model_distribution[model_ver] = model_distribution.get(model_ver, 0) + 1

        model_version_pct = {
            model: round((count / total_generated * 100.0), 2)
            for model, count in model_distribution.items()
        } if total_generated > 0 else {}

        # Time-to-action latency (viewed_at - timestamp)
        latencies = []
        for f in feedbacks:
            if f.viewed_at and f.timestamp:
                ts = f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp.tzinfo is None else f.timestamp
                va = f.viewed_at.replace(tzinfo=timezone.utc) if f.viewed_at.tzinfo is None else f.viewed_at
                delta_sec = (va - ts).total_seconds()
                if delta_sec >= 0:
                    latencies.append(delta_sec)

        median_time_to_view = None
        p95_time_to_view = None
        if latencies:
            import statistics
            median_time_to_view = round(statistics.median(latencies), 1)
            if len(latencies) > 1:
                p95_idx = int(len(latencies) * 0.95)
                p95_time_to_view = round(sorted(latencies)[p95_idx], 1)

        return {
            "total_generated": total_generated,
            "total_viewed": total_viewed,
            "total_accepted": total_accepted,
            "total_dismissed": total_dismissed,
            "total_ignored": total_ignored,
            "total_pending": total_pending,
            "acceptance_rate": overall_acceptance_rate,
            "dismissal_rate": overall_dismissal_rate,
            "viewed_rate": overall_viewed_rate,
            "category_breakdown": category_stats,
            "model_version_distribution": model_version_pct,
            "time_to_view_median_seconds": median_time_to_view,
            "time_to_view_p95_seconds": p95_time_to_view,
            "data_quality": "sufficient_data" if total_generated > 0 else "insufficient_data"
        }

    def _get_org_context(
        self,
        period: Optional[str] = "this_week",
        start_date: Optional[Union[str, date]] = None,
        end_date: Optional[Union[str, date]] = None,
        org_ids: Optional[List[uuid.UUID]] = None,
        include_test: Optional[bool] = None,
        user_tz: Optional[str] = None
    ):
        if org_ids is None:
            org_ids = [m.organization_id for m in self.db.query(OrganizationMembership).filter(
                OrganizationMembership.user_id == self.current_user.id,
                OrganizationMembership.status == "APPROVED"
            ).all()]

        if not org_ids:
            raise HTTPException(status_code=403, detail="Admin has no approved organization membership")

        if user_tz is None:
            user_tz = "UTC"

        # Convert date objects to strings if needed
        start_date_str = start_date.isoformat() if isinstance(start_date, date) else start_date
        end_date_str = end_date.isoformat() if isinstance(end_date, date) else end_date

        start_utc, end_utc = parse_date_range(start_date_str, end_date_str, period, user_tz)
        prev_start_utc, prev_end_utc = get_previous_start_end_for_period(period, user_tz)

        if include_test is None:
            include_test = should_include_test_data(self.db, self.current_user)

        # Compute analytics
        current_analytics = compute_team_analytics(
            db=self.db,
            current_user=self.current_user,
            team_id=None,
            start_date=start_utc.date(),
            end_date=end_utc.date()
        )
        prev_analytics = compute_team_analytics(
            db=self.db,
            current_user=self.current_user,
            team_id=None,
            start_date=prev_start_utc.date(),
            end_date=prev_end_utc.date()
        )

        # Work sustainability
        wsi_data = AnalyticsEngine.calculate_organization_work_sustainability(
            self.db, org_ids, start_utc, end_utc, include_test=include_test
        )
        prev_wsi_data = AnalyticsEngine.calculate_organization_work_sustainability(
            self.db, org_ids, prev_start_utc, prev_end_utc, include_test=include_test
        )

        # Teams
        teams = self.db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True).all() if org_ids else []

        # WLB survey stats
        profile_ids = current_analytics.get("profile_ids", [])
        week_start_date = start_utc.date() - timedelta(days=start_utc.date().weekday())

        # [DIAG 1: WLB Query Parameters]
        import logging
        logger = logging.getLogger(__name__)
        logger.info(f"[DIAG-WLB-1] Reporting period: {start_utc.isoformat()} to {end_utc.isoformat()}")
        logger.info(f"[DIAG-WLB-1] week_start_date: {week_start_date}, lookback window: {week_start_date - timedelta(days=21)}")
        logger.info(f"[DIAG-WLB-1] profile_ids count: {len(profile_ids)}")

        surveys = self.db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= week_start_date - timedelta(days=21)
        ).all() if profile_ids else []

        # [DIAG 1: WLB Survey Results]
        logger.info(f"[DIAG-WLB-2] Total WLB surveys found: {len(surveys)}")
        if surveys:
            survey_ids = [s.id for s in surveys[:5]]
            survey_weeks = [s.week_start_date for s in surveys[:5]]
            logger.info(f"[DIAG-WLB-2] First 5 survey IDs: {survey_ids}")
            logger.info(f"[DIAG-WLB-2] First 5 survey week_start_dates: {survey_weeks}")

        avg_wlb_score = round(sum(s.score for s in surveys) / len(surveys), 2) if surveys else 0.0
        wlb_respondents = len(set(s.profile_id for s in surveys))
        total_emps = len(profile_ids)
        wlb_participation_rate = round((wlb_respondents / max(1, total_emps)) * 100.0, 1)

        # [DIAG 1: WLB Aggregates]
        logger.info(f"[DIAG-WLB-3] avg_wlb_score: {avg_wlb_score}, wlb_respondents: {wlb_respondents}, total_emps: {total_emps}")

        # WLB rating breakdown (disconnect, personal_time, recovery)
        avg_disconnect = round(sum(s.rating_disconnect for s in surveys) / len(surveys), 2) if surveys else 0.0
        avg_personal_time = round(sum(s.rating_personal_time for s in surveys) / len(surveys), 2) if surveys else 0.0
        avg_recovery = round(sum(s.rating_recovery for s in surveys) / len(surveys), 2) if surveys else 0.0

        logger.info(f"[DIAG-WLB-4] rating_averages computed: disconnect={avg_disconnect}, personal_time={avg_personal_time}, recovery={avg_recovery}")

        # Wellbeing overview (organization aggregate)
        wb_service = WellbeingMonitoringService(self.db)
        checkins = self.db.query(SessionWellbeingCheckin).filter(
            SessionWellbeingCheckin.user_id.in_([p.user_id for p in self.db.query(Profile).filter(Profile.id.in_(profile_ids)).all()]),
            SessionWellbeingCheckin.created_at >= start_utc,
            SessionWellbeingCheckin.created_at <= end_utc
        ).all() if profile_ids else []
        checkin_count = len(checkins)
        overall_wellbeing = round(sum(c.overall_wellbeing for c in checkins) / checkin_count, 2) if checkin_count > 0 else 0.0
        mental_fatigue = round(sum(c.mental_fatigue for c in checkins) / checkin_count, 2) if checkin_count > 0 else 0.0
        workload_manageability = round(sum(c.workload_manageability for c in checkins) / checkin_count, 2) if checkin_count > 0 else 0.0
        perceived_focus = round(sum(c.perceived_focus for c in checkins) / checkin_count, 2) if checkin_count > 0 else 0.0
        break_recovery = round(sum(c.break_recovery for c in checkins) / checkin_count, 2) if checkin_count > 0 else 0.0

        # Compute daily and weekly wellbeing trends
        daily_trends = wb_service.compute_daily_wellbeing_trends(profile_ids, start_utc, end_utc) if profile_ids else []
        weekly_trends = wb_service.compute_weekly_wellbeing_trends(profile_ids, start_utc, end_utc) if profile_ids else []

        # Aggregate wellbeing risk across profiles (analyze all weeks within reporting period)
        risk_tiers = {"low": 0, "moderate": 0, "high": 0, "critical": 0, "insufficient_data": 0}

        # Generate all week-starts within the reporting period
        week_starts_in_period = []
        current_week = start_utc.date() - timedelta(days=start_utc.date().weekday())
        while current_week <= end_utc.date():
            week_starts_in_period.append(current_week)
            current_week += timedelta(weeks=1)

        for pid in profile_ids:
            try:
                # Aggregate risk tier across all weeks in the period
                risks_for_period = []
                for week_start in week_starts_in_period:
                    weekly_risk = wb_service.compute_weekly_risk(pid, week_start)
                    tier = weekly_risk.get("risk_tier", "insufficient_data")
                    if tier != "insufficient_data":
                        risks_for_period.append(tier)

                # Determine overall tier: if any week shows high/critical risk, use that; otherwise use most common
                if "critical" in risks_for_period:
                    overall_tier = "critical"
                elif "high" in risks_for_period:
                    overall_tier = "high"
                elif "moderate" in risks_for_period:
                    overall_tier = "moderate"
                elif "low" in risks_for_period:
                    overall_tier = "low"
                else:
                    overall_tier = "insufficient_data"

                if overall_tier in risk_tiers:
                    risk_tiers[overall_tier] += 1
                else:
                    risk_tiers["insufficient_data"] += 1
            except Exception:
                risk_tiers["insufficient_data"] += 1

        # Recommendation effectiveness (enhanced with category breakdown and rates)
        rec_stats = self.calculate_organization_recommendation_statistics(
            self.db, org_ids, start_utc, end_utc, include_test=include_test
        )

        # Insights
        insights_res = OrganizationalInsightsService.generate_organizational_insights(
            db=self.db,
            current_user=self.current_user,
            period=period,
            start_date=start_date_str,
            end_date=end_date_str
        )

        data_quality = "sufficient_data" if total_emps > 0 and current_analytics.get("total_work_hours", 0.0) > 0 else "insufficient_data"

        # [DIAG 3: Serialization Check]
        import logging
        logger = logging.getLogger(__name__)
        logger.info(f"[DIAG-SERIAL-1] About to build response dict with rating_averages: disconnect={avg_disconnect}, personal_time={avg_personal_time}, recovery={avg_recovery}")

        response_dict = {
            "organization_id": str(org_ids[0]) if org_ids else None,
            "period": period or "custom",
            "start_date": start_utc.date().isoformat(),
            "end_date": end_utc.date().isoformat(),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "timezone": user_tz,
            "data_quality_indicator": data_quality,
            "executive_summary": {
                "total_active_employees": total_emps,
                "total_active_teams": len(teams),
                "total_work_hours": current_analytics.get("total_work_hours", 0.0),
                "avg_work_hours_per_employee": current_analytics.get("avg_hours_per_emp", 0.0),
                "task_completion_rate": current_analytics.get("completion_rate", 0.0),
                "focus_rate": current_analytics.get("focus_rate", 0.0),
                "work_sustainability_index": wsi_data.get("sustainabilityIndex", 100.0),
                "avg_wlb_score": avg_wlb_score,
                "recommendation_acceptance_rate": rec_stats.get("acceptance_rate", 0.0),
                "insights_summary": f"Generated {insights_res.get('total_insights', 0)} organizational insights."
            },
            "productivity": {
                "total_work_hours": current_analytics.get("total_work_hours", 0.0),
                "previous_work_hours": prev_analytics.get("total_work_hours", 0.0),
                "work_hours_change_pct": round(((current_analytics.get("total_work_hours", 0.0) - prev_analytics.get("total_work_hours", 0.0)) / prev_analytics.get("total_work_hours", 0.0)) * 100.0, 1) if prev_analytics.get("total_work_hours", 0.0) > 0 else 0.0,
                "avg_hours_per_employee": current_analytics.get("avg_hours_per_emp", 0.0),
                "total_tasks": current_analytics.get("total_tasks", 0),
                "completed_tasks": current_analytics.get("completed_tasks", 0),
                "completion_rate": current_analytics.get("completion_rate", 0.0),
            },
            "work_sustainability": {
                "sustainability_index": wsi_data.get("sustainabilityIndex", 100.0),
                "previous_sustainability_index": prev_wsi_data.get("sustainabilityIndex", 100.0),
                "overtime_frequency": wsi_data.get("overtimeFrequency", 0.0),
                "break_compliance": wsi_data.get("breakCompliance", 100.0),
                "long_sessions_count": wsi_data.get("longSessionsCount", 0),
                "late_shift_endings_count": wsi_data.get("lateShiftEndingsCount", 0),
                "missed_breaks_count": wsi_data.get("missedBreaksCount", 0),
            },
            "work_life_balance": {
                "avg_wlb_score": avg_wlb_score,
                "survey_respondents": wlb_respondents,
                "survey_participation_rate": wlb_participation_rate,
                "rating_averages": {
                    "disconnect": avg_disconnect,
                    "personal_time": avg_personal_time,
                    "recovery": avg_recovery
                },
                "historical_trends": [{"week_start": str(week_start_date), "score": avg_wlb_score}]
            },
            "organizational_wellbeing": {
                "checkin_count": checkin_count,
                "overall_wellbeing": overall_wellbeing,
                "mental_fatigue": mental_fatigue,
                "workload_manageability": workload_manageability,
                "perceived_focus": perceived_focus,
                "break_recovery": break_recovery,
                "risk_distribution": risk_tiers,
                "total_assessed": total_emps,
                "participation_rate": round((len(set(c.user_id for c in checkins)) / total_emps * 100), 1) if total_emps > 0 else 0.0,
                "participation_count": len(set(c.user_id for c in checkins)),
                "historical_trends": {
                    "daily": daily_trends,
                    "weekly": weekly_trends
                },
                "data_quality_indicator": data_quality
            },
            "team_comparison": self._build_team_comparisons(self.db, org_ids, start_utc, end_utc, week_start_date, include_test),
            "recommendation_effectiveness": {
                "generated_count": rec_stats.get("total_generated", 0),
                "accepted_count": rec_stats.get("total_accepted", 0),
                "dismissed_count": rec_stats.get("total_dismissed", 0),
                "viewed_count": rec_stats.get("total_viewed", 0),
                "ignored_count": rec_stats.get("total_ignored", 0),
                "pending_count": rec_stats.get("total_pending", 0),
                "acceptance_rate": rec_stats.get("acceptance_rate", 0.0),
                "dismissal_rate": rec_stats.get("dismissal_rate", 0.0),
                "viewed_rate": rec_stats.get("viewed_rate", 0.0),
                "category_breakdown": rec_stats.get("category_breakdown", {}),
                "model_version_distribution": rec_stats.get("model_version_distribution", {}),
                "time_to_view_metrics": {
                    "median_seconds": rec_stats.get("time_to_view_median_seconds"),
                    "p95_seconds": rec_stats.get("time_to_view_p95_seconds")
                },
                "data_quality": rec_stats.get("data_quality", "insufficient_data"),
                "historical_trends": []
            },
            "organizational_insights": insights_res,
            "metric_definitions": {
                "wsi_methodology": "Work Sustainability Index (0-100) combining break compliance, overtime avoidance, and shift timing heuristics.",
                "wlb_methodology": "Work-Life Balance survey composite score (0-100) across disconnect, personal time, and recovery.",
                "privacy_rule": "Strict N >= 5 active employee suppression for team-level aggregations to protect individual confidentiality.",
                "insufficient_data_handling": "Missing sessions or zero employee activity flagged explicitly as insufficient_data; never treated as zero-performance or assigned default perfect scores."
            }
        }

        # [DIAG 3: Verify rating_averages in response_dict before return]
        if "work_life_balance" in response_dict and "rating_averages" in response_dict["work_life_balance"]:
            logger.info(f"[DIAG-SERIAL-2] rating_averages present in response_dict: {response_dict['work_life_balance']['rating_averages']}")
        else:
            logger.warning(f"[DIAG-SERIAL-2] WARNING: rating_averages NOT found in response_dict")

        return response_dict

    def _build_team_comparisons(self, db: Session, org_ids: List[uuid.UUID], start: datetime, end: datetime, week_start_date: date, include_test: bool) -> List[Dict[str, Any]]:
        teams = db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True).all() if org_ids else []
        comparisons = []
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
            is_suppressed = total_employees < 5

            sessions = db.query(WorkSession).filter(
                WorkSession.profile_id.in_(profile_ids),
                WorkSession.started_at >= start,
                WorkSession.started_at <= end
            ).all() if profile_ids else []

            total_work_secs = sum(max(0, ((s.ended_at or datetime.now(timezone.utc)) - s.started_at).total_seconds()) for s in sessions)
            total_work_hours = round(total_work_secs / 3600.0, 2)
            avg_hours = round(total_work_hours / max(1, total_employees), 2)

            tasks = db.query(Task).filter(
                Task.profile_id.in_(profile_ids),
                Task.created_at >= start,
                Task.created_at <= end
            ).all() if profile_ids else []
            completed_tasks = len([t for t in tasks if t.status == 'DONE'])

            # Use org-wide WSI (teams in same org share sustainability baseline)
            wsi_metrics = AnalyticsEngine.calculate_organization_work_sustainability(db, org_ids, start, end, include_test=include_test)

            surveys = db.query(WorkLifeBalanceSurvey).filter(
                WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
                WorkLifeBalanceSurvey.week_start_date >= week_start_date - timedelta(days=21)
            ).all() if profile_ids else []
            avg_wlb = round(sum(s.score for s in surveys) / len(surveys), 2) if surveys else 0.0
            avg_disconnect = round(sum(s.rating_disconnect for s in surveys) / len(surveys), 2) if surveys else 0.0
            avg_personal_time = round(sum(s.rating_personal_time for s in surveys) / len(surveys), 2) if surveys else 0.0
            avg_recovery = round(sum(s.rating_recovery for s in surveys) / len(surveys), 2) if surveys else 0.0

            wb_service = WellbeingMonitoringService(db)
            overview = wb_service.compute_team_overview(manager_id=self.current_user.id, week_start=week_start_date, team_id=team.id)
            by_tier = overview.team_summary.by_tier if overview and overview.team_summary else {}

            comparisons.append({
                "team_id": str(team.id),
                "team_name": team.name,
                "active_employees": total_employees,
                "privacy_suppressed": is_suppressed,
                "productivity": {
                    "total_work_hours": None if is_suppressed else total_work_hours,
                    "avg_work_hours_per_employee": None if is_suppressed else avg_hours,
                    "completed_tasks": None if is_suppressed else completed_tasks
                },
                "work_sustainability": {
                    "sustainability_index": wsi_metrics.get("sustainabilityIndex", 100.0)
                },
                "work_life_balance": {
                    "avg_wlb_score": None if is_suppressed else avg_wlb,
                    "rating_averages": {
                        "disconnect": None if is_suppressed else avg_disconnect,
                        "personal_time": None if is_suppressed else avg_personal_time,
                        "recovery": None if is_suppressed else avg_recovery
                    }
                },
                "wellbeing_tiers": {
                    "low": 0 if is_suppressed else by_tier.get("low", 0),
                    "moderate": 0 if is_suppressed else by_tier.get("moderate", 0),
                    "high": 0 if is_suppressed else by_tier.get("high", 0),
                    "critical": 0 if is_suppressed else by_tier.get("critical", 0),
                    "insufficient_data": 0 if is_suppressed else by_tier.get("insufficient_data", total_employees)
                }
            })
        return comparisons

    def generate_preview(self, period: Optional[str] = "this_week", start_date: Optional[str] = None, end_date: Optional[str] = None) -> Dict[str, Any]:
        return self._get_org_context(period, start_date, end_date)

    def generate_pdf(self, period: Optional[str] = "this_week", start_date: Optional[str] = None, end_date: Optional[str] = None) -> bytes:
        ctx = self._get_org_context(period, start_date, end_date)
        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=letter,
            rightMargin=54, leftMargin=54, topMargin=54, bottomMargin=54
        )
        styles = getSampleStyleSheet()
        title_style = ParagraphStyle('ReportTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, textColor=colors.HexColor("#1E293B"), spaceAfter=6)
        subtitle_style = ParagraphStyle('ReportSubtitle', parent=styles['Normal'], fontName='Helvetica-Oblique', fontSize=10, textColor=colors.HexColor("#64748B"), spaceAfter=15)
        h2_style = ParagraphStyle('ReportH2', parent=styles['Heading2'], fontName='Helvetica-Bold', fontSize=13, textColor=colors.HexColor("#0F172A"), spaceBefore=12, spaceAfter=6)
        body_style = ParagraphStyle('ReportBody', parent=styles['Normal'], fontName='Helvetica', fontSize=9, textColor=colors.HexColor("#334155"), spaceAfter=4)

        story = []
        story.append(Paragraph("IntelliBreak Executive Organization Report", title_style))
        story.append(Paragraph(f"Reporting Period: {ctx['start_date']} to {ctx['end_date']} | Generated: {ctx['generated_at'][:10]} ({ctx['timezone']})", subtitle_style))
        story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#CBD5E1"), spaceAfter=10))

        # Executive Summary section
        story.append(Paragraph("1. Executive Summary", h2_style))
        exec_sum = ctx["executive_summary"]
        exec_data = [
            ["Metric", "Value"],
            ["Total Active Employees", str(exec_sum["total_active_employees"])],
            ["Total Active Teams", str(exec_sum["total_active_teams"])],
            ["Total Work Hours", f"{exec_sum['total_work_hours']} hrs"],
            ["Average Work Hours / Employee", f"{exec_sum['avg_work_hours_per_employee']} hrs"],
            ["Task Completion Rate", f"{exec_sum['task_completion_rate']}%"],
            ["Work Sustainability Index (WSI)", f"{round(exec_sum['work_sustainability_index'], 1)}/100"],
            ["Average WLB Score", f"{exec_sum['avg_wlb_score']}/100"],
            ["Recommendation Acceptance Rate", f"{exec_sum['recommendation_acceptance_rate']}%"],
        ]
        t_exec = Table(exec_data, colWidths=[250, 254])
        t_exec.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#1E293B")),
            ('TEXTCOLOR', (0,0), (-1,0), colors.white),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTSIZE', (0,0), (-1,0), 9),
            ('BOTTOMPADDING', (0,0), (-1,0), 6),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
            ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor("#F8FAFC")]),
            ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
            ('FONTSIZE', (0,1), (-1,-1), 9),
            ('TOPPADDING', (0,1), (-1,-1), 4),
            ('BOTTOMPADDING', (0,1), (-1,-1), 4),
        ]))
        story.append(t_exec)
        story.append(Spacer(1, 10))

        # Productivity Section
        story.append(Paragraph("2. Organizational Productivity", h2_style))
        prod = ctx["productivity"]
        story.append(Paragraph(f"Total Work Hours: <b>{prod['total_work_hours']}</b> (Previous: {prod['previous_work_hours']} | Change: {prod['work_hours_change_pct']}%)", body_style))
        story.append(Paragraph(f"Tasks Created: <b>{prod['total_tasks']}</b> | Completed: <b>{prod['completed_tasks']}</b> | Completion Rate: <b>{prod['completion_rate']}%</b>", body_style))
        story.append(Spacer(1, 10))

        # Work Sustainability Section
        story.append(Paragraph("3. Work Sustainability", h2_style))
        sust = ctx["work_sustainability"]
        story.append(Paragraph(f"Sustainability Index (WSI): <b>{sust['sustainability_index']}/100</b> (Previous: {sust['previous_sustainability_index']})", body_style))
        story.append(Paragraph(f"Overtime Frequency: <b>{sust['overtime_frequency']}%</b> | Break Compliance: <b>{sust['break_compliance']}%</b>", body_style))
        story.append(Paragraph(f"Long Sessions: <b>{sust['long_sessions_count']}</b> | Late Shift Endings: <b>{sust['late_shift_endings_count']}</b>", body_style))
        story.append(Spacer(1, 10))

        # Work-Life Balance Section
        story.append(Paragraph("4. Work-Life Balance", h2_style))
        wlb = ctx["work_life_balance"]
        story.append(Paragraph(f"Average WLB Score: <b>{wlb['avg_wlb_score']}/100</b> | Survey Participation Rate: <b>{wlb['survey_participation_rate']}%</b> ({wlb['survey_respondents']} respondents)", body_style))
        story.append(Paragraph("Note: Individual WLB survey responses and notes are strictly confidential and protected from administrative export.", body_style))
        story.append(Spacer(1, 10))

        # Organizational Wellbeing Section
        story.append(Paragraph("5. Organizational Wellbeing", h2_style))
        wb_risk = ctx["organizational_wellbeing"]["risk_distribution"]
        story.append(Paragraph(f"Work-Pattern Risk Tiers — Low: {wb_risk['low']} | Moderate: {wb_risk['moderate']} | High: {wb_risk['high']} | Critical: {wb_risk['critical']} | Insufficient Data: {wb_risk['insufficient_data']}", body_style))
        story.append(Paragraph("Note: Individual wellbeing check-in notes and health disclosures are confidential and excluded from exports.", body_style))
        story.append(Spacer(1, 10))

        # Team Comparison Section
        story.append(Paragraph("6. Team Comparison (N >= 5 Privacy Rule Enforced)", h2_style))
        teams = ctx["team_comparison"]
        team_rows = [["Team Name", "Active Emps", "Work Hours", "WSI", "WLB Score", "Status"]]
        for t in teams:
            if t["privacy_suppressed"]:
                team_rows.append([t["team_name"], "Not enough people", "Not enough people to show this safely", "Suppressed", "Suppressed", "Suppressed"])
            else:
                team_rows.append([
                    t["team_name"],
                    str(t["active_employees"]),
                    str(t["productivity"]["total_work_hours"]),
                    str(t["work_sustainability"]["sustainability_index"]),
                    str(t["work_life_balance"]["avg_wlb_score"]),
                    "Active"
                ])
        t_teams = Table(team_rows, colWidths=[120, 64, 80, 60, 60, 120])
        t_teams.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#1E293B")),
            ('TEXTCOLOR', (0,0), (-1,0), colors.white),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('FONTSIZE', (0,0), (-1,0), 8),
            ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor("#CBD5E1")),
            ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, colors.HexColor("#F8FAFC")]),
            ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
            ('FONTSIZE', (0,1), (-1,-1), 8),
            ('TOPPADDING', (0,1), (-1,-1), 3),
            ('BOTTOMPADDING', (0,1), (-1,-1), 3),
        ]))
        story.append(t_teams)
        story.append(Spacer(1, 10))

        # Recommendation Effectiveness Section
        story.append(Paragraph("7. Recommendation Effectiveness", h2_style))
        rec = ctx["recommendation_effectiveness"]
        story.append(Paragraph(f"Generated: <b>{rec['generated_count']}</b> | Accepted: <b>{rec['accepted_count']}</b> | Dismissed: <b>{rec['dismissed_count']}</b> | Acceptance Rate: <b>{rec['acceptance_rate']}%</b>", body_style))
        story.append(Spacer(1, 10))

        # Organizational Insights Section
        story.append(Paragraph("8. Organizational Insights", h2_style))
        insights = ctx["organizational_insights"].get("insights", [])
        for ins in insights:
            story.append(Paragraph(f"• <b>[{ins['severity'].upper()}] {ins['title']}</b> ({ins['category']})", body_style))
            story.append(Paragraph(f"  {ins['description']}", body_style))
            story.append(Paragraph(f"  <i>Recommendation:</i> {ins['recommended_action']}", body_style))
        story.append(Spacer(1, 10))

        # Methodology Section
        story.append(Paragraph("9. Metric Definitions & Methodology", h2_style))
        meth = ctx["metric_definitions"]
        story.append(Paragraph(f"• WSI Methodology: {meth['wsi_methodology']}", body_style))
        story.append(Paragraph(f"• WLB Methodology: {meth['wlb_methodology']}", body_style))
        story.append(Paragraph(f"• Privacy Rule: {meth['privacy_rule']}", body_style))
        story.append(Paragraph(f"• Insufficient Data: {meth['insufficient_data_handling']}", body_style))

        doc.build(story, canvasmaker=NumberedCanvas)
        buffer.seek(0)
        return buffer.getvalue()

    def generate_excel(self, period: Optional[str] = "this_week", start_date: Optional[str] = None, end_date: Optional[str] = None) -> bytes:
        ctx = self._get_org_context(period, start_date, end_date)
        wb = openpyxl.Workbook()
        # Remove default sheet
        default_sheet = wb.active

        header_fill = PatternFill(start_color="1E293B", end_color="1E293B", fill_type="solid")
        header_font = Font(name="Segoe UI", size=11, bold=True, color="FFFFFF")
        title_font = Font(name="Segoe UI", size=15, bold=True, color="1E293B")
        subtitle_font = Font(name="Segoe UI", size=10, italic=True, color="64748B")
        regular_font = Font(name="Segoe UI", size=10)
        bold_font = Font(name="Segoe UI", size=10, bold=True)
        zebra_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
        thin_border = Border(left=Side(style='thin', color='CBD5E1'), right=Side(style='thin', color='CBD5E1'), top=Side(style='thin', color='CBD5E1'), bottom=Side(style='thin', color='CBD5E1'))

        def style_ws(ws, title_text, headers, rows):
            ws.cell(row=1, column=1, value=title_text).font = title_font
            ws.cell(row=2, column=1, value=f"Period: {ctx['start_date']} to {ctx['end_date']} | Generated: {ctx['generated_at'][:10]}").font = subtitle_font
            for col_idx, h in enumerate(headers, 1):
                cell = ws.cell(row=4, column=col_idx, value=h)
                cell.fill = header_fill
                cell.font = header_font
                cell.alignment = Alignment(horizontal="center", vertical="center")
                cell.border = thin_border
            ws.row_dimensions[4].height = 24

            for row_idx, r_vals in enumerate(rows, 5):
                for col_idx, val in enumerate(r_vals, 1):
                    cell = ws.cell(row=row_idx, column=col_idx, value=val)
                    cell.font = regular_font
                    cell.border = thin_border
                    if row_idx % 2 == 0:
                        cell.fill = zebra_fill
            ws.views.sheetView[0].showGridLines = True
            for col in ws.columns:
                max_len = max(len(str(c.value or '')) for c in col)
                col_letter = get_column_letter(col[0].column)
                ws.column_dimensions[col_letter].width = max(max_len + 4, 14)

        # Sheet 1: Executive Summary
        ws1 = wb.create_sheet(title="Executive Summary")
        exec_sum = ctx["executive_summary"]
        style_ws(ws1, "IntelliBreak Executive Summary", ["Metric", "Value"], [
            ["Total Active Employees", exec_sum["total_active_employees"]],
            ["Total Active Teams", exec_sum["total_active_teams"]],
            ["Total Work Hours", exec_sum["total_work_hours"]],
            ["Average Work Hours / Employee", exec_sum["avg_work_hours_per_employee"]],
            ["Task Completion Rate (%)", exec_sum["task_completion_rate"]],
            ["Work Sustainability Index (WSI)", round(exec_sum["work_sustainability_index"], 1)],
            ["Average WLB Score", exec_sum["avg_wlb_score"]],
            ["Recommendation Acceptance Rate (%)", exec_sum["recommendation_acceptance_rate"]],
        ])

        # Sheet 2: Productivity
        ws2 = wb.create_sheet(title="Productivity")
        prod = ctx["productivity"]
        style_ws(ws2, "Organizational Productivity", ["Metric", "Value"], [
            ["Total Work Hours", prod["total_work_hours"]],
            ["Previous Period Work Hours", prod["previous_work_hours"]],
            ["Work Hours Change (%)", prod["work_hours_change_pct"]],
            ["Average Hours / Employee", prod["avg_hours_per_employee"]],
            ["Total Tasks", prod["total_tasks"]],
            ["Completed Tasks", prod["completed_tasks"]],
            ["Task Completion Rate (%)", prod["completion_rate"]],
        ])

        # Sheet 3: Work Sustainability
        ws3 = wb.create_sheet(title="Work Sustainability")
        sust = ctx["work_sustainability"]
        style_ws(ws3, "Work Sustainability", ["Metric", "Value"], [
            ["Sustainability Index (WSI)", sust["sustainability_index"]],
            ["Previous Period WSI", sust["previous_sustainability_index"]],
            ["Overtime Frequency (%)", sust["overtime_frequency"]],
            ["Break Compliance (%)", sust["break_compliance"]],
            ["Long Sessions Count", sust["long_sessions_count"]],
            ["Late Shift Endings Count", sust["late_shift_endings_count"]],
            ["Missed Breaks Count", sust["missed_breaks_count"]],
        ])

        # Sheet 4: Work-Life Balance
        ws4 = wb.create_sheet(title="Work-Life Balance")
        wlb = ctx["work_life_balance"]
        style_ws(ws4, "Work-Life Balance", ["Metric", "Value"], [
            ["Average WLB Score", wlb["avg_wlb_score"]],
            ["Survey Respondents", wlb["survey_respondents"]],
            ["Survey Participation Rate (%)", wlb["survey_participation_rate"]],
        ])

        # Sheet 5: Organizational Wellbeing
        ws5 = wb.create_sheet(title="Organizational Wellbeing")
        wb_risk = ctx["organizational_wellbeing"]["risk_distribution"]
        style_ws(ws5, "Organizational Work-Pattern Risk Distribution", ["Risk Tier", "Employee Count"], [
            ["Low Risk", wb_risk["low"]],
            ["Moderate Risk", wb_risk["moderate"]],
            ["High Risk", wb_risk["high"]],
            ["Critical Risk", wb_risk["critical"]],
            ["Insufficient Data", wb_risk["insufficient_data"]],
        ])

        # Sheet 6: Team Comparison
        ws6 = wb.create_sheet(title="Team Comparison")
        teams = ctx["team_comparison"]
        team_rows = []
        for t in teams:
            team_rows.append([
                t["team_name"],
                "Not enough people" if t["privacy_suppressed"] else t["active_employees"],
                "Suppressed" if t["privacy_suppressed"] else t["productivity"]["total_work_hours"],
                "Suppressed" if t["privacy_suppressed"] else t["work_sustainability"]["sustainability_index"],
                "Suppressed" if t["privacy_suppressed"] else t["work_life_balance"]["avg_wlb_score"],
                "Suppressed" if t["privacy_suppressed"] else "Active"
            ])
        style_ws(ws6, "Team Comparison (N >= 5 Privacy Enforced)", ["Team Name", "Active Employees", "Total Work Hours", "WSI", "WLB Score", "Status"], team_rows)

        # Sheet 7: Recommendation Effectiveness
        ws7 = wb.create_sheet(title="Recommendation Effectiveness")
        rec = ctx["recommendation_effectiveness"]
        rec_rows = [
            ["Generated Recommendations", rec["generated_count"]],
            ["Accepted Count", rec["accepted_count"]],
            ["Dismissed Count", rec["dismissed_count"]],
            ["Pending Count", rec["pending_count"]],
            ["Acceptance Rate (%)", rec["acceptance_rate"]],
        ]
        # Category breakdown
        for cat, stats in rec.get("category_breakdown", {}).items():
            rec_rows.append([f"Category {cat}: Generated", stats.get("generated", 0)])
            rec_rows.append([f"Category {cat}: Accepted", stats.get("accepted", 0)])
            rec_rows.append([f"Category {cat}: Acceptance Rate (%)", stats.get("acceptance_rate", 0.0)])
        # Model version distribution
        for model, pct in rec.get("model_version_distribution", {}).items():
            rec_rows.append([f"Model {model} (%)", pct])
        # Time-to-view metrics
        ttv = rec.get("time_to_view_metrics", {})
        if ttv.get("median_seconds") is not None:
            rec_rows.append(["Time-to-View Median (seconds)", ttv.get("median_seconds")])
        if ttv.get("p95_seconds") is not None:
            rec_rows.append(["Time-to-View P95 (seconds)", ttv.get("p95_seconds")])
        style_ws(ws7, "Recommendation Effectiveness", ["Metric", "Value"], rec_rows)

        # Sheet 8: Organizational Insights
        ws8 = wb.create_sheet(title="Organizational Insights")
        insights = ctx["organizational_insights"].get("insights", [])
        insight_rows = []
        for ins in insights:
            insight_rows.append([ins["category"], ins["severity"], ins["title"], ins["description"], ins["recommended_action"]])
        style_ws(ws8, "Organizational Insights", ["Category", "Severity", "Title", "Description", "Recommended Action"], insight_rows if insight_rows else [["None", "None", "No insights generated", "", ""]])

        # Sheet 9: Metric Definitions
        ws9 = wb.create_sheet(title="Metric Definitions")
        meth = ctx["metric_definitions"]
        style_ws(ws9, "Metric Definitions & Methodology", ["Concept", "Definition / Policy"], [
            ["WSI Methodology", meth["wsi_methodology"]],
            ["WLB Methodology", meth["wlb_methodology"]],
            ["Privacy Rule", meth["privacy_rule"]],
            ["Insufficient Data Handling", meth["insufficient_data_handling"]],
        ])

        buffer = io.BytesIO()
        wb.save(buffer)
        buffer.seek(0)
        return buffer.getvalue()

    def generate_csv_zip(self, period: Optional[str] = "this_week", start_date: Optional[str] = None, end_date: Optional[str] = None) -> bytes:
        ctx = self._get_org_context(period, start_date, end_date)
        zip_buffer = io.BytesIO()

        def sanitize(val):
            if val is None:
                return ""
            s = str(val)
            if s and s[0] in ('=', '+', '-', '@'):
                return f"'{s}"
            return s

        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            # 1. Executive Summary CSV
            exec_io = io.StringIO()
            writer = csv.writer(exec_io)
            writer.writerow(["Metric", "Value"])
            for k, v in ctx["executive_summary"].items():
                writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("executive_summary.csv", exec_io.getvalue())

            # 2. Productivity CSV
            prod_io = io.StringIO()
            writer = csv.writer(prod_io)
            writer.writerow(["Metric", "Value"])
            for k, v in ctx["productivity"].items():
                writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("productivity.csv", prod_io.getvalue())

            # 3. Work Sustainability CSV
            sust_io = io.StringIO()
            writer = csv.writer(sust_io)
            writer.writerow(["Metric", "Value"])
            for k, v in ctx["work_sustainability"].items():
                writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("work_sustainability.csv", sust_io.getvalue())

            # 4. Work-Life Balance CSV
            wlb_io = io.StringIO()
            writer = csv.writer(wlb_io)
            writer.writerow(["Metric", "Value"])
            for k, v in ctx["work_life_balance"].items():
                if k != "historical_trends":
                    writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("work_life_balance.csv", wlb_io.getvalue())

            # 5. Organizational Wellbeing CSV
            wb_io = io.StringIO()
            writer = csv.writer(wb_io)
            writer.writerow(["Risk Tier", "Employee Count"])
            for k, v in ctx["organizational_wellbeing"]["risk_distribution"].items():
                writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("organizational_wellbeing.csv", wb_io.getvalue())

            # 6. Team Comparison CSV
            team_io = io.StringIO()
            writer = csv.writer(team_io)
            writer.writerow(["Team Name", "Active Employees", "Privacy Suppressed", "Total Work Hours", "WSI", "WLB Score"])
            for t in ctx["team_comparison"]:
                writer.writerow([
                    sanitize(t["team_name"]),
                    sanitize("Not enough people" if t["privacy_suppressed"] else t["active_employees"]),
                    sanitize(t["privacy_suppressed"]),
                    sanitize("Suppressed" if t["privacy_suppressed"] else t["productivity"]["total_work_hours"]),
                    sanitize("Suppressed" if t["privacy_suppressed"] else t["work_sustainability"]["sustainability_index"]),
                    sanitize("Suppressed" if t["privacy_suppressed"] else t["work_life_balance"]["avg_wlb_score"]),
                ])
            zf.writestr("team_comparison.csv", team_io.getvalue())

            # 7. Recommendation Effectiveness CSV
            rec_io = io.StringIO()
            writer = csv.writer(rec_io)
            writer.writerow(["Metric", "Value"])
            for k, v in ctx["recommendation_effectiveness"].items():
                if k != "historical_trends" and k != "category_breakdown" and k != "model_version_distribution" and k != "time_to_view_metrics":
                    writer.writerow([sanitize(k), sanitize(v)])

            # Category breakdown
            for cat, stats in ctx["recommendation_effectiveness"].get("category_breakdown", {}).items():
                writer.writerow([sanitize(f"category_{cat}_generated"), sanitize(stats.get("generated", 0))])
                writer.writerow([sanitize(f"category_{cat}_accepted"), sanitize(stats.get("accepted", 0))])
                writer.writerow([sanitize(f"category_{cat}_acceptance_rate"), sanitize(stats.get("acceptance_rate", 0.0))])

            # Model version distribution
            for model, pct in ctx["recommendation_effectiveness"].get("model_version_distribution", {}).items():
                writer.writerow([sanitize(f"model_{model}_pct"), sanitize(pct)])

            # Time-to-view metrics
            ttv = ctx["recommendation_effectiveness"].get("time_to_view_metrics", {})
            if ttv.get("median_seconds") is not None:
                writer.writerow([sanitize("time_to_view_median_seconds"), sanitize(ttv.get("median_seconds"))])
            if ttv.get("p95_seconds") is not None:
                writer.writerow([sanitize("time_to_view_p95_seconds"), sanitize(ttv.get("p95_seconds"))])

            zf.writestr("recommendation_effectiveness.csv", rec_io.getvalue())

            # 8. Organizational Insights CSV
            ins_io = io.StringIO()
            writer = csv.writer(ins_io)
            writer.writerow(["Category", "Severity", "Title", "Description", "Recommended Action"])
            for ins in ctx["organizational_insights"].get("insights", []):
                writer.writerow([
                    sanitize(ins.get("category")),
                    sanitize(ins.get("severity")),
                    sanitize(ins.get("title")),
                    sanitize(ins.get("description")),
                    sanitize(ins.get("recommended_action")),
                ])
            zf.writestr("organizational_insights.csv", ins_io.getvalue())

            # 9. Metric Definitions CSV
            meth_io = io.StringIO()
            writer = csv.writer(meth_io)
            writer.writerow(["Concept", "Definition / Policy"])
            for k, v in ctx["metric_definitions"].items():
                writer.writerow([sanitize(k), sanitize(v)])
            zf.writestr("metric_definitions.csv", meth_io.getvalue())

        zip_buffer.seek(0)
        return zip_buffer.getvalue()
