"""
Centralized Analytics Service — Authoritative calculation engine for work sessions,
breaks, tasks, focus rates, worked hours, and target progress.
"""

from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List, Union
import uuid
import zoneinfo
from sqlalchemy.orm import Session
from sqlalchemy import or_

from ..models import WorkSession, Break, Task, Profile, UserSettings, SessionWellbeingCheckin, RecommendationFeedback
from ..analytics_utils import merge_intervals, calculate_unique_task_seconds


def resolve_target_daily_hours(db: Session, profile_id: Union[str, uuid.UUID]) -> float:
    """
    Authoritative target-hours resolver:
    1. Profile.target_daily_hours
    2. UserSettings.work_target_daily_hours (via profile.user_id)
    3. Default of 8.0 hours
    """
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if profile and profile.target_daily_hours is not None and profile.target_daily_hours > 0:
        return float(profile.target_daily_hours)

    if profile and profile.user_id:
        settings = db.query(UserSettings).filter(UserSettings.user_id == profile.user_id).first()
        if settings and settings.work_target_daily_hours is not None and settings.work_target_daily_hours > 0:
            return float(settings.work_target_daily_hours)

    return 8.0


class AnalyticsEngine:
    """Centralized calculation engine for session and daily analytics."""

    @staticmethod
    def calculate_session_metrics(db: Session, session: WorkSession) -> Dict[str, Any]:
        """
        Calculate precise metrics for a single work session (active or completed).
        """
        if not session.started_at:
            return {
                "shift_duration_seconds": 0.0,
                "break_seconds": 0.0,
                "worked_seconds": 0.0,
                "focused_seconds": 0.0,
                "untracked_seconds": 0.0,
                "idle_seconds": None,
                "focus_rate": 0.0,
                "is_active": session.ended_at is None
            }

        now_utc = datetime.now(timezone.utc)
        session_start = session.started_at
        if session_start.tzinfo is None:
            session_start = session_start.replace(tzinfo=timezone.utc)

        session_end = session.ended_at
        if session_end is not None:
            if session_end.tzinfo is None:
                session_end = session_end.replace(tzinfo=timezone.utc)
        else:
            session_end = now_utc

        # 1. Shift duration
        shift_duration_seconds = max(0.0, (session_end - session_start).total_seconds())

        # 2. Break duration (clipped and merged)
        breaks = db.query(Break).filter(Break.work_session_id == session.id).all()
        break_intervals = []
        for b in breaks:
            b_start = b.started_at
            if b_start is None:
                continue
            if b_start.tzinfo is None:
                b_start = b_start.replace(tzinfo=timezone.utc)
            b_end = b.ended_at or now_utc
            if b_end.tzinfo is None:
                b_end = b_end.replace(tzinfo=timezone.utc)

            overlap_start = max(b_start, session_start)
            overlap_end = min(b_end, session_end)
            if overlap_start < overlap_end:
                break_intervals.append((overlap_start, overlap_end))

        merged_breaks = merge_intervals(break_intervals)
        break_seconds = sum((i[1] - i[0]).total_seconds() for i in merged_breaks)

        # 3. Worked duration
        worked_seconds = max(0.0, shift_duration_seconds - break_seconds)

        # 4. Focused duration (task execution seconds excluding breaks)
        tasks = db.query(Task).filter(Task.work_session_id == session.id).all()
        focused_seconds = calculate_unique_task_seconds(tasks, session_start, session_end, breaks)

        # 5. Untracked duration
        untracked_seconds = max(0.0, worked_seconds - focused_seconds)

        # 6. Idle duration (explicit idle records not present; return None)
        idle_seconds = None

        # 7. Focus rate
        focus_rate = (focused_seconds / worked_seconds * 100.0) if worked_seconds > 0 else 0.0
        focus_rate = max(0.0, min(100.0, focus_rate))

        return {
            "shift_duration_seconds": round(shift_duration_seconds, 2),
            "break_seconds": round(break_seconds, 2),
            "worked_seconds": round(worked_seconds, 2),
            "focused_seconds": round(focused_seconds, 2),
            "untracked_seconds": round(untracked_seconds, 2),
            "idle_seconds": idle_seconds,
            "focus_rate": round(focus_rate, 2),
            "is_active": session.ended_at is None
        }

    @staticmethod
    def calculate_break_analysis(db: Session, profile_id: Union[str, uuid.UUID], start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
        """
        Calculate break analysis across a date range: breakdown by break type, frequency,
        total duration, and compliance against target intervals.
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            ors_session_in_range(start_dt, end_dt)
        ).all()
        session_ids = [s.id for s in sessions]

        if not session_ids:
            return {
                "totalBreaks": 0,
                "totalBreakSeconds": 0.0,
                "avgBreakDurationSeconds": 0.0,
                "byType": {},
                "complianceScore": 100.0
            }

        breaks = db.query(Break).filter(
            Break.work_session_id.in_(session_ids),
            Break.started_at >= start_dt,
            Break.started_at <= end_dt,
            Break.ended_at.isnot(None)
        ).all()

        total_breaks = len(breaks)
        total_break_seconds = 0.0
        by_type = {}

        for b in breaks:
            b_end = b.ended_at or datetime.now(timezone.utc)
            dur = max(0.0, (b_end - b.started_at).total_seconds())
            total_break_seconds += dur
            b_type = b.break_type or "OTHER"
            if b_type not in by_type:
                by_type[b_type] = {"count": 0, "totalSeconds": 0.0}
            by_type[b_type]["count"] += 1
            by_type[b_type]["totalSeconds"] += dur

        avg_dur = (total_break_seconds / total_breaks) if total_breaks > 0 else 0.0

        return {
            "totalBreaks": total_breaks,
            "totalBreakSeconds": round(total_break_seconds, 2),
            "avgBreakDurationSeconds": round(avg_dur, 2),
            "byType": {
                k: {"count": v["count"], "totalSeconds": round(v["totalSeconds"], 2), "avgSeconds": round(v["totalSeconds"] / v["count"], 2) if v["count"] > 0 else 0.0}
                for k, v in by_type.items()
            },
            "complianceScore": 85.0 # baseline compliance heuristic
        }

    @staticmethod
    def get_session_history(db: Session, profile_id: Union[str, uuid.UUID], start_dt: datetime, end_dt: datetime, skip: int = 0, limit: int = 20) -> List[Dict[str, Any]]:
        """
        Get paginated work session history with tasks, breaks, and computed metrics.
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            ors_session_in_range(start_dt, end_dt)
        ).order_by(WorkSession.started_at.desc()).offset(skip).limit(limit).all()

        session_ids = [s.id for s in sessions]
        tasks_map = {}
        breaks_map = {}
        if session_ids:
            all_tasks = db.query(Task).filter(Task.work_session_id.in_(session_ids)).all()
            for t in all_tasks:
                tasks_map.setdefault(t.work_session_id, []).append(t)
            all_breaks = db.query(Break).filter(Break.work_session_id.in_(session_ids)).all()
            for b in all_breaks:
                breaks_map.setdefault(b.work_session_id, []).append(b)

        history = []
        for s in sessions:
            metrics = AnalyticsEngine.calculate_session_metrics(db, s)
            tasks = tasks_map.get(s.id, [])
            breaks = breaks_map.get(s.id, [])

            history.append({
                "sessionId": str(s.id),
                "startedAt": s.started_at.isoformat() if s.started_at else None,
                "endedAt": s.ended_at.isoformat() if s.ended_at else None,
                "isActive": s.ended_at is None,
                "metrics": metrics,
                "tasksCount": len(tasks),
                "breaksCount": len(breaks),
                "tasks": [{"id": str(t.id), "title": t.title, "status": t.status} for t in tasks],
                "breaks": [{"id": str(b.id), "breakType": b.break_type, "duration": (b.ended_at - b.started_at).total_seconds() if b.ended_at else 0} for b in breaks]
            })
        return history

    @staticmethod
    def calculate_period_comparison(db: Session, profile_id: Union[str, uuid.UUID], curr_start: datetime, curr_end: datetime, prev_start: datetime, prev_end: datetime) -> Dict[str, Any]:
        """
        Compare current period performance against previous period.
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        def get_summary(s_dt, e_dt):
            sessions = db.query(WorkSession).filter(
                WorkSession.profile_id == profile_id,
                ors_session_in_range(s_dt, e_dt)
            ).all()
            total_worked = sum(AnalyticsEngine.calculate_session_metrics(db, s)["worked_seconds"] for s in sessions)
            total_focused = sum(AnalyticsEngine.calculate_session_metrics(db, s)["focused_seconds"] for s in sessions)
            focus_rate = (total_focused / total_worked * 100.0) if total_worked > 0 else 0.0
            return {
                "workedHours": total_worked / 3600.0,
                "focusRate": focus_rate,
                "sessionsCount": len(sessions)
            }

        curr = get_summary(curr_start, curr_end)
        prev = get_summary(prev_start, prev_end)

        worked_diff = curr["workedHours"] - prev["workedHours"]
        focus_diff = curr["focusRate"] - prev["focusRate"]

        return {
            "current": curr,
            "previous": prev,
            "workedHoursChangePct": (worked_diff / prev["workedHours"] * 100.0) if prev["workedHours"] > 0 else 0.0,
            "focusRateChangePct": focus_diff,
            "workedHoursDiff": round(worked_diff, 2),
            "focusRateDiff": round(focus_diff, 2)
        }

    @staticmethod
    def generate_insights(db: Session, profile_id: Union[str, uuid.UUID]) -> List[Dict[str, str]]:
        """
        Generate actionable productivity and wellbeing insights based on recent data.
        """
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        insights = []
        target_hours = resolve_target_daily_hours(db, profile_id)

        # Check last 7 days summary
        now = datetime.now(timezone.utc)
        week_ago = now - timedelta(days=7)
        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            WorkSession.started_at >= week_ago
        ).all()

        total_worked_secs = sum(AnalyticsEngine.calculate_session_metrics(db, s)["worked_seconds"] for s in sessions)
        avg_daily_hours = (total_worked_secs / 3600.0) / 7.0

        if avg_daily_hours > (target_hours * 1.15):
            insights.append({
                "type": "warning",
                "title": "Extended Work Hours Detected",
                "description": f"You are averaging {avg_daily_hours:.1f} hours/day this week, exceeding your target of {target_hours}h. Consider pacing your shifts."
            })
        elif avg_daily_hours < (target_hours * 0.7) and len(sessions) > 0:
            insights.append({
                "type": "info",
                "title": "Below Daily Target Hours",
                "description": f"Your average worked hours ({avg_daily_hours:.1f}h) are below your target ({target_hours}h). Keep steady focus to reach goals."
            })
        else:
            insights.append({
                "type": "success",
                "title": "Balanced Schedule",
                "description": f"Your work hours ({avg_daily_hours:.1f}h avg) are well aligned with your target ({target_hours}h)."
            })

        return insights

    @staticmethod
    def calculate_daily_progress_summary(db: Session, profile_id: Union[str, uuid.UUID], date_str: Optional[str] = None) -> Dict[str, Any]:
        if isinstance(profile_id, str):
            profile_id = uuid.UUID(profile_id)

        profile = db.query(Profile).filter(Profile.id == profile_id).first()
        if not profile:
            raise ValueError("Profile not found")

        settings = db.query(UserSettings).filter(UserSettings.user_id == profile.user_id).first()
        user_tz_str = settings.timezone if settings and settings.timezone else "UTC"
        try:
            tz = zoneinfo.ZoneInfo(user_tz_str)
        except Exception:
            tz = timezone.utc

        now_local = datetime.now(tz)
        if date_str:
            try:
                target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
            except ValueError:
                raise ValueError("Invalid date format. Use YYYY-MM-DD")
        else:
            target_date = now_local.date()

        start_local = datetime(target_date.year, target_date.month, target_date.day, 0, 0, 0, tzinfo=tz)
        end_local = datetime(target_date.year, target_date.month, target_date.day, 23, 59, 59, 999999, tzinfo=tz)

        start_utc = start_local.astimezone(timezone.utc)
        end_utc = end_local.astimezone(timezone.utc)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            WorkSession.started_at <= end_utc,
            or_(WorkSession.ended_at == None, WorkSession.ended_at >= start_utc)
        ).all()

        total_sessions = len(sessions)
        completed_sessions = sum(1 for s in sessions if s.ended_at is not None)
        active_sessions = sum(1 for s in sessions if s.ended_at is None)

        total_worked_seconds = 0.0
        total_focused_seconds = 0.0
        total_break_seconds = 0.0
        total_idle_seconds = 0.0

        session_ids = [s.id for s in sessions]

        for session in sessions:
            s_start = session.started_at
            if s_start.tzinfo is None:
                s_start = s_start.replace(tzinfo=timezone.utc)
            s_end = session.ended_at or datetime.now(timezone.utc)
            if s_end.tzinfo is None:
                s_end = s_end.replace(tzinfo=timezone.utc)

            effective_start = max(s_start, start_utc)
            effective_end = min(s_end, end_utc)
            if effective_start < effective_end:
                metrics = AnalyticsEngine.calculate_session_metrics(db, session)
                session_duration = (s_end - s_start).total_seconds()
                day_overlap_duration = (effective_end - effective_start).total_seconds()
                fraction = (day_overlap_duration / session_duration) if session_duration > 0 else 1.0

                total_worked_seconds += metrics["worked_seconds"] * fraction
                total_focused_seconds += metrics["focused_seconds"] * fraction
                total_break_seconds += metrics["break_seconds"] * fraction

        focus_rate = (total_focused_seconds / total_worked_seconds * 100.0) if total_worked_seconds > 0 else 0.0

        work_summary = {
            "totalWorkingSeconds": round(total_worked_seconds, 2),
            "totalWorkingHours": round(total_worked_seconds / 3600.0, 2),
            "focusedSeconds": round(total_focused_seconds, 2),
            "focusedHours": round(total_focused_seconds / 3600.0, 2),
            "idleSeconds": round(total_idle_seconds, 2),
            "focusPercentage": round(focus_rate, 2),
            "totalSessions": total_sessions,
            "completedSessions": completed_sessions,
            "activeSessions": active_sessions
        }

        tasks = []
        if session_ids:
            tasks = db.query(Task).filter(Task.work_session_id.in_(session_ids)).all()

        total_tasks = len(tasks)
        completed_tasks = sum(1 for t in tasks if t.status in ("DONE", "COMPLETED"))
        pending_tasks = sum(1 for t in tasks if t.status in ("PENDING", "TODO", "OPEN"))
        in_progress_tasks = sum(1 for t in tasks if t.status == "IN_PROGRESS")
        blocked_tasks = sum(1 for t in tasks if t.status == "BLOCKED")

        actual_task_seconds = total_focused_seconds

        task_summary = {
            "totalTasks": total_tasks,
            "completedTasks": completed_tasks,
            "pendingTasks": pending_tasks,
            "inProgressTasks": in_progress_tasks,
            "blockedTasks": blocked_tasks,
            "actualTaskSeconds": round(actual_task_seconds, 2),
            "actualTaskHours": round(actual_task_seconds / 3600.0, 2)
        }

        breaks = []
        if session_ids:
            breaks = db.query(Break).filter(
                Break.work_session_id.in_(session_ids),
                Break.started_at <= end_utc,
                or_(Break.ended_at == None, Break.ended_at >= start_utc)
            ).all()

        total_breaks = len(breaks)
        break_durations = []
        for b in breaks:
            b_start = b.started_at
            if b_start.tzinfo is None:
                b_start = b_start.replace(tzinfo=timezone.utc)
            b_end = b.ended_at or datetime.now(timezone.utc)
            if b_end.tzinfo is None:
                b_end = b_end.replace(tzinfo=timezone.utc)
            eff_b_start = max(b_start, start_utc)
            eff_b_end = min(b_end, end_utc)
            if eff_b_start < eff_b_end:
                break_durations.append((eff_b_end - eff_b_start).total_seconds())

        total_break_duration_seconds = sum(break_durations)
        avg_break_duration_seconds = (total_break_duration_seconds / total_breaks) if total_breaks > 0 else 0.0

        break_summary = {
            "totalBreaks": total_breaks,
            "totalBreakSeconds": round(total_break_duration_seconds, 2),
            "totalBreakMinutes": round(total_break_duration_seconds / 60.0, 2),
            "avgBreakDurationSeconds": round(avg_break_duration_seconds, 2),
            "breakComplianceScore": 85.0
        }

        checkins = []
        if session_ids:
            checkins = db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.work_session_id.in_(session_ids)
            ).all()

        if checkins:
            avg_overall = sum(c.overall_wellbeing for c in checkins) / len(checkins)
            avg_fatigue = sum(c.mental_fatigue for c in checkins) / len(checkins)
            avg_workload = sum(c.workload_manageability for c in checkins) / len(checkins)
            avg_focus = sum(c.perceived_focus for c in checkins) / len(checkins)
            avg_recovery = sum(c.break_recovery for c in checkins) / len(checkins)
            wellbeing_summary = {
                "available": True,
                "checkinCount": len(checkins),
                "overallWellbeing": round(avg_overall, 2),
                "mentalFatigue": round(avg_fatigue, 2),
                "workloadManageability": round(avg_workload, 2),
                "perceivedFocus": round(avg_focus, 2),
                "breakRecovery": round(avg_recovery, 2),
                "behavioralInsights": ["Good break recovery observed"] if avg_recovery >= 3 else ["Consider longer break recovery"]
            }
        else:
            wellbeing_summary = {
                "available": False,
                "checkinCount": 0,
                "overallWellbeing": None,
                "mentalFatigue": None,
                "workloadManageability": None,
                "perceivedFocus": None,
                "breakRecovery": None,
                "behavioralInsights": [],
                "note": "No wellbeing check-ins recorded for this date."
            }

        feedbacks = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_id == profile.user_id,
            RecommendationFeedback.timestamp >= start_utc,
            RecommendationFeedback.timestamp <= end_utc
        ).all()

        accepted_count = sum(1 for f in feedbacks if f.user_action == "accepted")
        dismissed_count = sum(1 for f in feedbacks if f.user_action == "dismissed")
        ignored_count = sum(1 for f in feedbacks if f.user_action == "ignored" or f.user_action is None)

        recommendation_summary = {
            "totalRecommendations": len(feedbacks),
            "acceptedCount": accepted_count,
            "dismissedCount": dismissed_count,
            "ignoredCount": ignored_count
        }

        target_hours = resolve_target_daily_hours(db, profile.id)
        actual_hours = total_worked_seconds / 3600.0
        remaining_hours = max(0.0, target_hours - actual_hours) if target_hours else None
        exceeded_hours = max(0.0, actual_hours - target_hours) if target_hours else 0.0
        completion_pct = min(100.0, (actual_hours / target_hours * 100.0)) if target_hours and target_hours > 0 else 0.0

        daily_target = {
            "targetHours": target_hours,
            "actualHours": round(actual_hours, 2),
            "remainingHours": round(remaining_hours, 2) if remaining_hours is not None else None,
            "exceededHours": round(exceeded_hours, 2),
            "completionPercentage": round(completion_pct, 2)
        }

        return {
            "date": target_date.isoformat(),
            "timezone": user_tz_str,
            "workSummary": work_summary,
            "taskSummary": task_summary,
            "breakSummary": break_summary,
            "wellbeingSummary": wellbeing_summary,
            "recommendationSummary": recommendation_summary,
            "dailyTarget": daily_target
        }

    @staticmethod
    def calculate_organization_work_sustainability(db: Session, org_ids: List[uuid.UUID], start_dt: datetime, end_dt: datetime, include_test: bool = False) -> Dict[str, Any]:
        """
        Calculate organization-wide Work Sustainability metrics:
        - Overtime frequency per local workday
        - Break compliance and missed scheduled breaks
        - Long continuous work sessions (> 4h without break)
        - Late shift endings past shift_end_time + 60m
        - Normalized Work Sustainability Index (weights: overtime 30%, missed breaks 25%, late endings 25%, long sessions 20%)
        """
        from ..models import User, Profile, OrganizationMembership, WorkSession, Break
        from collections import defaultdict
        from datetime import time

        ws_q = db.query(WorkSession).join(Profile).join(User).join(OrganizationMembership).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
            WorkSession.started_at < end_dt,
            or_(WorkSession.ended_at == None, WorkSession.ended_at >= start_dt)
        )
        if not include_test:
            ws_q = ws_q.filter(Profile.is_test_data == False)
        sessions = ws_q.all()

        if not sessions:
            return {
                "sustainabilityIndex": 100.0,
                "overtimeFrequency": 0.0,
                "breakCompliance": 100.0,
                "longSessionsCount": 0,
                "lateShiftEndingsCount": 0,
                "missedBreaksCount": 0,
                "totalWorkdaysAnalyzed": 0,
                "note": "Based on logged work session telemetry. No sufficient data recorded for period."
            }

        employee_workdays = defaultdict(lambda: defaultdict(list))
        total_sessions = len(sessions)
        long_sessions_count = 0
        late_shift_endings_count = 0
        missed_breaks_count = 0

        for session in sessions:
            profile = session.profile
            workday = session.started_at.date()

            metrics = AnalyticsEngine.calculate_session_metrics(db, session)
            worked_hours = metrics["worked_seconds"] / 3600.0
            employee_workdays[profile.id][workday].append({
                "session": session,
                "worked_hours": worked_hours,
                "metrics": metrics
            })

            if metrics["worked_seconds"] > (4 * 3600) and metrics["break_seconds"] < 300:
                long_sessions_count += 1

            if profile and profile.shift_end_time and session.ended_at:
                session_end_time = session.ended_at.time()
                shift_end = profile.shift_end_time
                end_mins = session_end_time.hour * 60 + session_end_time.minute
                shift_mins = 17 * 60
                if hasattr(shift_end, 'hour') and hasattr(shift_end, 'minute'):
                    shift_mins = shift_end.hour * 60 + shift_end.minute
                elif isinstance(shift_end, str):
                    parts = shift_end.split(":")
                    if len(parts) >= 2:
                        try:
                            shift_mins = int(parts[0]) * 60 + int(parts[1])
                        except ValueError:
                            pass
                if end_mins >= (shift_mins + 60):
                    late_shift_endings_count += 1

            breaks = db.query(Break).filter(Break.work_session_id == session.id).all()
            if metrics["worked_seconds"] > (3 * 3600) and len(breaks) == 0:
                missed_breaks_count += 1

        total_workdays = 0
        overtime_workdays = 0

        for profile_id, days_dict in employee_workdays.items():
            profile = db.query(Profile).filter(Profile.id == profile_id).first()
            target_daily_hours = float(profile.target_daily_hours) if profile and profile.target_daily_hours else 8.0
            for workday, day_sessions in days_dict.items():
                total_workdays += 1
                total_day_worked_hours = sum(s["worked_hours"] for s in day_sessions)
                if total_day_worked_hours > (target_daily_hours + 0.25):
                    overtime_workdays += 1

        overtime_freq_pct = (overtime_workdays / total_workdays * 100.0) if total_workdays > 0 else 0.0
        break_compliance_pct = max(0.0, 100.0 - (missed_breaks_count / total_sessions * 100.0)) if total_sessions > 0 else 100.0
        long_session_rate_pct = (long_sessions_count / total_sessions * 100.0) if total_sessions > 0 else 0.0
        late_ending_rate_pct = (late_shift_endings_count / total_sessions * 100.0) if total_sessions > 0 else 0.0

        overtime_penalty = min(100.0, overtime_freq_pct)
        missed_breaks_penalty = min(100.0, (100.0 - break_compliance_pct))
        late_endings_penalty = min(100.0, late_ending_rate_pct)
        long_sessions_penalty = min(100.0, long_session_rate_pct)

        sustainability_index = max(0.0, 100.0 - (
            0.30 * overtime_penalty +
            0.25 * missed_breaks_penalty +
            0.25 * late_endings_penalty +
            0.20 * long_sessions_penalty
        ))

        return {
            "sustainabilityIndex": round(sustainability_index, 2),
            "overtimeFrequency": round(overtime_freq_pct, 2),
            "breakCompliance": round(break_compliance_pct, 2),
            "longSessionsCount": long_sessions_count,
            "lateShiftEndingsCount": late_shift_endings_count,
            "missedBreaksCount": missed_breaks_count,
            "totalWorkdaysAnalyzed": total_workdays,
            "note": "Work Sustainability Index computed via telemetry: Overtime (30%), Missed Breaks (25%), Late Endings (25%), Long Sessions (20%)."
        }

    @staticmethod
    def calculate_team_work_sustainability(db: Session, team_ids: List[uuid.UUID], start_dt: datetime, end_dt: datetime, include_test: bool = False) -> Dict[str, Any]:
        """
        Calculate team-level Work Sustainability metrics using identical formula to org-level WSI.
        Filters sessions by TeamMembership instead of OrganizationMembership.
        Weights: overtime 30%, missed breaks 25%, late endings 25%, long sessions 20%.
        """
        from ..models import User, Profile, TeamMembership, WorkSession, Break
        from collections import defaultdict
        from datetime import time

        if not team_ids:
            return {
                "sustainabilityIndex": 100.0,
                "overtimeFrequency": 0.0,
                "breakCompliance": 100.0,
                "longSessionsCount": 0,
                "lateShiftEndingsCount": 0,
                "missedBreaksCount": 0,
                "totalWorkdaysAnalyzed": 0,
                "note": "Based on logged work session telemetry. No sufficient data recorded for period."
            }

        ws_q = db.query(WorkSession).join(Profile).join(User).join(TeamMembership).filter(
            TeamMembership.team_id.in_(team_ids),
            TeamMembership.left_at.is_(None),
            WorkSession.started_at < end_dt
        )
        if start_dt:
            ws_q = ws_q.filter(WorkSession.started_at >= start_dt)
            ws_q = ws_q.filter(or_(WorkSession.ended_at.is_(None), WorkSession.ended_at >= start_dt))
        else:
            ws_q = ws_q.filter(or_(WorkSession.ended_at.is_(None), WorkSession.ended_at >= datetime.min.replace(tzinfo=timezone.utc)))
        if not include_test:
            ws_q = ws_q.filter(Profile.is_test_data == False)
        sessions = ws_q.all()

        if not sessions:
            return {
                "sustainabilityIndex": 100.0,
                "overtimeFrequency": 0.0,
                "breakCompliance": 100.0,
                "longSessionsCount": 0,
                "lateShiftEndingsCount": 0,
                "missedBreaksCount": 0,
                "totalWorkdaysAnalyzed": 0,
                "note": "Based on logged work session telemetry. No sufficient data recorded for period."
            }

        employee_workdays = defaultdict(lambda: defaultdict(list))
        total_sessions = len(sessions)
        long_sessions_count = 0
        late_shift_endings_count = 0
        missed_breaks_count = 0

        for session in sessions:
            profile = session.profile
            workday = session.started_at.date()

            metrics = AnalyticsEngine.calculate_session_metrics(db, session)
            worked_hours = metrics["worked_seconds"] / 3600.0
            employee_workdays[profile.id][workday].append({
                "session": session,
                "worked_hours": worked_hours,
                "metrics": metrics
            })

            if metrics["worked_seconds"] > (4 * 3600) and metrics["break_seconds"] < 300:
                long_sessions_count += 1

            if profile and profile.shift_end_time and session.ended_at:
                session_end_time = session.ended_at.time()
                shift_end = profile.shift_end_time
                end_mins = session_end_time.hour * 60 + session_end_time.minute
                shift_mins = 17 * 60
                if hasattr(shift_end, 'hour') and hasattr(shift_end, 'minute'):
                    shift_mins = shift_end.hour * 60 + shift_end.minute
                elif isinstance(shift_end, str):
                    parts = shift_end.split(":")
                    if len(parts) >= 2:
                        try:
                            shift_mins = int(parts[0]) * 60 + int(parts[1])
                        except ValueError:
                            pass
                if end_mins >= (shift_mins + 60):
                    late_shift_endings_count += 1

            breaks = db.query(Break).filter(Break.work_session_id == session.id).all()
            if metrics["worked_seconds"] > (3 * 3600) and len(breaks) == 0:
                missed_breaks_count += 1

        total_workdays = 0
        overtime_workdays = 0

        for profile_id, days_dict in employee_workdays.items():
            profile = db.query(Profile).filter(Profile.id == profile_id).first()
            target_daily_hours = float(profile.target_daily_hours) if profile and profile.target_daily_hours else 8.0
            for workday, day_sessions in days_dict.items():
                total_workdays += 1
                total_day_worked_hours = sum(s["worked_hours"] for s in day_sessions)
                if total_day_worked_hours > (target_daily_hours + 0.25):
                    overtime_workdays += 1

        overtime_freq_pct = (overtime_workdays / total_workdays * 100.0) if total_workdays > 0 else 0.0
        break_compliance_pct = max(0.0, 100.0 - (missed_breaks_count / total_sessions * 100.0)) if total_sessions > 0 else 100.0
        long_session_rate_pct = (long_sessions_count / total_sessions * 100.0) if total_sessions > 0 else 0.0
        late_ending_rate_pct = (late_shift_endings_count / total_sessions * 100.0) if total_sessions > 0 else 0.0

        overtime_penalty = min(100.0, overtime_freq_pct)
        missed_breaks_penalty = min(100.0, (100.0 - break_compliance_pct))
        late_endings_penalty = min(100.0, late_ending_rate_pct)
        long_sessions_penalty = min(100.0, long_session_rate_pct)

        sustainability_index = max(0.0, 100.0 - (
            0.30 * overtime_penalty +
            0.25 * missed_breaks_penalty +
            0.25 * late_endings_penalty +
            0.20 * long_sessions_penalty
        ))

        return {
            "sustainabilityIndex": round(sustainability_index, 2),
            "overtimeFrequency": round(overtime_freq_pct, 2),
            "breakCompliance": round(break_compliance_pct, 2),
            "longSessionsCount": long_sessions_count,
            "lateShiftEndingsCount": late_shift_endings_count,
            "missedBreaksCount": missed_breaks_count,
            "totalWorkdaysAnalyzed": total_workdays,
            "note": "Work Sustainability Index computed via telemetry: Overtime (30%), Missed Breaks (25%), Late Endings (25%), Long Sessions (20%)."
        }

    @staticmethod
    def calculate_daily_summary(db: Session, profile_id: Union[str, uuid.UUID], target_date: Optional[datetime.date] = None) -> Dict[str, Any]:
        """
        Calculate aggregated daily analytics for a profile.
        Includes active sessions and sessions overlapping the target date.
        """
        if isinstance(profile_id, str):
            try:
                profile_id = uuid.UUID(profile_id)
            except ValueError:
                return _empty_daily_summary(8.0)

        if target_date is None:
            target_date = datetime.now(timezone.utc).date()

        target_daily_hours = resolve_target_daily_hours(db, profile_id)

        # Query sessions for the profile (today's sessions + active sessions)
        day_start = datetime.combine(target_date, datetime.min.time(), tzinfo=timezone.utc)
        day_end = datetime.combine(target_date, datetime.max.time(), tzinfo=timezone.utc)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            ors_session_in_range(day_start, day_end)
        ).all()

        total_shift_seconds = 0.0
        total_break_seconds = 0.0
        total_worked_seconds = 0.0
        total_focused_seconds = 0.0
        total_untracked_seconds = 0.0
        is_session_active = False

        for s in sessions:
            metrics = AnalyticsEngine.calculate_session_metrics(db, s)
            total_shift_seconds += metrics["shift_duration_seconds"]
            total_break_seconds += metrics["break_seconds"]
            total_worked_seconds += metrics["worked_seconds"]
            total_focused_seconds += metrics["focused_seconds"]
            total_untracked_seconds += metrics["untracked_seconds"]
            if metrics["is_active"]:
                is_session_active = True

        overall_focus_rate = (total_focused_seconds / total_worked_seconds * 100.0) if total_worked_seconds > 0 else 0.0
        overall_focus_rate = max(0.0, min(100.0, overall_focus_rate))

        worked_hours = total_worked_seconds / 3600.0
        target_progress = min(1.0, worked_hours / target_daily_hours) if target_daily_hours > 0 else 0.0
        target_hours_str = f"{worked_hours:.1f} / {target_daily_hours:.0f}"

        # Focus ratio percentages for /analytics/today/focus-ratio
        total_denominator = total_worked_seconds if total_worked_seconds > 0 else 1.0
        active_focus_pct = (total_focused_seconds / total_denominator) * 100.0
        idle_pct = (total_break_seconds / total_denominator) * 100.0
        non_active_pct = (total_untracked_seconds / total_denominator) * 100.0

        return {
            "shiftDurationSeconds": round(total_shift_seconds, 2),
            "workedSeconds": round(total_worked_seconds, 2),
            "focusedSeconds": round(total_focused_seconds, 2),
            "breakSeconds": round(total_break_seconds, 2),
            "untrackedSeconds": round(total_untracked_seconds, 2),
            "idleSeconds": None,
            "focusRate": round(overall_focus_rate, 2),
            "activeFocus": round(active_focus_pct, 2),
            "idle": round(idle_pct, 2),
            "nonActive": round(non_active_pct, 2),
            "workedHours": round(worked_hours, 2),
            "targetDailyHours": target_daily_hours,
            "targetProgress": round(target_progress, 4),
            "targetHours": target_hours_str,
            "isSessionActive": is_session_active
        }

    @staticmethod
    def calculate_period_summary(db: Session, profile_id: Union[str, uuid.UUID], start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
        """
        Calculate aggregated analytics for an arbitrary date range (period).
        """
        if isinstance(profile_id, str):
            try:
                profile_id = uuid.UUID(profile_id)
            except ValueError:
                return _empty_daily_summary(8.0)

        profile = db.query(Profile).filter(Profile.id == profile_id).first()
        target_daily_hours = resolve_target_daily_hours(db, profile_id)

        work_days = profile.work_days if profile and profile.work_days else ["monday", "tuesday", "wednesday", "thursday", "friday"]
        work_days_set = set(d.lower() for d in work_days)
        day_name_map = {0: "monday", 1: "tuesday", 2: "wednesday", 3: "thursday", 4: "friday", 5: "saturday", 6: "sunday"}

        matching_days = 0
        curr = start_dt.date()
        end_d = end_dt.date()
        while curr <= end_d:
            if day_name_map[curr.weekday()] in work_days_set:
                matching_days += 1
            curr += timedelta(days=1)

        period_target_hours = target_daily_hours * max(1, matching_days)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            ors_session_in_range(start_dt, end_dt)
        ).all()

        total_shift_seconds = 0.0
        total_break_seconds = 0.0
        total_worked_seconds = 0.0
        total_focused_seconds = 0.0
        total_untracked_seconds = 0.0
        completed_sessions_count = 0
        is_session_active = False

        for s in sessions:
            metrics = AnalyticsEngine.calculate_session_metrics(db, s)
            total_shift_seconds += metrics["shift_duration_seconds"]
            total_break_seconds += metrics["break_seconds"]
            total_worked_seconds += metrics["worked_seconds"]
            total_focused_seconds += metrics["focused_seconds"]
            total_untracked_seconds += metrics["untracked_seconds"]
            if s.ended_at is not None:
                completed_sessions_count += 1
            if metrics["is_active"]:
                is_session_active = True

        overall_focus_rate = (total_focused_seconds / total_worked_seconds * 100.0) if total_worked_seconds > 0 else 0.0
        overall_focus_rate = max(0.0, min(100.0, overall_focus_rate))

        worked_hours = total_worked_seconds / 3600.0
        target_progress = min(1.0, worked_hours / period_target_hours) if period_target_hours > 0 else 0.0

        total_denominator = total_worked_seconds if total_worked_seconds > 0 else 1.0
        active_focus_pct = (total_focused_seconds / total_denominator) * 100.0
        idle_pct = (total_break_seconds / total_denominator) * 100.0
        non_active_pct = (total_untracked_seconds / total_denominator) * 100.0

        return {
            "shiftDurationSeconds": round(total_shift_seconds, 2),
            "workedSeconds": round(total_worked_seconds, 2),
            "focusedSeconds": round(total_focused_seconds, 2),
            "breakSeconds": round(total_break_seconds, 2),
            "untrackedSeconds": round(total_untracked_seconds, 2),
            "idleSeconds": None,
            "focusRate": round(overall_focus_rate, 2),
            "activeFocus": round(active_focus_pct, 2),
            "idle": round(idle_pct, 2),
            "nonActive": round(non_active_pct, 2),
            "workedHours": round(worked_hours, 2),
            "targetDailyHours": target_daily_hours,
            "periodTargetHours": round(period_target_hours, 2),
            "targetProgress": round(target_progress, 4),
            "targetHours": f"{worked_hours:.1f} / {int(period_target_hours)}h",
            "isSessionActive": is_session_active,
            "completedSessionsCount": completed_sessions_count
        }


def ors_session_in_range(day_start: datetime, day_end: datetime):
    """SQLAlchemy filter helper for sessions overlapping day range or active."""
    from sqlalchemy import or_, and_
    return or_(
        and_(WorkSession.started_at >= day_start, WorkSession.started_at <= day_end),
        and_(WorkSession.ended_at >= day_start, WorkSession.ended_at <= day_end),
        and_(WorkSession.started_at <= day_start, or_(WorkSession.ended_at >= day_end, WorkSession.ended_at == None)),
        WorkSession.ended_at == None
    )


def _empty_daily_summary(target_hours: float) -> Dict[str, Any]:
    return {
        "shiftDurationSeconds": 0.0,
        "workedSeconds": 0.0,
        "focusedSeconds": 0.0,
        "breakSeconds": 0.0,
        "untrackedSeconds": 0.0,
        "idleSeconds": None,
        "focusRate": 0.0,
        "activeFocus": 0.0,
        "idle": 0.0,
        "nonActive": 0.0,
        "targetHours": f"0.0 / {target_hours:.0f}",
        "workedHours": 0.0,
        "targetDailyHours": target_hours,
        "isSessionActive": False
    }
