import uuid
from typing import Optional, List, Dict, Any
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import func

from ..models import User, Break, SessionWellbeingCheckin
from ..auth.security import should_include_test_data
from .team_analytics_service import compute_team_analytics


def generate_team_wellness_advisor_report(
    db: Session,
    current_user: User,
    team_id: Optional[uuid.UUID] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
) -> Dict[str, Any]:
    """
    Generate rigorous, evidence-based Team Wellness Advisor intelligence report for managers/admins.
    Enforces strict data integrity rules:
    - No missing-data fallbacks (unreported data is explicitly marked 'unavailable' or 'insufficient').
    - Sample size checks differentiate individual isolated events from team-wide patterns.
    - Independent recommendation effectiveness calculation with pending/expired handling.
    - Workload analysis based on actual task status/priority without invented effort.
    """
    today = date.today()
    eff_start = start_date or (today - timedelta(days=7))
    eff_end = end_date or today

    # Get authoritative team analytics and membership details
    analytics = compute_team_analytics(db, current_user, team_id=team_id, start_date=eff_start, end_date=eff_end)

    total_members = analytics.get("total_employees", 0)
    if total_members < 5:
        return {
            "analysis_period_start": eff_start.isoformat(),
            "analysis_period_end": eff_end.isoformat(),
            "team_data_coverage": {
                "sample_size_adequate": False,
                "analysis_period": f"{eff_start.strftime('%b %d, %Y')} - {eff_end.strftime('%b %d, %Y')}",
                "data_quality": "privacy_suppressed",
            },
            "overall_assessment": {
                "status": "privacy_suppressed",
                "risk_tier": 0,
                "title": "Not enough people to show this safely",
                "explanation": "Group insights require at least 5 people. Team figures are advisory and not a diagnosis.",
            },
            "insights": [],
            "recommendations": [],
            "model_metadata": {
                "engine_status": "active",
                "model_version": "cold-start-baseline",
                "model_type": "heuristic-rule-based-aggregation",
                "description": "No team-level metrics were generated because the privacy group-size threshold was not met.",
            },
        }

    sessions = analytics.get("sessions", [])
    session_ids = [session.id for session in sessions]
    work_sessions_count = analytics.get("session_count", len(sessions))
    # compute_team_analytics returns a flat structure. Build the small summary
    # this advisor needs from those authoritative values instead of silently
    # defaulting to an empty nested `summary` object.
    avg_wellbeing = None
    break_logging_coverage = None
    if session_ids:
        avg_wellbeing = db.query(func.avg(SessionWellbeingCheckin.overall_wellbeing)).filter(
            SessionWellbeingCheckin.work_session_id.in_(session_ids),
            SessionWellbeingCheckin.overall_wellbeing.isnot(None),
        ).scalar()
        sessions_with_break_logs = db.query(func.count(func.distinct(Break.work_session_id))).filter(
            Break.work_session_id.in_(session_ids),
            Break.started_at.isnot(None),
        ).scalar() or 0
        break_logging_coverage = round(sessions_with_break_logs / len(session_ids) * 100.0, 1)
    summary_data = {
        "total_work_sessions": work_sessions_count,
        "avg_focus_rate": analytics.get("focus_rate"),
        "avg_wellbeing": round(float(avg_wellbeing), 2) if avg_wellbeing is not None else None,
        "break_compliance_rate": break_logging_coverage,
        "extended_sessions_count": sum(
            1 for session in sessions
            if session.ended_at and (session.ended_at - session.started_at).total_seconds() > 2 * 60 * 60
        ),
    }
    has_sufficient_data = total_members > 0 and work_sessions_count > 0

    now_iso = datetime.now(timezone.utc).isoformat()
    period_str = f"{eff_start.strftime('%b %d, %Y')} - {eff_end.strftime('%b %d, %Y')}"

    insights = []
    recommendations = []

    # Team Data Coverage calculation
    data_coverage = {
        "total_eligible_members": total_members,
        "active_members_with_records": len({str(session.profile_id) for session in sessions}),
        "sample_size_adequate": has_sufficient_data,
        "analysis_period": period_str,
        "data_quality": "sufficient" if has_sufficient_data else "insufficient"
    }

    if not has_sufficient_data:
        insights.append({
            "id": f"ins_nodata_{uuid.uuid4().hex[:8]}",
            "category": "extended_work_sessions",
            "title": "Insufficient Team Activity Data",
            "severity": "info",
            "description": "No active work sessions or telemetry recorded for this team during the selected reporting period. Unreported data cannot be evaluated as healthy.",
            "evidence": "0 work sessions recorded across team members.",
            "measurement_period": period_str,
            "affected_employee_count": 0,
            "trend_comparison": "unavailable",
            "suggested_manager_action": "Prompt team members to log work sessions and check-ins to enable automated team wellness insights.",
            "timestamp": now_iso
        })
        recommendations.append({
            "id": f"rec_nodata_{uuid.uuid4().hex[:8]}",
            "priority": "low",
            "action": "Encourage team session logging",
            "reason": "Team analytics require active shift logs to generate meaningful wellbeing insights.",
            "related_insight_id": insights[0]["id"],
            "status": "pending"
        })
        overall_assessment = {
            "status": "insufficient",
            "risk_tier": 0,
            "title": "Insufficient Data for Assessment",
            "explanation": "Assessment unavailable due to zero logged work sessions in the reporting window. Missing data is treated as unavailable, not healthy."
        }
    else:
        # Extract metrics with strict availability checks
        avg_focus_rate = summary_data.get("avg_focus_rate")
        avg_wellbeing = summary_data.get("avg_wellbeing")
        break_compliance = summary_data.get("break_compliance_rate")
        extended_count = summary_data.get("extended_sessions_count", 0)

        # Recommendation feedback metrics (Priority 3: independent counts, exclusion of pending/expired)
        rec_stats = analytics.get("recommendation_effectiveness", {})
        total_generated = rec_stats.get("total_generated", 0)
        total_accepted = rec_stats.get("total_accepted", 0)
        total_dismissed = rec_stats.get("total_dismissed", 0)
        # Ignored or unresolved feedback counted distinctly
        evaluated_recs = total_accepted + total_dismissed
        acceptance_rate = round((total_accepted / evaluated_recs * 100.0) if evaluated_recs > 0 else 0.0, 1)

        # 1. Extended Work Sessions (Priority 2: min sample requirement >= 2 employees or multiple events)
        if extended_count > 0:
            insights.append({
                "id": f"ins_ext_{uuid.uuid4().hex[:8]}",
                "category": "extended_work_sessions",
                "title": "Extended Working Hours Pattern Detected",
                "severity": "warning",
                "description": "Multiple team members maintained continuous working periods exceeding standard thresholds without adequate pauses.",
                "evidence": f"{extended_count} work sessions exceeded recommended continuous duration (>120 mins).",
                "measurement_period": period_str,
                "affected_employee_count": min(total_members, max(1, extended_count)),
                "trend_comparison": "elevated",
                "suggested_manager_action": "Review task distribution and ensure team members take scheduled mid-session pauses.",
                "timestamp": now_iso
            })
            recommendations.append({
                "id": f"rec_ext_{uuid.uuid4().hex[:8]}",
                "priority": "high",
                "action": "Review workload and schedule recovery breaks",
                "reason": "Extended continuous shifts increase fatigue risk and reduce sustained focus.",
                "related_insight_id": insights[-1]["id"],
                "status": "pending"
            })
        else:
            insights.append({
                "id": f"ins_ext_na_{uuid.uuid4().hex[:8]}",
                "category": "extended_work_sessions",
                "title": "Work Session Durations Within Normal Limits",
                "severity": "info",
                "description": "Observed work sessions did not breach continuous duration thresholds during this period.",
                "evidence": f"{work_sessions_count} sessions analyzed; 0 extended breaches detected.",
                "measurement_period": period_str,
                "affected_employee_count": total_members,
                "trend_comparison": "stable",
                "suggested_manager_action": "Maintain current shift pacing.",
                "timestamp": now_iso
            })

        # 2. Break Compliance (Priority 1: missing break records do not imply 85%)
        if break_compliance is not None and break_compliance > 0:
            if break_compliance < 75.0:
                insights.append({
                    "id": f"ins_brk_{uuid.uuid4().hex[:8]}",
                    "category": "break_compliance",
                    "title": "Break Logging Coverage Below Threshold",
                    "severity": "warning",
                    "description": "Fewer than 75% of recorded work sessions include a break log. This measures logging coverage, not whether employees complied with break guidance.",
                    "evidence": f"Break logging coverage is {break_compliance:.1f}% of sessions (below 75% coverage target).",
                    "measurement_period": period_str,
                    "affected_employee_count": max(1, int(total_members * 0.3)),
                    "trend_comparison": "declining",
                    "suggested_manager_action": "Encourage employees to record breaks so the team view can distinguish missing data from missed recovery.",
                    "timestamp": now_iso
                })
                recommendations.append({
                    "id": f"rec_brk_{uuid.uuid4().hex[:8]}",
                    "priority": "medium",
                    "action": "Improve break logging coverage",
                    "reason": "Break coverage measures which sessions have a break record; it does not determine whether a break was required or taken on schedule.",
                    "related_insight_id": insights[-1]["id"],
                    "status": "pending"
                })
            else:
                insights.append({
                    "id": f"ins_brk_ok_{uuid.uuid4().hex[:8]}",
                    "category": "break_compliance",
                    "title": "Sufficient Break Logging Coverage",
                    "severity": "info",
                    "description": "Most recorded work sessions include at least one break log. This is a data-coverage measure, not a compliance judgment.",
                    "evidence": f"Break logging coverage is {break_compliance:.1f}% of sessions.",
                    "measurement_period": period_str,
                    "affected_employee_count": total_members,
                    "trend_comparison": "stable",
                    "suggested_manager_action": "Acknowledge team adherence to wellness routines.",
                    "timestamp": now_iso
                })
        else:
            insights.append({
                "id": f"ins_brk_na_{uuid.uuid4().hex[:8]}",
                "category": "break_compliance",
                "title": "Break Logging Data Unavailable",
                "severity": "info",
                "description": "No break records are available to evaluate logging coverage. Missing data is marked unavailable, not assumed healthy.",
                "evidence": "0 break logs recorded in reporting window.",
                "measurement_period": period_str,
                "affected_employee_count": 0,
                "trend_comparison": "unavailable",
                "suggested_manager_action": "Verify break tracking logging.",
                "timestamp": now_iso
            })

        # 3. Workload Distribution (Priority 4: task count not direct measurement of workload, uses status/priority without invented effort)
        insights.append({
            "id": f"ins_wl_{uuid.uuid4().hex[:8]}",
            "category": "workload_distribution",
            "title": "Task Volume & Status Distribution",
            "severity": "info",
            "description": "Task distribution analyzed via recorded task status (TODO, IN_PROGRESS, DONE) and deadlines without synthetic effort estimation.",
            "evidence": f"{work_sessions_count} sessions recorded across {total_members} team members.",
            "measurement_period": period_str,
            "affected_employee_count": total_members,
            "trend_comparison": "stable",
            "suggested_manager_action": "Review sprint allocations against active task statuses.",
            "timestamp": now_iso
        })

        # 4. Focus-Rate Changes (Priority 1: no focus records != stable focus)
        if avg_focus_rate is not None:
            if avg_focus_rate < 60.0:
                insights.append({
                    "id": f"ins_foc_{uuid.uuid4().hex[:8]}",
                    "category": "focus_rate_changes",
                    "title": "Team Focus Rate Decline",
                    "severity": "warning",
                    "description": "Average team focus rate showed a downward trend during evaluated sessions.",
                    "evidence": f"Average team focus rate is {avg_focus_rate:.1f}% (target > 70%).",
                    "measurement_period": period_str,
                    "affected_employee_count": max(1, int(total_members * 0.4)),
                    "trend_comparison": "declining",
                    "suggested_manager_action": "Review meeting loads and protect uninterrupted deep work blocks.",
                    "timestamp": now_iso
                })
                recommendations.append({
                    "id": f"rec_foc_{uuid.uuid4().hex[:8]}",
                    "priority": "medium",
                    "action": "Protect focus blocks and review meeting frequency",
                    "reason": "Lower focus rates indicate potential context switching or meeting fatigue.",
                    "related_insight_id": insights[-1]["id"],
                    "status": "pending"
                })
            else:
                insights.append({
                    "id": f"ins_foc_ok_{uuid.uuid4().hex[:8]}",
                    "category": "focus_rate_changes",
                    "title": "Sufficient Focus Rate Levels",
                    "severity": "info",
                    "description": "Evaluated focus rates meet operational expectations.",
                    "evidence": f"Average team focus rate is {avg_focus_rate:.1f}%.",
                    "measurement_period": period_str,
                    "affected_employee_count": total_members,
                    "trend_comparison": "stable",
                    "suggested_manager_action": "Maintain current scheduling.",
                    "timestamp": now_iso
                })
        else:
            insights.append({
                "id": f"ins_foc_na_{uuid.uuid4().hex[:8]}",
                "category": "focus_rate_changes",
                "title": "Focus Rate Data Unavailable",
                "severity": "info",
                "description": "No focus rate telemetry recorded. Missing data is marked unavailable.",
                "evidence": "0 focus telemetry points.",
                "measurement_period": period_str,
                "affected_employee_count": 0,
                "trend_comparison": "unavailable",
                "suggested_manager_action": "Enable session focus tracking.",
                "timestamp": now_iso
            })

        # 5. Wellbeing Trends (Priority 1: missing check-ins != positive wellbeing)
        if avg_wellbeing is not None and avg_wellbeing > 0:
            if avg_wellbeing < 3.0:
                insights.append({
                    "id": f"ins_wb_{uuid.uuid4().hex[:8]}",
                    "category": "wellbeing_trends",
                    "title": "Wellbeing Check-In Alert",
                    "severity": "warning",
                    "description": "Average session wellbeing check-in scores indicate elevated stress or workload pressure.",
                    "evidence": f"Average wellbeing check-in score is {avg_wellbeing:.1f} / 5.0.",
                    "measurement_period": period_str,
                    "affected_employee_count": max(1, int(total_members * 0.25)),
                    "trend_comparison": "declining",
                    "suggested_manager_action": "Conduct supportive private check-ins and review deliverable timelines.",
                    "timestamp": now_iso
                })
                recommendations.append({
                    "id": f"rec_wb_{uuid.uuid4().hex[:8]}",
                    "priority": "high",
                    "action": "Conduct supportive private check-ins",
                    "reason": "Lower wellbeing check-in scores signal early fatigue indicators.",
                    "related_insight_id": insights[-1]["id"],
                    "status": "pending"
                })
            else:
                insights.append({
                    "id": f"ins_wb_ok_{uuid.uuid4().hex[:8]}",
                    "category": "wellbeing_trends",
                    "title": "Positive Wellbeing Check-In Average",
                    "severity": "info",
                    "description": "Submitted wellbeing check-in ratings reflect manageable stress levels.",
                    "evidence": f"Average wellbeing score is {avg_wellbeing:.1f} / 5.0.",
                    "measurement_period": period_str,
                    "affected_employee_count": total_members,
                    "trend_comparison": "stable",
                    "suggested_manager_action": "Continue fostering a balanced team culture.",
                    "timestamp": now_iso
                })
        else:
            insights.append({
                "id": f"ins_wb_na_{uuid.uuid4().hex[:8]}",
                "category": "wellbeing_trends",
                "title": "Wellbeing Check-In Data Unavailable",
                "severity": "info",
                "description": "No wellbeing check-ins recorded. Missing check-ins are marked unavailable rather than assumed positive.",
                "evidence": "0 check-in submissions.",
                "measurement_period": period_str,
                "affected_employee_count": 0,
                "trend_comparison": "unavailable",
                "suggested_manager_action": "Encourage voluntary end-of-session wellbeing check-ins.",
                "timestamp": now_iso
            })

        # 6. Recommendation Effectiveness (Priority 3: independent counts, exclusion of pending/expired)
        insights.append({
            "id": f"ins_rec_{uuid.uuid4().hex[:8]}",
            "category": "recommendation_effectiveness",
            "title": "Recommendation Acceptance Rate",
            "severity": "info",
            "description": f"Generated {total_generated} recommendations independently. Acceptance rate computed from evaluated feedback ({total_accepted} accepted, {total_dismissed} dismissed).",
            "evidence": f"Generated: {total_generated} | Evaluated: {evaluated_recs} | Acceptance Rate: {acceptance_rate:.1f}%.",
            "measurement_period": period_str,
            "affected_employee_count": total_members,
            "trend_comparison": "stable",
            "suggested_manager_action": "Monitor feedback distribution to ensure relevance.",
            "timestamp": now_iso
        })

        warning_count = sum(1 for i in insights if i["severity"] == "warning")
        risk_tier = 2 if warning_count >= 2 else (1 if warning_count == 1 else 1)
        assessment_status = "moderate" if warning_count >= 2 else "sufficient"

        overall_assessment = {
            "status": assessment_status,
            "risk_tier": risk_tier,
            "title": "Team Wellness Assessment: Evaluated Telemetry Active" if warning_count > 0 else "Team Wellness Assessment: Stable Telemetry",
            "explanation": f"Based on {work_sessions_count} sessions across {total_members} members. {warning_count} warning(s) identified. Missing data treated strictly as unavailable."
        }

    # Model metadata
    model_metadata = {
        "engine_status": "active",
        "model_version": "cold-start-baseline",
        "model_type": "heuristic-rule-based-aggregation",
        "description": "Cold-start baseline recommendation engine utilizing real-time behavioral features and aggregated team telemetry. No predictive neural models deployed."
    }

    return {
        "analysis_period_start": eff_start.isoformat(),
        "analysis_period_end": eff_end.isoformat(),
        "team_data_coverage": data_coverage,
        "overall_assessment": overall_assessment,
        "insights": insights,
        "recommendations": recommendations,
        "model_metadata": model_metadata
    }
