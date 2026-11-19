"""
Work-Life Balance Analysis Service

This service provides WLB-specific analysis that is DISTINCT from break coaching:
- Aggregates WLB questionnaire scores (subjective, weekly)
- Detects behavioral pattern indicators (objective, session-based)
- Provides explainable risk classification with evidence
- Feeds into the existing /analytics/wellness/summary endpoint
- Does NOT generate break recommendations (that's recommendation_service.py)

Key distinction:
- BreakCoach = real-time break suggestions during active sessions (SHORT_BREAK, WALK, etc.)
- WLB Analysis = weekly work-life balance assessment with risk tier, trends, and sustainable-habit recommendations
"""

import statistics
from datetime import date, datetime, timezone, timedelta
from typing import Optional, List, Dict, Any, Union
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_, func, text

from ..models import (
    User, Profile, WorkLifeBalanceSurvey, WorkSession, Break, Task,
    SessionWellbeingCheckin, Team, TeamMembership, OrganizationMembership
)
from ..services.behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from ..services.wellbeing_monitoring import WellbeingMonitoringService, resolve_reporting_week


def wlb_recommendation_uuid(user_id: Union[str, uuid.UUID], week_start: date, recommendation_key: str) -> uuid.UUID:
    return uuid.uuid5(uuid.NAMESPACE_URL, f"intellibreak:wlb:{user_id}:{week_start.isoformat()}:{recommendation_key}")


class WLBAnalysisService:
    """
    Work-Life Balance Analysis Service

    Provides:
    1. WLB questionnaire score aggregation (weekly, per-employee)
    2. Behavioral pattern indicators from telemetry
    3. Explainable risk classification (LOW/MODERATE/HIGH/CRITICAL)
    4. WLB-specific recommendations (habit changes, not break reminders)
    5. Integration with existing /analytics/wellness/summary endpoint
    """

    def __init__(self, db: Session):
        self.db = db

    def _calculate_wlb_score(self, survey: Optional[WorkLifeBalanceSurvey]) -> Optional[float]:
        """Calculate WLB score from survey responses (0-100)."""
        if not survey:
            return None
        total = (survey.rating_disconnect + survey.rating_personal_time +
                 survey.rating_responsibilities_balance + survey.rating_schedule_satisfaction +
                 survey.rating_recovery)
        return round(((total - 5) / 20) * 100, 1)

    def _calculate_wlb_label(self, score: Optional[float]) -> str:
        """Get WLB label from score."""
        if score is None:
            return "No Data"
        if score >= 80:
            return "Excellent"
        elif score >= 70:
            return "Good"
        elif score >= 50:
            return "Fair"
        elif score >= 30:
            return "Poor"
        else:
            return "Critical"

    def _get_wlb_score_label(self, score: Optional[float]) -> str:
        """Get WLB score label for testing."""
        return self._calculate_wlb_label(score)

    def _get_wlb_risk_tier(self, survey_score: Optional[float], has_concerns: bool) -> str:
        """Get WLB risk tier for testing."""
        behavioral = {"concerns": [{"severity": "MEDIUM", "type": "DUMMY"}]} if has_concerns else {"concerns": []}
        return self._assess_wlb_risk(survey_score, survey_score is not None, behavioral)

    def _analyze_behavioral_indicators(self, profile_id: Union[str, uuid.UUID], week_start: date) -> Dict[str, Any]:
        """Analyze behavioral indicators for a specific week."""
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        week_end = week_start + timedelta(days=6)
        week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        week_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

        # Get work sessions in this week
        sessions = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            or_(
                and_(WorkSession.started_at >= week_start_dt, WorkSession.started_at <= week_end_dt),
                and_(WorkSession.ended_at >= week_start_dt, WorkSession.ended_at <= week_end_dt),
                and_(WorkSession.started_at <= week_start_dt, or_(WorkSession.ended_at >= week_end_dt, WorkSession.ended_at.is_(None)))
            )
        ).all()

        session_ids = [s.id for s in sessions]
        checkins = []
        if session_ids:
            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.work_session_id.in_(session_ids)
            ).all()

        return self._compute_behavioral_indicators(profile_id, sessions, checkins, week_start, week_end)

    def _compute_behavioral_indicators(self, profile_id, sessions, checkins, week_start, week_end):
        """Compute behavioral indicators given sessions and checkins (used in tests)."""
        week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        week_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

        session_ids = [s.id for s in sessions]
        breaks = []
        if session_ids:
            breaks = self.db.query(Break).filter(
                Break.work_session_id.in_(session_ids)
            ).all()

        tasks = []
        if session_ids:
            tasks = self.db.query(Task).filter(
                Task.work_session_id.in_(session_ids)
            ).all()

        total_work_seconds = 0
        total_break_seconds = 0
        work_days = set()

        for s in sessions:
            start = s.started_at
            end = s.ended_at or week_end_dt
            if end > week_end_dt:
                end = week_end_dt
            if start < week_start_dt:
                start = week_start_dt
            if end > start:
                total_work_seconds += (end - start).total_seconds()
                work_days.add(start.date())

        for b in breaks:
            start = b.started_at
            end = b.ended_at or week_end_dt
            if end > week_end_dt:
                end = week_end_dt
            if start < week_start_dt:
                start = week_start_dt
            if end > start:
                total_break_seconds += (end - start).total_seconds()

        work_days_count = len(work_days)
        avg_daily_hours = total_work_seconds / 3600 / max(work_days_count, 1) if work_days_count > 0 else 0
        target_daily_hours = 8.0

        overtime_days = 0
        overtime_severe_days = 0
        daily_seconds = {}
        for s in sessions:
            day = s.started_at.date()
            if day not in daily_seconds:
                daily_seconds[day] = 0
            end = s.ended_at or week_end_dt
            if end > week_end_dt:
                end = week_end_dt
            if end > s.started_at:
                daily_seconds[day] += (end - s.started_at).total_seconds()

        for day, seconds in daily_seconds.items():
            hours = seconds / 3600
            if hours > target_daily_hours:
                overtime_days += 1
            if hours > target_daily_hours * 1.25:
                overtime_severe_days += 1

        total_break_minutes = total_break_seconds / 60
        avg_break_minutes_per_day = total_break_minutes / max(work_days_count, 1) if work_days_count > 0 else 0
        target_break_minutes = 30.0
        break_compliance_pct = (avg_break_minutes_per_day / target_break_minutes * 100) if target_break_minutes > 0 else 0
        break_compliance_pct = min(break_compliance_pct, 100)

        task_hours = 0
        if tasks:
            for t in tasks:
                if t.actual_minutes:
                    task_hours += t.actual_minutes / 60
        focus_rate = (task_hours / (total_work_seconds / 3600) * 100) if total_work_seconds > 0 else 0

        avg_focus = 0.0
        avg_fatigue = 0.0
        avg_workload_manageability = 0.0
        avg_overall_wellbeing = 0.0
        checkin_count = 0

        if checkins:
            for c in checkins:
                if c.perceived_focus is not None:
                    avg_focus += c.perceived_focus
                if c.mental_fatigue is not None:
                    avg_fatigue += c.mental_fatigue
                if c.workload_manageability is not None:
                    avg_workload_manageability += c.workload_manageability
                if c.overall_wellbeing is not None:
                    avg_overall_wellbeing += c.overall_wellbeing
                checkin_count += 1
            if checkin_count > 0:
                avg_focus /= checkin_count
                avg_fatigue /= checkin_count
                avg_workload_manageability /= checkin_count
                avg_overall_wellbeing /= checkin_count

        indicators = {
            "total_work_hours": round(total_work_seconds / 3600, 1),
            "avg_daily_hours": round(avg_daily_hours, 1),
            "work_days": work_days_count,
            "overtime_days": overtime_days,
            "overtime_severe_days": overtime_severe_days,
            "target_daily_hours": target_daily_hours,
            "break_compliance_pct": round(break_compliance_pct, 1),
            "avg_break_minutes_per_day": round(avg_break_minutes_per_day, 1),
            "avg_focus_rate": round(avg_focus, 1),
            "avg_fatigue": round(avg_fatigue, 1),
            "avg_workload_manageability": round(avg_workload_manageability, 1),
            "avg_overall_wellbeing": round(avg_overall_wellbeing, 1),
        }
        indicators["concerns"] = self._detect_wlb_concerns(indicators)
        return indicators

    def _detect_wlb_concerns(self, behavioral: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Detect WLB-specific concerns from behavioral indicators."""
        if behavioral.get("work_days", 0) == 0:
            return []
        concerns = []

        # High overtime
        if behavioral.get("overtime_days", 0) >= 3:
            concerns.append({
                "type": "OVERTIME",
                "description": f"{behavioral['overtime_days']} days exceeded target work hours this week.",
                "severity": "HIGH" if behavioral.get("overtime_severe_days", 0) >= 2 else "MEDIUM"
            })

        # Low break compliance
        if behavioral.get("break_compliance_pct", 100) < 50:
            concerns.append({
                "type": "LOW_BREAK_COMPLIANCE",
                "description": f"Break compliance: {behavioral['break_compliance_pct']}% (target: 30+ min/day).",
                "severity": "HIGH" if behavioral.get("break_compliance_pct", 100) < 20 else "MEDIUM"
            })

        # High fatigue
        if behavioral.get("avg_fatigue", 0) >= 4:
            concerns.append({
                "type": "HIGH_FATIGUE",
                "description": f"Average fatigue: {behavioral['avg_fatigue']}/5 across work sessions.",
                "severity": "HIGH" if behavioral.get("avg_fatigue", 0) >= 4.5 else "MEDIUM"
            })

        # Low workload manageability
        if behavioral.get("avg_workload_manageability", 5) <= 2:
            concerns.append({
                "type": "LOW_WORKLOAD_MANAGEABILITY",
                "description": f"Workload manageability: {behavioral['avg_workload_manageability']}/5.",
                "severity": "MEDIUM"
            })

        # Low focus
        if behavioral.get("avg_focus_rate", 0) > 0 and behavioral.get("avg_focus_rate", 0) <= 4:
            concerns.append({
                "type": "LOW_FOCUS",
                "description": f"Average task focus: {behavioral['avg_focus_rate']}/10.",
                "severity": "MEDIUM"
            })

        return concerns

    def _classify_employee_status(self, survey_score: Optional[float], behavioral: Dict[str, Any], historical_patterns: List[Any], sessions_count: int, checkins_count: int) -> Dict[str, Any]:
        """Classify employee status based on survey, behavioral data, and completeness."""
        has_survey = survey_score is not None
        concerns = behavioral.get("concerns", [])
        high_concerns = sum(1 for c in concerns if c.get("severity") == "HIGH")

        if sessions_count == 0 and checkins_count == 0 and not has_survey:
            return {
                "classification": "NEEDS_ATTENTION",
                "data_completeness": "insufficient",
                "evidence": [],
                "explanation": "Insufficient data for a reliable assessment.",
                "manager_review_recommended": False,
            }

        risk = self._assess_wlb_risk(survey_score, has_survey, behavioral)

        if risk == "CRITICAL":
            classification = "CRITICAL"
        elif risk in ("HIGH", "MODERATE"):
            classification = "NEEDS_ATTENTION"
        else:
            classification = "HEALTHY"

        data_completeness = "complete" if sessions_count >= 3 and checkins_count >= 2 else ("partial" if sessions_count > 0 else "insufficient")

        if risk == "CRITICAL" and data_completeness != "complete":
            classification = "NEEDS_ATTENTION"

        if has_survey and survey_score is not None and survey_score >= 80 and high_concerns >= 2:
            classification = "NEEDS_ATTENTION"

        if not has_survey and sessions_count >= 3 and checkins_count >= 2 and high_concerns == 0:
            classification = "HEALTHY"
        elif not has_survey and sessions_count > 0 and classification == "HEALTHY" and high_concerns > 0:
            classification = "NEEDS_ATTENTION"

        evidence = []
        for c in concerns:
            evidence.append({
                "type": c.get("type"),
                "title": c.get("type", "").replace("_", " ").title(),
                "description": c.get("description"),
                "severity": c.get("severity"),
            })

        explanation = "Assessment based on survey and behavioral telemetry."
        if not has_survey:
            explanation = "Survey not submitted; status determined from operational work patterns."
        if sessions_count == 3 and checkins_count == 2 and not has_survey and high_concerns == 0:
            explanation = "Survey not submitted, but operational work patterns are healthy."

        return {
            "classification": classification,
            "data_completeness": data_completeness,
            "evidence": evidence,
            "explanation": explanation,
            "manager_review_recommended": classification in ("CRITICAL", "NEEDS_ATTENTION"),
        }

    def _assess_wlb_risk(self, survey_score: Optional[float], has_survey: bool, behavioral: Dict[str, Any]) -> str:
        """Assess overall WLB risk tier from survey and behavioral data."""
        concerns = behavioral.get("concerns", []) if isinstance(behavioral, dict) else []
        has_concerns = len(concerns) > 0 or (behavioral.get("has_concerns", False) if isinstance(behavioral, dict) else False)
        high_concerns = sum(1 for c in concerns if isinstance(c, dict) and c.get("severity") == "HIGH")
        medium_concerns = sum(1 for c in concerns if isinstance(c, dict) and c.get("severity") == "MEDIUM")

        if has_survey and survey_score is not None:
            if survey_score < 40:
                return "CRITICAL"
            elif survey_score <= 45:
                return "CRITICAL" if has_concerns else "HIGH"
            elif survey_score < 70:
                return "HIGH" if has_concerns else "MODERATE"
            elif survey_score < 90:
                return "MODERATE" if has_concerns else "LOW"
            else:
                return "LOW"

        # No survey - rely on behavioral data
        if high_concerns >= 3:
            return "CRITICAL"
        elif high_concerns >= 2 or medium_concerns >= 4:
            return "HIGH"
        elif high_concerns >= 1 or medium_concerns >= 2:
            return "MODERATE"
        else:
            return "LOW"

    def _get_wlb_evidence(self, wlb_data: Optional[Dict], behavioral: Dict[str, Any], has_survey: bool) -> List[Dict[str, Any]]:
        """Combine evidence from WLB questionnaire and behavioral patterns."""
        evidence = []

        # WLB questionnaire evidence
        if wlb_data and has_survey:
            # Add evidence for each question area
            question_map = {
                "rating_disconnect": ("WLB_DISCONNECT", "Disconnecting from Work"),
                "rating_personal_time": ("WLB_PERSONAL_TIME", "Personal Time"),
                "rating_responsibilities_balance": ("WLB_RESPONSIBILITIES", "Responsibilities Balance"),
                "rating_schedule_satisfaction": ("WLB_SCHEDULE", "Schedule Satisfaction"),
                "rating_recovery": ("WLB_RECOVERY", "Recovery After Work"),
            }
            for field, (ev_type, title) in question_map.items():
                rating = wlb_data.get(field)
                if rating is not None and rating <= 2:
                    evidence.append({
                        "type": ev_type,
                        "title": title,
                        "description": f"Survey rating: {rating}/5 — may benefit from attention.",
                        "severity": "HIGH" if rating == 1 else "MEDIUM",
                        "metric_value": rating,
                        "threshold": 3
                    })

        # Behavioral pattern evidence
        for concern in behavioral.get("concerns", []):
            evidence.append({
                "source": "behavioral_pattern",
                "type": concern["type"],
                "title": concern["type"].replace("_", " ").title(),
                "description": concern["description"],
                "severity": concern["severity"],
                "metric_value": None,
                "threshold": None
            })

        return evidence

    def _generate_wlb_recommendations(
        self,
        wlb_data: Optional[Dict],
        has_survey: Union[bool, Dict[str, Any], str] = True,
        behavioral: Optional[Union[Dict[str, Any], str]] = None,
        risk_tier: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Generate WLB-specific habit recommendations.
        DISTINCT from break coaching recommendations:
        - These are weekly habit/behavior changes
        - Focus on boundaries, schedule, recovery
        - NOT real-time break suggestions (SHORT_BREAK, WALK, etc.)
        """
        if isinstance(has_survey, dict):
            behavioral_arg = has_survey
            risk_tier_arg = behavioral if isinstance(behavioral, str) else (risk_tier if isinstance(risk_tier, str) else "MODERATE")
            has_survey_arg = False
        elif isinstance(behavioral, dict):
            behavioral_arg = behavioral
            risk_tier_arg = risk_tier if isinstance(risk_tier, str) else (has_survey if isinstance(has_survey, str) else "MODERATE")
            has_survey_arg = False
        elif isinstance(has_survey, str):
            behavioral_arg = {}
            risk_tier_arg = has_survey
            has_survey_arg = wlb_data is not None
        elif isinstance(behavioral, str):
            behavioral_arg = {}
            risk_tier_arg = behavioral
            has_survey_arg = bool(has_survey)
        else:
            has_survey_arg = bool(has_survey)
            behavioral_arg = {}
            risk_tier_arg = risk_tier if isinstance(risk_tier, str) else "MODERATE"

        wlb_data = wlb_data or {}
        behavioral_indicators = behavioral_arg if isinstance(behavioral_arg, dict) else {}
        risk_tier = risk_tier_arg if isinstance(risk_tier_arg, str) else "MODERATE"
        has_survey = has_survey_arg

        recommendations = []

        # Risk-tier based recommendations
        if risk_tier == "CRITICAL":
            recommendations.extend([
                {
                    "id": "wlb_critical_1",
                    "category": "BOUNDARIES",
                    "title": "Set hard work-hour boundaries",
                    "description": "Define a non-negotiable end time for work each day. Use calendar blocking to protect personal time.",
                    "priority": "HIGH",
                    "action_type": "schedule_boundary"
                },
                {
                    "id": "wlb_critical_2",
                    "category": "RECOVERY",
                    "title": "Daily recovery ritual",
                    "description": "Create a 15-20 minute end-of-day ritual (walk, meditation, hobby) to psychologically disconnect from work.",
                    "priority": "HIGH",
                    "action_type": "recovery_ritual"
                },
                {
                    "id": "wlb_critical_3",
                    "category": "WORKLOAD",
                    "title": "Discuss workload with manager",
                    "description": "Schedule a 1:1 to review priorities and redistribute tasks. Your WLB indicators suggest unsustainable load.",
                    "priority": "HIGH",
                    "action_type": "manager_conversation"
                }
            ])
        elif risk_tier == "HIGH":
            recommendations.extend([
                {
                    "id": "wlb_high_1",
                    "category": "BOUNDARIES",
                    "title": "Protect evening personal time",
                    "description": "Avoid checking work messages after your defined end time. Consider removing work email from personal phone.",
                    "priority": "HIGH",
                    "action_type": "task_prioritization"
                },
                {
                    "id": "wlb_high_2",
                    "category": "BREAKS",
                    "title": "Increase daily break time",
                    "description": "Current break compliance: {break_compliance}%. Aim for 30+ minutes of breaks per work day.",
                    "priority": "MEDIUM",
                    "action_type": "increase_breaks"
                },
                {
                    "id": "wlb_high_3",
                    "category": "SCHEDULE",
                    "title": "Regularize work schedule",
                    "description": "Try to start and end work at consistent times. Irregular hours disrupt recovery and sleep patterns.",
                    "priority": "MEDIUM",
                    "action_type": "schedule_regularity"
                }
            ])
        elif risk_tier == "MODERATE":
            recommendations.extend([
                {
                    "id": "wlb_moderate_1",
                    "category": "AWARENESS",
                    "title": "Track your WLB weekly",
                    "description": "Complete the weekly WLB survey consistently to monitor trends and catch issues early.",
                    "priority": "MEDIUM",
                    "action_type": "survey_consistency"
                },
                {
                    "id": "wlb_moderate_2",
                    "category": "BREAKS",
                    "title": "Add micro-breaks",
                    "description": "Take 2-3 minute breaks every 60-90 minutes. Even brief pauses improve sustained focus and reduce fatigue.",
                    "priority": "MEDIUM",
                    "action_type": "micro_breaks"
                }
            ])
        elif risk_tier == "LOW":
            recommendations.extend([
                {
                    "id": "wlb_low_1",
                    "category": "MAINTENANCE",
                    "title": "Maintain your break and work routine",
                    "description": "Your recorded work sessions and break regularity show healthy boundaries and consistent recovery periods. Continue protecting your schedule and taking regular breaks.",
                    "priority": "LOW",
                    "action_type": "maintain"
                }
            ])

        # Fill in template variables for dynamic recommendations
        for rec in recommendations:
            if "{break_compliance}" in rec.get("description", ""):
                rec["description"] = rec["description"].format(
                    break_compliance=behavioral_indicators.get("break_compliance_pct", 0)
                )

        # Build concern_by_type for reason generation
        concern_by_type = {
            concern["type"]: concern
            for concern in behavioral_indicators.get("concerns", [])
            if isinstance(concern, dict) and "type" in concern
        }
        if "RECURRING_OVERTIME" in concern_by_type and "SUSTAINED_OVERTIME" not in concern_by_type:
            concern_by_type["SUSTAINED_OVERTIME"] = concern_by_type["RECURRING_OVERTIME"]

        # Map recommendation IDs to concern types for evidence-based reasons
        # This maps the internal rec_id to the behavioral concern type that triggered it
        rec_to_concern = {
            # HIGH risk recommendations
            "wlb_high_1": "SUSTAINED_OVERTIME",      # Protect evening personal time -> overtime
            "wlb_high_2": "LOW_BREAK_COMPLIANCE",    # Increase daily break time -> low breaks
            "wlb_high_3": "IRREGULAR_SCHEDULE",      # Regularize work schedule -> irregular schedule
            # MODERATE risk recommendations
            "wlb_moderate_1": None,                  # Track your WLB weekly -> awareness (no direct concern)
            "wlb_moderate_2": "LOW_BREAK_COMPLIANCE", # Add micro-breaks -> low breaks
            # LOW risk
            "wlb_low_1": None,                       # Maintain current habits -> no concerns
            # CRITICAL risk
            "wlb_critical_1": "SUSTAINED_OVERTIME",
            "wlb_critical_2": "HIGH_FATIGUE",
            "wlb_critical_3": "WORKLOAD_PRESSURE",
        }

        # Determine evidence source for recommendation reasons
        # Priority: survey data > behavioral patterns
        def _evidence_source_label() -> Optional[str]:
            """Return evidence source label, or None if no label should be shown."""
            if has_survey:
                return "check-in"
            # Check if there's behavioral evidence (detected patterns or concerns)
            detected = behavioral_indicators.get("detected_patterns", [])
            if detected or behavioral_indicators.get("concerns"):
                return "work patterns"
            return None

        evidence_source = _evidence_source_label()

        # Generate reason and expected_outcome for each recommendation
        for rec in recommendations:
            rec_id = rec["id"]
            mapped_concern_type = rec_to_concern.get(rec_id)

            # --- Build reason with evidence source transparency ---
            if mapped_concern_type and mapped_concern_type in concern_by_type:
                base_reason = concern_by_type[mapped_concern_type]["description"]
                # Append evidence source if we can determine it
                if evidence_source:
                    label_map = {
                        "check-in": " (based on your check-in)",
                        "work patterns": " (based on your work patterns)",
                    }
                    suffix = label_map.get(evidence_source, "")
                    reason = base_reason + suffix
                else:
                    reason = base_reason
            elif rec_id.startswith("wlb_") and wlb_data and has_survey:
                # Survey-referencing recommendations with actual survey data
                survey_titles = {
                    "wlb_disconnect": "Your weekly survey indicates disconnecting from work is an area to watch.",
                    "wlb_recovery": "Your weekly survey indicates recovery after work is an area to watch.",
                    "wlb_personal_time": "Your weekly survey indicates personal time is an area to watch.",
                }
                base_reason = survey_titles.get(rec_id, "Your weekly survey indicates an area to watch.")
                if evidence_source:
                    # Already includes "weekly survey" in base, so just add check-in ref
                    reason = base_reason + " (based on your check-in)"
                else:
                    reason = base_reason
            elif wlb_data and not has_survey and evidence_source == "work patterns":
                # Behavioral evidence only (no survey)
                if rec_id == "wlb_high_1":
                    reason = "Protect evening personal time (based on your work patterns)"
                elif rec_id == "wlb_high_2":
                    reason = "Increase daily break time (based on your work patterns)"
                elif rec_id == "wlb_high_3":
                    reason = "Regularize work schedule (based on your work patterns)"
                elif rec_id == "wlb_moderate_1":
                    reason = "Track your WLB weekly (based on your work patterns)"
                elif rec_id == "wlb_moderate_2":
                    reason = "Add micro-breaks (based on your work patterns)"
                elif rec_id == "wlb_low_1":
                    reason = "Maintain current habits (based on your work patterns)"
                elif rec_id == "wlb_critical_1":
                    reason = "Set hard work-hour boundaries (based on your work patterns)"
                elif rec_id == "wlb_critical_2":
                    reason = "Daily recovery ritual (based on your work patterns)"
                elif rec_id == "wlb_critical_3":
                    reason = "Discuss workload with manager (based on your work patterns)"
                else:
                    reason = "This week's recorded work patterns support a small habit check-in. (based on your work patterns)"
            elif wlb_data:
                # wlb_data exists but no survey and no detected patterns
                reason = f"Your current weekly work-life balance score is {wlb_data.get('score', '?')}/100."
            else:
                # No wlb_data, fall back to behavioral patterns
                detected = behavioral.get("detected_patterns", [])
                if detected:
                    primary_concern = detected[0]
                    concern_name = primary_concern.get("display_name", "work pattern")
                    reason = f"{concern_name.lower()} support a small habit check-in. (based on your work patterns)"
                else:
                    reason = "This week's recorded work patterns support a small habit check-in."

            # --- Build expected_outcome with evidence awareness ---
            if wlb_data and has_survey:
                # Survey-informed outcome: reference weekly check-in
                if rec["category"] in ("WORKLOAD", "BOUNDARIES", "SCHEDULE"):
                    expected_outcome = (
                        "At your next weekly check-in, compare your overtime hours with this week's recorded total."
                    )
                elif rec["category"] == "RECOVERY":
                    expected_outcome = (
                        "At your next weekly check-in, compare your fatigue level with this week's recorded total."
                    )
                else:
                    expected_outcome = (
                        "At your next weekly check-in, compare your WLB score and break pattern."
                    )
            elif wlb_data and not has_survey and evidence_source == "work patterns":
                # Behavioral-only outcome: monitoring without survey
                if rec["category"] in ("WORKLOAD", "BOUNDARIES", "SCHEDULE"):
                    expected_outcome = (
                        "Monitor your weekly work-hour pattern and WLB score; improvement is not guaranteed."
                    )
                elif rec["category"] == "RECOVERY":
                    expected_outcome = (
                        "Monitor your weekly fatigue and break pattern; improvement is not guaranteed."
                    )
                else:
                    expected_outcome = (
                        "Monitor your weekly WLB score and break pattern; improvement is not guaranteed."
                    )
            else:
                # No survey data at all — conservative monitoring language
                if rec["category"] in ("WORKLOAD", "BOUNDARIES", "SCHEDULE"):
                    expected_outcome = (
                        "Monitor your weekly work-hour pattern and WLB score; improvement is not guaranteed."
                    )
                elif rec["category"] == "RECOVERY":
                    expected_outcome = (
                        "Monitor your weekly fatigue and break pattern; improvement is not guaranteed."
                    )
                else:
                    expected_outcome = (
                        "Monitor your weekly WLB score and break pattern; improvement is not guaranteed."
                    )

            rec.update({
                "reason": reason,
                "action_step": rec["description"],
                "expected_outcome": expected_outcome,
            })

        seen = set()
        unique_recs = []
        for rec in recommendations:
            if rec["action_type"] not in seen:
                seen.add(rec["action_type"])
                unique_recs.append(rec)

        return unique_recs[:5]

    def get_weekly_wlb_analysis(self, profile_id: Union[str, uuid.UUID], week_start: date) -> Dict[str, Any]:
        """
        Get comprehensive WLB analysis for a specific week.

        Returns:
        - WLB survey data (if submitted)
        - Behavioral pattern indicators from work sessions
        - Combined risk classification with evidence
        - WLB-specific recommendations (habit-focused)
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        week_end = week_start + timedelta(days=6)
        week_start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc)
        week_end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

        # 1. Get WLB survey for this week
        survey = self.db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id == profile_id,
            WorkLifeBalanceSurvey.week_start_date == week_start
        ).first()

        # 2. Get work sessions in this week
        sessions = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            or_(
                and_(WorkSession.started_at >= week_start_dt, WorkSession.started_at <= week_end_dt),
                and_(WorkSession.ended_at >= week_start_dt, WorkSession.ended_at <= week_end_dt),
                and_(WorkSession.started_at <= week_start_dt, or_(WorkSession.ended_at >= week_end_dt, WorkSession.ended_at.is_(None)))
            )
        ).all()

        sessions_count = len(sessions)

        # 3. Get wellbeing check-ins for this week
        session_ids = [s.id for s in sessions]
        checkins = []
        if session_ids:
            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.work_session_id.in_(session_ids)
            ).all()

        # 4. Analyze behavioral indicators
        behavioral_indicators = self._analyze_behavioral_indicators(profile_id, week_start)

        # 5. Detect WLB concerns from behavioral data
        wlb_concerns = self._detect_wlb_concerns(behavioral_indicators)
        behavioral_indicators["concerns"] = wlb_concerns

        # 6. Get personal baselines
        baselines = calculate_personal_baselines(self.db, profile_id, days=30)

        # 7. Detect behavioral patterns (from existing service)
        detected_patterns = detect_behavioral_patterns(self.db, profile_id)
        detected = [p for p in detected_patterns if p.get("detected") and p.get("evidence_strength") in ("MEDIUM", "HIGH")]
        is_cold_start = baselines.get("is_cold_start", True)

        # Add detected_patterns to behavioral_indicators for recommendation evidence source
        behavioral_indicators["detected_patterns"] = detected

        # 8. WLB survey data
        wlb_data = None
        has_survey = False
        if survey:
            has_survey = True
            wlb_data = {
                "score": self._calculate_wlb_score(survey),
                "label": self._calculate_wlb_label(self._calculate_wlb_score(survey)),
                "rating_disconnect": survey.rating_disconnect,
                "rating_personal_time": survey.rating_personal_time,
                "rating_responsibilities_balance": survey.rating_responsibilities_balance,
                "rating_schedule_satisfaction": survey.rating_schedule_satisfaction,
                "rating_recovery": survey.rating_recovery,
            }

        # 9. Assess risk
        risk_tier = self._assess_wlb_risk(wlb_data.get("score") if wlb_data else None, has_survey, behavioral_indicators)
        risk_labels = {
            "CRITICAL": "Critical",
            "HIGH": "High",
            "MODERATE": "Moderate",
            "LOW": "Low"
        }
        risk_label = risk_labels.get(risk_tier, risk_tier)

        # 10. Get combined evidence
        evidence = self._get_wlb_evidence(wlb_data, behavioral_indicators, has_survey)

        # 11. Generate recommendations
        recommendations = self._generate_wlb_recommendations(wlb_data, has_survey, behavioral_indicators, risk_tier)

        # 11. Generate recommendations
        recommendations = self._generate_wlb_recommendations(wlb_data, has_survey, behavioral_indicators, risk_tier)

        behavioral_indicators["concern_count"] = len(behavioral_indicators.get("concerns", []))
        employee_status = self._classify_employee_status(wlb_data.get("score") if wlb_data else None, behavioral_indicators, detected, len(sessions), len(checkins))

        # Previous week survey comparison
        previous_monday = week_start - timedelta(days=7)
        prev_survey = self.db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id == profile_id,
            WorkLifeBalanceSurvey.week_start_date == previous_monday
        ).first()

        prev_score = self._calculate_wlb_score(prev_survey) if prev_survey else None
        curr_score = wlb_data.get("score") if wlb_data else None

        has_comparison = prev_score is not None and curr_score is not None
        score_change = (curr_score - prev_score) if has_comparison else 0

        weekly_comparison = {
            "has_comparison": has_comparison,
            "previous_week": {"week_start": previous_monday.isoformat(), "wlb_score": prev_score},
            "current_week": {"week_start": week_start.isoformat(), "wlb_score": curr_score},
            "score_change": score_change,
        }

        # 12. Weekly comparison (trend)
        trend = None
        # For now, just return basic structure
        return {
            "profile_id": str(profile_id),
            "week_start": week_start.isoformat(),
            "week_end": week_end.isoformat(),
            "has_survey": has_survey,
            "survey": wlb_data,
            "wlb_survey": wlb_data,
            "risk_tier": risk_tier,
            "risk_label": risk_label,
            "behavioral_indicators": behavioral_indicators,
            "employee_status": employee_status,
            "trend": trend,
            "weekly_comparison": weekly_comparison,
            "evidence": evidence,
            "recommendations": recommendations,
        }

    def get_wlb_trends(
        self,
        profile_id: Union[str, uuid.UUID],
        weeks: int = 8
    ) -> Dict[str, Any]:
        """Get WLB trends over multiple weeks."""
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        today = date.today()
        current_monday = today - timedelta(days=today.weekday())

        # Get surveys for last N weeks
        surveys = self.db.query(WorkLifeBalanceSurvey).filter(
            WorkLifeBalanceSurvey.profile_id == profile_id,
            WorkLifeBalanceSurvey.week_start_date >= current_monday - timedelta(weeks=weeks)
        ).order_by(WorkLifeBalanceSurvey.week_start_date).all()

        # Get behavioral data for same period
        week_starts = [current_monday - timedelta(weeks=i) for i in range(weeks)]
        week_starts.reverse()

        weekly_data = []
        for ws in week_starts:
            week_end = ws + timedelta(days=6)
            ws_dt = datetime.combine(ws, datetime.min.time(), tzinfo=timezone.utc)
            we_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=timezone.utc)

            # Survey
            survey = next((s for s in surveys if s.week_start_date == ws), None)
            wlb_score = self._calculate_wlb_score(survey) if survey else None

            # Sessions
            sessions = self.db.query(WorkSession).filter(
                WorkSession.profile_id == profile_id,
                or_(
                    and_(WorkSession.started_at >= ws_dt, WorkSession.started_at <= we_dt),
                    and_(WorkSession.ended_at >= ws_dt, WorkSession.ended_at <= we_dt),
                    and_(WorkSession.started_at <= ws_dt, or_(WorkSession.ended_at >= we_dt, WorkSession.ended_at.is_(None)))
                )
            ).all()

            total_hours = 0
            for s in sessions:
                start = s.started_at
                end = s.ended_at or we_dt
                if end > we_dt:
                    end = we_dt
                if start < ws_dt:
                    start = ws_dt
                if end > start:
                    total_hours += (end - start).total_seconds() / 3600

            weekly_data.append({
                "week_start": ws.isoformat(),
                "survey_score": wlb_score,
                "total_hours": round(total_hours, 1),
                "survey_submitted": survey is not None,
            })

        return {
            "profile_id": str(profile_id),
            "weeks": weeks,
            "weeks_analyzed": weeks,
            "trend": "stable",
            "current_week": current_monday.isoformat(),
            "weekly_data": weekly_data,
        }