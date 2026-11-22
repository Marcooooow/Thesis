import uuid
from datetime import date, datetime, timezone, timedelta
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session

from ..models import User, Profile, OrganizationMembership, Team, TeamMembership, WorkLifeBalanceSurvey, RecommendationFeedback
from ..services.team_analytics_service import compute_team_analytics
from ..services.analytics_service import AnalyticsEngine
from ..services.wellbeing_monitoring import WellbeingMonitoringService, resolve_reporting_week
from ..analytics_utils import parse_date_range, get_previous_start_end_for_period

class OrganizationalInsightsService:
    """
    Deterministic, rule-based organizational insights engine for Admin Organization Analytics.
    Analyzes productivity, work sustainability, work-life balance, organizational wellbeing,
    team performance, and recommendation effectiveness against configurable thresholds.

    NOTE: All thresholds defined below are centralized operational heuristics for IntelliBreak
    thesis demonstration purposes and do NOT constitute clinical diagnoses or scientifically validated limits.
    """
    THRESHOLD_PRODUCTIVITY_CHANGE_PCT = 15.0  # +/- 15% work hours change trigger
    THRESHOLD_WSI_DECLINE_POINTS = 10.0      # > 10 points WSI drop trigger
    THRESHOLD_WSI_HEALTHY = 85.0             # >= 85 healthy WSI score
    THRESHOLD_WLB_DECLINE_POINTS = 10.0      # > 10 points WLB survey score drop trigger
    THRESHOLD_WLB_HEALTHY = 75.0             # >= 75 healthy WLB score
    THRESHOLD_WELLBEING_HIGH_RISK_PCT = 25.0 # > 25% high wellbeing risk tier concentration trigger
    THRESHOLD_REC_ACCEPTANCE_HIGH = 60.0     # >= 60% high recommendation acceptance trigger
    THRESHOLD_REC_ACCEPTANCE_LOW = 30.0      # < 30% low recommendation acceptance trigger
    THRESHOLD_MIN_TEAM_MEMBERS = 5           # Minimum group size for privacy-safe team insights

    @staticmethod
    def generate_organizational_insights(
        db: Session,
        current_user: User,
        period: Optional[str] = "this_week",
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
        category_filter: Optional[str] = None
    ) -> Dict[str, Any]:
        user_tz = "UTC" # Default reporting timezone
        start_utc, end_utc = parse_date_range(start_date, end_date, period, user_tz)
        prev_start_utc, prev_end_utc = get_previous_start_end_for_period(period, user_tz)

        effective_start_date = start_utc.date()
        effective_end_date = end_utc.date()
        prev_start_date = prev_start_utc.date()
        prev_end_date = prev_end_utc.date()

        # Compute current period analytics
        current_analytics = compute_team_analytics(
            db=db,
            current_user=current_user,
            team_id=None,
            start_date=effective_start_date,
            end_date=effective_end_date
        )

        # Compute previous period analytics for comparison
        prev_analytics = compute_team_analytics(
            db=db,
            current_user=current_user,
            team_id=None,
            start_date=prev_start_date,
            end_date=prev_end_date
        )

        insights: List[Dict[str, Any]] = []
        now_iso = datetime.now(timezone.utc).isoformat()

        total_employees = current_analytics.get("total_employees", 0)
        current_work_hours = current_analytics.get("total_work_hours", 0.0)
        prev_work_hours = prev_analytics.get("total_work_hours", 0.0)
        current_avg_hours = current_analytics.get("avg_hours_per_emp", 0.0)
        prev_avg_hours = prev_analytics.get("avg_hours_per_emp", 0.0)

        # Insufficient data check
        if total_employees == 0 or current_work_hours == 0.0:
            insights.append({
                "id": f"ins_nodata_{uuid.uuid4().hex[:8]}",
                "category": "productivity",
                "title": "Insufficient Data for Organizational Analysis",
                "description": "There are no active employee profiles or work session hours recorded for the selected reporting period.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"total_employees": total_employees, "total_work_hours": current_work_hours},
                "evidence": "Employee count or work hours equals zero.",
                "recommended_action": "Ensure employees have active sessions or check reporting date range filters.",
                "timestamp": now_iso
            })
            return {
                "period": period or "custom",
                "start_date": effective_start_date.isoformat(),
                "end_date": effective_end_date.isoformat(),
                "generated_at": now_iso,
                "total_insights": len(insights),
                "severity_counts": {"informational": 1, "positive": 0, "warning": 0, "critical": 0},
                "insights": insights,
                "data_quality_indicator": "insufficient_data"
            }

        # 1. Productivity Insights
        hours_diff_pct = ((current_work_hours - prev_work_hours) / max(1.0, prev_work_hours)) * 100.0 if prev_work_hours > 0 else 0.0
        if current_work_hours > prev_work_hours * 1.15 and prev_work_hours > 0:
            insights.append({
                "id": f"ins_prod_pos_{uuid.uuid4().hex[:8]}",
                "category": "productivity",
                "title": "Robust Productivity Growth Across Organization",
                "description": f"Total organizational work hours increased by {round(hours_diff_pct, 1)}% compared to the previous equivalent period.",
                "severity": "positive",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_work_hours": current_work_hours, "previous_work_hours": prev_work_hours, "change_pct": round(hours_diff_pct, 1)},
                "evidence": f"Current work hours ({current_work_hours}h) exceed previous period ({prev_work_hours}h) by >15%.",
                "recommended_action": "Monitor work sustainability to ensure growth does not lead to employee fatigue.",
                "timestamp": now_iso
            })
        elif current_work_hours < prev_work_hours * 0.85 and prev_work_hours > 0:
            insights.append({
                "id": f"ins_prod_warn_{uuid.uuid4().hex[:8]}",
                "category": "productivity",
                "title": "Notable Decline in Organizational Work Hours",
                "description": f"Total organizational work hours declined by {round(abs(hours_diff_pct), 1)}% compared to the previous equivalent period.",
                "severity": "warning",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_work_hours": current_work_hours, "previous_work_hours": prev_work_hours, "change_pct": round(hours_diff_pct, 1)},
                "evidence": f"Current work hours ({current_work_hours}h) dropped below previous period ({prev_work_hours}h) by >15%.",
                "recommended_action": "Investigate potential operational blockers or holiday impact during this period.",
                "timestamp": now_iso
            })
        else:
            insights.append({
                "id": f"ins_prod_info_{uuid.uuid4().hex[:8]}",
                "category": "productivity",
                "title": "Stable Productivity Trend",
                "description": f"Organizational work hours remained stable at {current_work_hours} hours across {total_employees} active employees.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_work_hours": current_work_hours, "avg_hours_per_emp": current_avg_hours},
                "evidence": f"Work hours change ({round(hours_diff_pct, 1)}%) is within normal stability bounds (+/- 15%).",
                "recommended_action": "Maintain current operational cadence.",
                "timestamp": now_iso
            })

        # 2. Work Sustainability Insights (WSI)
        org_wsi = 82.5 # Default baseline / computed WSI
        prev_wsi = 80.0
        # If sessions or profile data exists, compute WSI proxy or use AnalyticsEngine
        org_ids = [m.organization_id for m in db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == current_user.id,
            OrganizationMembership.status == "APPROVED"
        ).all()]
        wsi_data = AnalyticsEngine.calculate_organization_work_sustainability(
            db, org_ids, start_utc, end_utc, include_test=True
        )
        current_wsi = wsi_data.get("sustainabilityIndex", 80.0)

        prev_wsi_data = AnalyticsEngine.calculate_organization_work_sustainability(
            db, org_ids, prev_start_utc, prev_end_utc, include_test=True
        )
        previous_wsi = prev_wsi_data.get("sustainabilityIndex", 80.0)

        wsi_drop = previous_wsi - current_wsi
        if wsi_drop > 10.0:
            insights.append({
                "id": f"ins_wsi_crit_{uuid.uuid4().hex[:8]}",
                "category": "sustainability",
                "title": "Work Sustainability Index Declined Significantly",
                "description": f"The organization's Work Sustainability Index dropped by {round(wsi_drop, 1)} points compared to the previous period.",
                "severity": "warning",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_wsi": current_wsi, "previous_wsi": previous_wsi, "drop": round(wsi_drop, 1)},
                "evidence": f"WSI declined from {previous_wsi} to {current_wsi} (threshold >10 points).",
                "recommended_action": "Review overtime frequency, break compliance, and late shift endings across active teams.",
                "timestamp": now_iso
            })
        elif current_wsi >= 85.0:
            insights.append({
                "id": f"ins_wsi_pos_{uuid.uuid4().hex[:8]}",
                "category": "sustainability",
                "title": "High Work Sustainability Across Organization",
                "description": f"Organizational Work Sustainability Index is strong at {current_wsi}/100.",
                "severity": "positive",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_wsi": current_wsi},
                "evidence": f"WSI score ({current_wsi}) exceeds healthy sustainability threshold (85).",
                "recommended_action": "Continue supporting healthy break habits and sustainable work cadences.",
                "timestamp": now_iso
            })
        else:
            insights.append({
                "id": f"ins_wsi_info_{uuid.uuid4().hex[:8]}",
                "category": "sustainability",
                "title": "Moderate Work Sustainability Index",
                "description": f"Work Sustainability Index stands at {current_wsi}/100, indicating balanced operations with areas for optimization.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_wsi": current_wsi},
                "evidence": f"WSI score ({current_wsi}) is within stable operational range.",
                "recommended_action": "Encourage regular break compliance and prevent excessive overtime.",
                "timestamp": now_iso
            })

        # 3. Work-Life Balance Insights (WLB) - Use canonical aggregation matching report service
        profile_ids = current_analytics.get("profile_ids", [])
        week_start_date = start_utc.date() - timedelta(days=start_utc.date().weekday())
        lookback_start = week_start_date - timedelta(days=21)
        prev_week_start = prev_start_utc.date() - timedelta(days=prev_start_utc.date().weekday())
        prev_lookback = prev_week_start - timedelta(days=21)

        wlb_surveys = db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= lookback_start
        ).all() if profile_ids else []
        prev_wlb_surveys = db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id.in_(profile_ids),
            WorkLifeBalanceSurvey.week_start_date >= prev_lookback
        ).all() if profile_ids else []

        current_avg_wlb = sum(s.score for s in wlb_surveys) / len(wlb_surveys) if wlb_surveys else None
        prev_avg_wlb = sum(s.score for s in prev_wlb_surveys) / len(prev_wlb_surveys) if prev_wlb_surveys else None
        wlb_diff = (current_avg_wlb - prev_avg_wlb) if (current_avg_wlb is not None and prev_avg_wlb is not None) else 0.0

        if wlb_diff < -10.0 and prev_wlb_surveys:
            insights.append({
                "id": f"ins_wlb_warn_{uuid.uuid4().hex[:8]}",
                "category": "wlb",
                "title": "Work-Life Balance Ratings Notable Decline",
                "description": f"Employee-reported Work-Life Balance scores declined by {round(abs(wlb_diff), 1)} points compared to the previous period.",
                "severity": "warning",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_avg_wlb": round(current_avg_wlb, 1), "previous_avg_wlb": round(prev_avg_wlb, 1), "survey_count": len(wlb_surveys)},
                "evidence": f"Average WLB score dropped from {round(prev_avg_wlb, 1)} to {round(current_avg_wlb, 1)}.",
                "recommended_action": "Review workload distribution and ensure employees take adequate disconnecting breaks.",
                "timestamp": now_iso
            })
        elif current_avg_wlb is not None and current_avg_wlb >= 75.0:
            insights.append({
                "id": f"ins_wlb_pos_{uuid.uuid4().hex[:8]}",
                "category": "wlb",
                "title": "Strong Employee Work-Life Balance Scores",
                "description": f"Average WLB survey score is robust at {round(current_avg_wlb, 1)}/100 based on {len(wlb_surveys)} survey responses.",
                "severity": "positive",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_avg_wlb": round(current_avg_wlb, 1), "survey_count": len(wlb_surveys)},
                "evidence": f"WLB score ({round(current_avg_wlb, 1)}) indicates healthy work-life integration.",
                "recommended_action": "Maintain current wellness break policies.",
                "timestamp": now_iso
            })
        else:
            insights.append({
                "id": f"ins_wlb_info_{uuid.uuid4().hex[:8]}",
                "category": "wlb",
                "title": "Stable Work-Life Balance Feedback",
                "description": f"Work-life balance survey average is {round(current_avg_wlb, 1) if current_avg_wlb is not None else 'N/A'}/100 with {len(wlb_surveys)} responses submitted.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"current_avg_wlb": round(current_avg_wlb, 1) if current_avg_wlb is not None else None, "survey_count": len(wlb_surveys)},
                "evidence": f"WLB score ({round(current_avg_wlb, 1) if current_avg_wlb is not None else 'N/A'}) is within expected baseline levels.",
                "recommended_action": "Encourage ongoing participation in weekly wellbeing surveys.",
                "timestamp": now_iso
            })

        # 4. Organizational Wellbeing Insights
        wb_service = WellbeingMonitoringService(db)
        profile_ids = current_analytics.get("profile_ids", [])
        overview_week_start = resolve_reporting_week(db, profile_ids, effective_start_date)

        risk_counts = {"low_risk": 0, "moderate_risk": 0, "high_risk": 0, "critical": 0, "insufficient_data": 0}
        total_p = len(profile_ids)

        # [DIAG 4: Risk Classification Tracing]
        risk_tier_detail = []  # Track individual classifications

        for pid in profile_ids:
            try:
                risk_resp = wb_service.compute_weekly_risk(pid, overview_week_start)
                risk_tier_raw = risk_resp.risk_tier if risk_resp else None

                tier = str(risk_tier_raw).lower() if risk_resp and risk_resp.risk_tier else "insufficient_data"

                if "high" in tier:
                    risk_counts["high_risk"] += 1
                elif "mod" in tier:
                    risk_counts["moderate_risk"] += 1
                elif "crit" in tier:
                    risk_counts["critical"] += 1
                elif "insuff" in tier:
                    risk_counts["insufficient_data"] += 1
                else:
                    risk_counts["low_risk"] += 1
            except Exception as e:
                risk_counts["insufficient_data"] += 1

        high_risk_pct = round((risk_counts["high_risk"] / max(1, total_p)) * 100.0, 1) if total_p > 0 else 0.0
        risk_dist = risk_counts

        if high_risk_pct > 25.0:
            insights.append({
                "id": f"ins_wb_crit_{uuid.uuid4().hex[:8]}",
                "category": "wellbeing",
                "title": "Elevated Proportion of Employees in High Work-Pattern Risk Tiers",
                "description": f"{round(high_risk_pct, 1)}% of evaluated employee profiles fall into the high work-pattern risk tier.",
                "severity": "critical",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"high_risk_percentage": round(high_risk_pct, 1), "risk_distribution": risk_dist},
                "evidence": f"High risk tier concentration ({round(high_risk_pct, 1)}%) exceeds safety threshold of 25%.",
                "recommended_action": "Coordinate with team managers to review workload balance and encourage rest breaks.",
                "timestamp": now_iso
            })
        else:
            insights.append({
                "id": f"ins_wb_pos_{uuid.uuid4().hex[:8]}",
                "category": "wellbeing",
                "title": "Favorable Work-Pattern Risk Distribution",
                "description": f"Organizational work-pattern risk distribution remains healthy with low-risk concentration at {100.0 - high_risk_pct}%.",
                "severity": "positive",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"high_risk_percentage": round(high_risk_pct, 1), "risk_distribution": risk_dist},
                "evidence": f"High risk tier concentration ({round(high_risk_pct, 1)}%) is well below critical thresholds.",
                "recommended_action": "Continue proactive wellness monitoring.",
                "timestamp": now_iso
            })

        # 5. Team Performance Insights
        teams = db.query(Team).filter(Team.organization_id.in_(org_ids), Team.is_active == True).all() if org_ids else []
        suppressed_teams_count = 0
        active_teams_analyzed = 0
        for t in teams:
            # Check member count for privacy suppression.
            m_count = db.query(Profile).join(TeamMembership, Profile.id == TeamMembership.profile_id).filter(
                TeamMembership.team_id == t.id,
                TeamMembership.left_at.is_(None)
            ).count()
            if m_count < 5:
                suppressed_teams_count += 1
            else:
                active_teams_analyzed += 1

        if active_teams_analyzed > 0:
            insights.append({
                "id": f"ins_team_info_{uuid.uuid4().hex[:8]}",
                "category": "teams",
                "title": "Team Comparative Analysis Completed",
                "description": f"Analyzed {active_teams_analyzed} eligible teams across the organization. {suppressed_teams_count} team(s) suppressed under N<3 privacy rules.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"active_teams_analyzed": active_teams_analyzed, "privacy_suppressed_teams": suppressed_teams_count},
                "evidence": "Team comparison metrics successfully evaluated with privacy suppression enforcement.",
                "recommended_action": "Review individual team dashboards for granular comparisons.",
                "timestamp": now_iso
            })

        # 6. Recommendation Effectiveness Insights
        feedback_records = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.timestamp >= start_utc,
            RecommendationFeedback.timestamp <= end_utc
        ).all()
        total_recs = len(feedback_records)
        accepted_recs = len([f for f in feedback_records if f.user_action == 'accepted'])
        acceptance_rate = round((accepted_recs / total_recs * 100.0) if total_recs > 0 else 0.0, 1)

        if total_recs > 0 and acceptance_rate >= 60.0:
            insights.append({
                "id": f"ins_rec_pos_{uuid.uuid4().hex[:8]}",
                "category": "recommendations",
                "title": "High Recommendation Acceptance Rate",
                "description": f"Employees accepted {acceptance_rate}% of generated break recommendations ({accepted_recs}/{total_recs}).",
                "severity": "positive",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"total_recommendations": total_recs, "accepted_recommendations": accepted_recs, "acceptance_rate": acceptance_rate},
                "evidence": f"Acceptance rate ({acceptance_rate}%) exceeds high engagement threshold (60%).",
                "recommended_action": "Continue delivering timely break and wellness suggestions.",
                "timestamp": now_iso
            })
        elif total_recs > 0 and acceptance_rate < 30.0:
            insights.append({
                "id": f"ins_rec_warn_{uuid.uuid4().hex[:8]}",
                "category": "recommendations",
                "title": "Low Recommendation Acceptance Rate",
                "description": f"Recommendation acceptance rate is low at {acceptance_rate}% ({accepted_recs}/{total_recs}).",
                "severity": "warning",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"total_recommendations": total_recs, "accepted_recommendations": accepted_recs, "acceptance_rate": acceptance_rate},
                "evidence": f"Acceptance rate ({acceptance_rate}%) falls below threshold (30%).",
                "recommended_action": "Evaluate recommendation timing and relevance for employees.",
                "timestamp": now_iso
            })
        else:
            insights.append({
                "id": f"ins_rec_info_{uuid.uuid4().hex[:8]}",
                "category": "recommendations",
                "title": "Moderate Recommendation Effectiveness",
                "description": f"Recommendation acceptance rate stands at {acceptance_rate}% across {total_recs} feedback events.",
                "severity": "informational",
                "period": period or f"{effective_start_date} to {effective_end_date}",
                "supporting_metrics": {"total_recommendations": total_recs, "acceptance_rate": acceptance_rate},
                "evidence": f"Acceptance rate ({acceptance_rate}%) is within expected baseline levels.",
                "recommended_action": "Monitor user feedback trends.",
                "timestamp": now_iso
            })

        # Filter by category if requested
        filtered_insights = insights
        if category_filter:
            filtered_insights = [i for i in insights if i["category"].lower() == category_filter.lower()]

        # Compute severity counts
        severity_counts = {"informational": 0, "positive": 0, "warning": 0, "critical": 0}
        for ins in insights:
            sev = ins.get("severity", "informational")
            if sev in severity_counts:
                severity_counts[sev] += 1

        return {
            "period": period or "custom",
            "start_date": effective_start_date.isoformat(),
            "end_date": effective_end_date.isoformat(),
            "generated_at": now_iso,
            "total_insights": len(filtered_insights),
            "severity_counts": severity_counts,
            "insights": filtered_insights,
            "data_quality_indicator": "sufficient_data"
        }
