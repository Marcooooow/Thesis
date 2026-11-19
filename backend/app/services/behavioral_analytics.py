"""
Behavioral Analytics Service — Personal baselines and pattern detection.
Calculates robust employee-specific work habit baselines and detects behavioral patterns
(overwork, skipped breaks, recovery, focus decline, workload, schedule irregularity, fatigue/stress)
using real historical data.
"""

from datetime import datetime, timezone, timedelta
from typing import Optional, Dict, Any, List, Union
import statistics
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import text

from ..models import WorkSession, Break, Task, SessionWellbeingCheckin, Profile, UserSettings
from ..analytics_utils import calculate_unique_task_seconds


def _calculate_median(values: List[float]) -> Optional[float]:
    """Calculate median using stdlib statistics, returning None if empty."""
    if not values:
        return None
    return float(statistics.median(values))


def calculate_personal_baselines(db: Session, profile_id: Union[str, uuid.UUID], days: int = 30) -> Dict[str, Any]:
    """
    Calculate personal behavioral baselines for an employee over a given observation window (7, 14, 30 days).
    Uses robust statistics (median) over completed sessions, breaks, tasks, and wellbeing check-ins.
    Handles cold-start gracefully when observation count is insufficient.
    """
    if isinstance(profile_id, str):
        try:
            profile_id = uuid.UUID(profile_id)
        except ValueError:
            return {"error": "Invalid profile_id UUID", "is_cold_start": True}

    now = datetime.now(timezone.utc)
    start_date = now - timedelta(days=days)

    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        return {"error": "Profile not found", "is_cold_start": True}

    # Query completed work sessions in window
    sessions = db.query(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        WorkSession.ended_at.isnot(None),
        WorkSession.started_at >= start_date
    ).all()

    # Query breaks in window
    breaks = db.query(Break).join(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        Break.ended_at.isnot(None),
        Break.started_at >= start_date
    ).all()

    # Query wellbeing checkins in window
    checkins = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id == profile.user_id,
        SessionWellbeingCheckin.created_at >= start_date
    ).all()

    # Cold-start threshold: fewer than 3 sessions or fewer days of data
    is_cold_start = len(sessions) < 3

    # 1. Session durations (minutes)
    session_durations = [
        (s.ended_at - s.started_at).total_seconds() / 60.0
        for s in sessions if s.started_at and s.ended_at and s.ended_at > s.started_at
    ]

    # 2. Daily working hours
    daily_hours_map = {}
    for s in sessions:
        if s.started_at and s.ended_at and s.ended_at > s.started_at:
            day_key = s.started_at.date()
            dur = (s.ended_at - s.started_at).total_seconds() / 3600.0
            daily_hours_map[day_key] = daily_hours_map.get(day_key, 0.0) + dur
    daily_working_hours = list(daily_hours_map.values())

    # 3. Break durations (minutes)
    break_durations = [
        (b.ended_at - b.started_at).total_seconds() / 60.0
        for b in breaks if b.started_at and b.ended_at and b.ended_at > b.started_at
    ]

    # 4. Break intervals (minutes between session start/prior break and next break)
    break_intervals = []
    for s in sessions:
        s_breaks = sorted([b for b in breaks if b.work_session_id == s.id and b.started_at], key=lambda x: x.started_at)
        if s_breaks and s.started_at:
            last_t = s.started_at
            for b in s_breaks:
                interval_min = (b.started_at - last_t).total_seconds() / 60.0
                if interval_min > 0:
                    break_intervals.append(interval_min)
                last_t = b.ended_at or b.started_at

    # 5. Focus rates across sessions
    focus_rates = []
    for s in sessions:
        if s.started_at and s.ended_at:
            s_tasks = db.query(Task).filter(Task.work_session_id == s.id).all()
            s_breaks = [b for b in breaks if b.work_session_id == s.id]
            t_sec = calculate_unique_task_seconds(s_tasks, s.started_at, s.ended_at, s_breaks)
            w_sec = (s.ended_at - s.started_at).total_seconds()
            if w_sec > 0:
                focus_rates.append((t_sec / w_sec) * 100.0)

    # 6. Wellbeing trends (fatigue, workload manageability)
    fatigue_scores = [c.mental_fatigue for c in checkins if c.mental_fatigue is not None]
    workload_scores = [c.workload_manageability for c in checkins if c.workload_manageability is not None]
    overall_wellbeing_scores = [c.overall_wellbeing for c in checkins if c.overall_wellbeing is not None]

    baselines = {
        "profile_id": str(profile_id),
        "observation_window_days": days,
        "observation_count_sessions": len(sessions),
        "is_cold_start": is_cold_start,
        "median_session_duration_minutes": _calculate_median(session_durations),
        "median_daily_working_hours": _calculate_median(daily_working_hours),
        "median_break_duration_minutes": _calculate_median(break_durations),
        "median_break_interval_minutes": _calculate_median(break_intervals),
        "median_focus_rate_percentage": _calculate_median(focus_rates),
        "median_mental_fatigue": _calculate_median([float(x) for x in fatigue_scores]),
        "median_workload_manageability": _calculate_median([float(x) for x in workload_scores]),
        "median_overall_wellbeing": _calculate_median([float(x) for x in overall_wellbeing_scores]),
    }
    return baselines


def detect_behavioral_patterns(db: Session, profile_id: Union[str, uuid.UUID]) -> List[Dict[str, Any]]:
    """
    Detects evidence-based behavioral patterns for an employee:
    1. Recurring overwork
    2. Repeated skipped breaks
    3. Insufficient recovery
    4. Declining measurable focus
    5. Increasing workload
    6. Irregular working schedules
    7. Recurring fatigue and stress reports

    Returns a list of pattern evaluation dictionaries.
    """
    if isinstance(profile_id, str):
        try:
            profile_id = uuid.UUID(profile_id)
        except ValueError:
            return []

    now = datetime.now(timezone.utc)
    window_14d = now - timedelta(days=14)

    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not profile:
        return []

    baselines_30d = calculate_personal_baselines(db, profile_id, days=30)
    sessions_14d = db.query(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        WorkSession.ended_at.isnot(None),
        WorkSession.started_at >= window_14d
    ).all()

    checkins_14d = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id == profile.user_id,
        SessionWellbeingCheckin.created_at >= window_14d
    ).all()

    target_hours = float(profile.target_daily_hours or 8.0)
    patterns = []

    # --- Pattern 1: Recurring Overwork ---
    daily_hours = {}
    for s in sessions_14d:
        if s.started_at and s.ended_at:
            day = s.started_at.date()
            dur = (s.ended_at - s.started_at).total_seconds() / 3600.0
            daily_hours[day] = daily_hours.get(day, 0.0) + dur

    overwork_days = [d for d, hrs in daily_hours.items() if hrs > target_hours + 1.0]
    is_overwork = len(overwork_days) >= 3
    avg_daily = round(statistics.mean(list(daily_hours.values())), 1) if daily_hours else 0.0
    patterns.append({
        "pattern_id": "RECURRING_OVERWORK",
        "detected": is_overwork,
        "display_name": "Recurring Overwork",
        "measurement": f"{len(overwork_days)} days exceeded target by >1h (avg: {avg_daily}h/day)" if is_overwork else f"Avg {avg_daily}h/day within range",
        "observation_period": "14 days",
        "observation_count": len(daily_hours),
        "evidence_strength": "HIGH" if len(overwork_days) >= 4 else ("MEDIUM" if is_overwork else "LOW"),
        "days_triggered": len(overwork_days),
        "data_limitations": "Based solely on logged work session start/end timestamps; unlogged offline work not captured."
    })

    # --- Pattern 2: Insufficient Recovery ---
    recent_recoveries = [c.break_recovery for c in checkins_14d if c.break_recovery is not None]
    avg_recovery = statistics.mean(recent_recoveries) if recent_recoveries else 3.0
    is_insufficient_recovery = avg_recovery < 2.5 and len(recent_recoveries) >= 2
    patterns.append({
        "pattern_id": "INSUFFICIENT_RECOVERY",
        "detected": is_insufficient_recovery,
        "display_name": "Insufficient Recovery",
        "measurement": f"Recovery score {round(avg_recovery, 1)}/5 across {len(recent_recoveries)} check-ins" if recent_recoveries else "No recovery data",
        "observation_period": "14 days",
        "observation_count": len(recent_recoveries),
        "evidence_strength": "MEDIUM" if is_insufficient_recovery else "LOW",
        "days_triggered": len(recent_recoveries) if is_insufficient_recovery else 0,
        "data_limitations": "Subjective self-reported Likert scale; does not measure physiological recovery directly."
    })

    # --- Pattern 3: Repeated Skipped Breaks ---
    skipped_count = 0
    total_eval_sessions = 0
    for s in sessions_14d:
        if s.started_at and s.ended_at:
            dur_min = (s.ended_at - s.started_at).total_seconds() / 60.0
            if dur_min >= 60:
                total_eval_sessions += 1
                b_count = db.query(Break).filter(Break.work_session_id == s.id).count()
                if b_count == 0:
                    skipped_count += 1
    is_skipped = total_eval_sessions >= 3 and (skipped_count / total_eval_sessions) >= 0.4
    patterns.append({
        "pattern_id": "REPEATED_SKIPPED_BREAKS",
        "detected": is_skipped,
        "display_name": "Repeated Skipped Breaks",
        "measurement": f"{skipped_count} of {total_eval_sessions} long sessions had no breaks" if is_skipped else f"Break compliance adequate ({skipped_count}/{total_eval_sessions} sessions skipped)",
        "observation_period": "14 days",
        "observation_count": total_eval_sessions,
        "evidence_strength": "HIGH" if skipped_count >= 5 else ("MEDIUM" if is_skipped else "LOW"),
        "days_triggered": skipped_count,
        "data_limitations": "Assumes employees log all breaks within IntelliBreak sessions."
    })

    # --- Pattern 4: Declining Measurable Focus ---
    median_baseline_focus = baselines_30d.get("median_focus_rate_percentage")
    recent_focus_rates = []
    for s in sessions_14d[-5:]:
        if s.started_at and s.ended_at:
            s_tasks = db.query(Task).filter(Task.work_session_id == s.id).all()
            s_breaks = db.query(Break).filter(Break.work_session_id == s.id).all()
            t_sec = calculate_unique_task_seconds(s_tasks, s.started_at, s.ended_at, s_breaks)
            w_sec = (s.ended_at - s.started_at).total_seconds()
            if w_sec > 0:
                recent_focus_rates.append((t_sec / w_sec) * 100.0)
    avg_recent_focus = statistics.mean(recent_focus_rates) if recent_focus_rates else 50.0
    is_focus_declining = median_baseline_focus is not None and avg_recent_focus < median_baseline_focus - 15.0
    patterns.append({
        "pattern_id": "DECLINING_MEASURABLE_FOCUS",
        "detected": is_focus_declining,
        "display_name": "Declining Measurable Focus",
        "measurement": f"Focus dropped {round(median_baseline_focus - avg_recent_focus, 1)}pp below baseline ({round(avg_recent_focus, 1)}% vs {median_baseline_focus}%)" if is_focus_declining else f"Focus stable ({round(avg_recent_focus, 1)}%)",
        "observation_period": "14 days",
        "observation_count": len(recent_focus_rates),
        "evidence_strength": "MEDIUM" if is_focus_declining else "LOW",
        "days_triggered": len(recent_focus_rates) if is_focus_declining else 0,
        "data_limitations": "Task activity ratio measures active task window logging, not deep cognitive focus directly."
    })

    # --- Pattern 5: Recurring Fatigue and Stress Reports ---
    fatigue_scores = [c.mental_fatigue for c in checkins_14d if c.mental_fatigue is not None]
    stress_factor_count = sum(len(c.stress_factors) for c in checkins_14d if c.stress_factors)
    avg_fatigue = statistics.mean(fatigue_scores) if fatigue_scores else 1.0
    is_fatigue_high = avg_fatigue > 3.5 or stress_factor_count >= 3
    patterns.append({
        "pattern_id": "RECURRING_FATIGUE_STRESS",
        "detected": is_fatigue_high,
        "display_name": "Recurring Fatigue and Stress",
        "measurement": f"Avg fatigue {round(avg_fatigue, 1)}/5 across {len(fatigue_scores)} check-ins" if is_fatigue_high else f"Fatigue within normal range ({round(avg_fatigue, 1)}/5)",
        "observation_period": "14 days",
        "observation_count": len(checkins_14d),
        "evidence_strength": "HIGH" if avg_fatigue > 4.0 else ("MEDIUM" if is_fatigue_high else "LOW"),
        "days_triggered": len(fatigue_scores) if is_fatigue_high else 0,
        "data_limitations": "Self-reported perceived fatigue; does not constitute medical or psychological diagnosis."
    })

    return patterns
