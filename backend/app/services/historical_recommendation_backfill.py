"""
Historical Recommendation Reconstruction Service & Backfill Utility.
Reconstructs missing historical recommendations for thesis demo employees using IntelliBreak's
actual recommendation pipeline and historical session/wellbeing context.
"""

import uuid
import logging
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import text

from ..models import (
    User, Profile, WorkSession, Break, Task, SessionWellbeingCheckin,
    RecommendationFeedback, UserSettings
)
from ..analytics_utils import calculate_unique_task_seconds
from .behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from .recommendation_service import _score_candidate, _generate_reason

logger = logging.getLogger(__name__)

THESIS_DEMO_EMAILS = [
    f"thesis.employee{str(i).zfill(2)}@intellibreak.local"
    for i in range(1, 21)
]

def extract_historical_session_features(db: Session, profile: Profile, session: WorkSession) -> Dict[str, Any]:
    """Extract historical features for a specific completed work session (temporal-safe)."""
    session_start = session.started_at
    session_end = session.ended_at or session_start + timedelta(hours=8)

    # Last break prior to or during session
    last_break = db.query(Break).join(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        Break.ended_at <= session_start
    ).order_by(Break.ended_at.desc()).first()

    last_break_duration = 0.0
    if last_break and last_break.started_at and last_break.ended_at:
        last_break_duration = (last_break.ended_at - last_break.started_at).total_seconds() / 60.0

    # Tasks for this session
    session_tasks = db.query(Task).filter(
        Task.work_session_id == session.id
    ).all()
    completed = sum(1 for t in session_tasks if t.status == "DONE")
    total = len(session_tasks)
    completion_rate = completed / total if total > 0 else 0.0

    # User settings
    settings = db.query(UserSettings).filter(UserSettings.user_id == profile.user_id).first()
    pref_interval = settings.break_interval_minutes if settings else 30
    pref_duration = settings.break_duration_minutes if settings else 10

    session_length_minutes = (session_end - session_start).total_seconds() / 60.0

    time_since_break = 9999
    if last_break and last_break.ended_at:
        time_since_break = (session_start - last_break.ended_at).total_seconds() / 60.0

    # Focus rate for this historical session
    current_focus_rate = None
    finished_tasks = [t for t in session_tasks if t.actual_minutes is not None]
    active_tasks = [t for t in session_tasks if t.status == 'IN_PROGRESS' and t.started_at is not None]
    all_tasks = {t.id: t for t in (finished_tasks + active_tasks)}.values()

    session_breaks = db.query(Break).filter(
        Break.work_session_id == session.id,
        Break.ended_at.isnot(None)
    ).all()

    total_task_seconds = calculate_unique_task_seconds(all_tasks, session_start, session_end, session_breaks)
    total_work_seconds = (session_end - session_start).total_seconds()
    if total_work_seconds > 0:
        current_focus_rate = (total_task_seconds / total_work_seconds * 100)

    # Historical wellbeing check-in association
    checkin = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.work_session_id == session.id
    ).first()

    if not checkin and session.ended_at:
        two_hours_after = session.ended_at + timedelta(hours=2)
        checkin = db.query(SessionWellbeingCheckin).filter(
            SessionWellbeingCheckin.user_id == profile.user_id,
            SessionWellbeingCheckin.created_at >= session.started_at,
            SessionWellbeingCheckin.created_at <= two_hours_after
        ).order_by(SessionWellbeingCheckin.created_at).first()

    wellbeing_features = {
        "wellbeing_overall": None,
        "wellbeing_fatigue": None,
        "wellbeing_workload": None,
        "wellbeing_focus": None,
        "wellbeing_recovery": None,
        "wellbeing_stress_count": 0
    }

    if checkin:
        overall_wellbeing = checkin.overall_wellbeing
        mental_fatigue = checkin.mental_fatigue
        workload_manageability = checkin.workload_manageability
        perceived_focus = checkin.perceived_focus
        break_recovery = checkin.break_recovery
        stress_factors = checkin.stress_factors

        wellbeing_features["wellbeing_overall"] = (overall_wellbeing - 1) / 4.0 if overall_wellbeing is not None else None
        wellbeing_features["wellbeing_fatigue"] = (mental_fatigue - 1) / 4.0 if mental_fatigue is not None else None
        wellbeing_features["wellbeing_workload"] = (workload_manageability - 1) / 4.0 if workload_manageability is not None else None
        wellbeing_features["wellbeing_focus"] = (perceived_focus - 1) / 4.0 if perceived_focus is not None else None
        wellbeing_features["wellbeing_recovery"] = (break_recovery - 1) / 4.0 if break_recovery is not None else None
        wellbeing_features["wellbeing_stress_count"] = len(stress_factors) if stress_factors else 0

    personal_baselines = calculate_personal_baselines(db, profile.id, days=30)
    detected_patterns = detect_behavioral_patterns(db, profile.id)

    features = {
        "profile_id": str(profile.id),
        "user_id": str(profile.user_id),
        "session_length_minutes": round(session_length_minutes, 1),
        "time_since_last_break_minutes": round(time_since_break, 1) if time_since_break < 9999 else None,
        "recent_task_completion_rate": round(completion_rate, 2),
        "recent_task_count": total,
        "preferred_interval_minutes": pref_interval,
        "preferred_duration_minutes": pref_duration,
        "has_active_session": False,
        "has_active_break": False,
        "last_break_duration_minutes": round(last_break_duration, 1),
        "cold_start": (total < 2),
        "current_focus_rate": round(current_focus_rate, 2) if current_focus_rate is not None else None,
        "personal_baselines": personal_baselines,
        "detected_patterns": detected_patterns,
        "wellbeing_overall": wellbeing_features.get("wellbeing_overall"),
        "wellbeing_fatigue": wellbeing_features.get("wellbeing_fatigue"),
        "wellbeing_workload": wellbeing_features.get("wellbeing_workload"),
        "wellbeing_focus": wellbeing_features.get("wellbeing_focus"),
        "wellbeing_recovery": wellbeing_features.get("wellbeing_recovery"),
        "wellbeing_stress_count": wellbeing_features.get("wellbeing_stress_count"),
        "feature_snapshot": {
            "session_length": round(session_length_minutes, 1),
            "time_since_break": round(time_since_break, 1) if time_since_break < 9999 else None,
            "completion_rate": round(completion_rate, 2),
            "current_focus_rate": round(current_focus_rate, 2) if current_focus_rate is not None else None,
            "wellbeing_overall": wellbeing_features.get("wellbeing_overall"),
            "wellbeing_fatigue": wellbeing_features.get("wellbeing_fatigue"),
            "wellbeing_workload": wellbeing_features.get("wellbeing_workload"),
            "wellbeing_focus": wellbeing_features.get("wellbeing_focus"),
            "wellbeing_recovery": wellbeing_features.get("wellbeing_recovery"),
            "wellbeing_stress_count": wellbeing_features.get("wellbeing_stress_count"),
        }
    }
    return features


def reconstruct_historical_recommendations_for_session(db: Session, profile: Profile, session: WorkSession) -> Optional[RecommendationFeedback]:
    """Reconstruct a recommendation for a single historical session using the heuristic recommendation fallback engine."""
    # Strict uniqueness check using work_session_id
    existing = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.work_session_id == session.id
    ).first()
    if existing:
        return None

    features = extract_historical_session_features(db, profile, session)
    candidate_types = ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]

    scores = {}
    for c in candidate_types:
        scores[c] = _score_candidate(c, features)

    if not scores:
        return None

    top_candidate = max(scores, key=scores.get)
    score = scores[top_candidate]
    reason = _generate_reason(top_candidate, features)

    recommendation_id = uuid.uuid4()
    rec_timestamp = session.started_at + timedelta(minutes=min(30, (session.ended_at - session.started_at).total_seconds() / 120))

    feedback = RecommendationFeedback(
        recommendation_id=recommendation_id,
        user_id=profile.user_id,
        model_version="historical-reconstruction-v1",
        provenance="historical_reconstruction",
        feature_schema_version="v2-wellbeing",
        recommendation_type=top_candidate,
        recommendation_score=score,
        context_features=features.get("feature_snapshot") or {},
        timestamp=rec_timestamp,
        user_action=None,  # No fabricated user actions or feedback
        reason=reason,
        work_session_id=session.id
    )

    db.add(feedback)
    return feedback


def run_historical_backfill(db: Session, dry_run: bool = True) -> Dict[str, Any]:
    """
    Run controlled historical recommendation backfill for the 20 primary thesis demo employees.
    Target Scope: Explicit allowlist (thesis.employee01 through thesis.employee20, Role = EMPLOYEE).
    Transaction Safety: Single transaction with explicit rollback on error.
    """
    stats = {
        "employees_inspected": 0,
        "historical_sessions_inspected": 0,
        "sessions_with_existing_recommendations": 0,
        "sessions_eligible": 0,
        "sessions_reconstructed_successfully": 0,
        "sessions_skipped_insufficient_data": 0,
        "errors": 0
    }

    # Strict employee filtering using explicit allowlist of the 20 thesis demo employee emails
    thesis_demo_profiles = db.query(Profile).join(User, Profile.user_id == User.id).filter(
        Profile.is_test_data == True,
        User.role == 'EMPLOYEE',
        User.email.in_(THESIS_DEMO_EMAILS)
    ).all()

    stats["employees_inspected"] = len(thesis_demo_profiles)

    try:
        for profile in thesis_demo_profiles:
            # Explicit WorkSession query: restricted strictly to current profile.id AND ended_at IS NOT NULL
            sessions = db.query(WorkSession).filter(
                WorkSession.profile_id == profile.id,
                WorkSession.ended_at.isnot(None)
            ).all()

            for session in sessions:
                stats["historical_sessions_inspected"] += 1

                # Check existing recommendation (strict uniqueness via work_session_id)
                existing = db.query(RecommendationFeedback).filter(
                    RecommendationFeedback.work_session_id == session.id
                ).first()

                if existing:
                    stats["sessions_with_existing_recommendations"] += 1
                    continue

                stats["sessions_eligible"] += 1

                if not dry_run:
                    feedback = reconstruct_historical_recommendations_for_session(db, profile, session)
                    if feedback:
                        stats["sessions_reconstructed_successfully"] += 1
                    else:
                        stats["sessions_skipped_insufficient_data"] += 1
                else:
                    # Dry run mode: read-only simulation
                    stats["sessions_reconstructed_successfully"] += 1

        if not dry_run:
            db.commit()
    except Exception as e:
        logger.error(f"Backfill execution failed, rolling back transaction: {e}")
        db.rollback()
        raise e

    return stats
