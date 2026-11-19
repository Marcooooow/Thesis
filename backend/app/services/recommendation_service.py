"""
Recommendation Service — Candidate-based recommendation engine.

ARCHITECTURE (per approved design):
Existing IntelliBreak data (users, profiles, work_sessions, breaks, tasks)
→ feature extraction (session length, time since last break, task completion rate, behavioral baselines, pattern detection)
→ candidate generation (break types: SHORT_BREAK, WALK, HYDRATE, STRETCH, LUNCH)
→ candidate-specific scoring (heuristic score based on extracted features + behavioral pattern adjustments)
→ ranking (sort by score)
→ recommendation (serve top; store in recommendation_feedback with recommendation_id)
→ feedback (user_action NULL initially; updated when user responds)

IMPORTANT DISTINCTIONS:
- This is NOT the work-pattern decline prediction from ml_service.py.
- The existing ml_service.py probability may be used as an input feature if appropriate,
  but it is NOT by itself the recommendation model / recommendation score.
- The recommendation_score is a ranking score, not a calibrated confidence.
- Cold-start path (insufficient labeled data) is explicitly separated and labeled.
- No fake data, no fabricated metrics, no fabricated model performance.
- ML integration: Optional enhancement to heuristic ranking, with explicit fallback.
"""

import os
import statistics
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text
import uuid
import numpy as np

from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import (
    User, Profile, WorkSession, Break, Task, UserSettings,
    RecommendationFeedback, MLModel
)
from ..analytics_utils import calculate_unique_task_seconds
from .behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from .wlb_analysis_service import WLBAnalysisService, wlb_recommendation_uuid
from .feature_schema import (
    V2_NUMERIC_FEATURE_KEYS,
    V2_ALL_FEATURE_KEYS,
    V1_NUMERIC_FEATURE_KEYS,
    V1_ALL_FEATURE_KEYS,
    build_feature_vector,
    FEATURE_SCHEMA_VERSION
)
from .cache_service import analytics_cache

router = APIRouter(prefix="/recommend", tags=["recommend"])

# Candidate activities available across 5 workplace wellness categories
RECOMMENDATION_TAXONOMY = {
    # A. Break and Recovery
    "SHORT_BREAK": {"category": "Break and Recovery", "duration": 5},
    "WALK": {"category": "Break and Recovery", "duration": 15},
    "HYDRATE": {"category": "Break and Recovery", "duration": 2},
    "STRETCH": {"category": "Break and Recovery", "duration": 5},
    "LUNCH": {"category": "Break and Recovery", "duration": 30},
    "SCREEN_FREE_PAUSE": {"category": "Break and Recovery", "duration": 10},
    "RECOVERY_BREAK": {"category": "Break and Recovery", "duration": 15},

    # B. Ergonomics and Physical Comfort
    "POSTURE_ADJUSTMENT": {"category": "Ergonomics and Physical Comfort", "duration": 2},
    "WRIST_RELAXATION": {"category": "Ergonomics and Physical Comfort", "duration": 3},
    "ERGONOMICS_REVIEW": {"category": "Ergonomics and Physical Comfort", "duration": 10},
    "SIT_STAND_VARIATION": {"category": "Ergonomics and Physical Comfort", "duration": 5},

    # C. Focus and Cognitive Recovery
    "FOCUS_INTERVAL_PLANNING": {"category": "Focus and Cognitive Recovery", "duration": 5},
    "TASK_BATCHING": {"category": "Focus and Cognitive Recovery", "duration": 10},
    "REDUCE_CONTEXT_SWITCHING": {"category": "Focus and Cognitive Recovery", "duration": 5},
    "COGNITIVE_RECOVERY": {"category": "Focus and Cognitive Recovery", "duration": 10},
    "LOWER_INTENSITY_TASK": {"category": "Focus and Cognitive Recovery", "duration": 15},

    # D. Workload and Time Management
    "TASK_PRIORITIZATION": {"category": "Workload and Time Management", "duration": 10},
    "MILESTONE_BREAKDOWN": {"category": "Workload and Time Management", "duration": 10},
    "DEADLINE_REVIEW": {"category": "Workload and Time Management", "duration": 10},
    "WORKLOAD_REVIEW": {"category": "Workload and Time Management", "duration": 15},
    "WORKLOAD_DISTRIBUTION": {"category": "Workload and Time Management", "duration": 15},

    # E. Sustainable Work Habits and Work-Life Balance
    "WLB_HOURS_REVIEW": {"category": "Sustainable Work Habits and Work-Life Balance", "duration": 15},
    "SHIFT_ENDING_ROUTINE": {"category": "Sustainable Work Habits and Work-Life Balance", "duration": 10},
    "RECOVERY_PLANNING": {"category": "Sustainable Work Habits and Work-Life Balance", "duration": 10},
    "WELLBEING_CHECKIN": {"category": "Sustainable Work Habits and Work-Life Balance", "duration": 3},
    "ROUTINE_MAINTENANCE": {"category": "Sustainable Work Habits and Work-Life Balance", "duration": 5},
}

CANDIDATE_TYPES = list(RECOMMENDATION_TAXONOMY.keys())

# Explicit cold-start baseline: when insufficient real labeled data exists
COLD_START_LABEL = "cold-start-baseline"


def _extract_features(db: Session, profile_id: uuid.UUID) -> Dict[str, Any]:
    """Extract real features and behavioral analytics from existing IntelliBreak data."""
    now = datetime.now(timezone.utc)
    profile = db.query(Profile).filter(Profile.id == profile_id).first()

    # Active session check
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        WorkSession.ended_at == None
    ).first()

    # Last break (if any)
    last_break = db.query(Break).join(WorkSession).filter(
        WorkSession.profile_id == profile_id
    ).order_by(Break.ended_at.desc()).first()

    # Active break check
    active_break = db.query(Break).join(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        WorkSession.ended_at == None,
        Break.ended_at == None
    ).first()

    last_break_duration = 0.0
    if last_break and last_break.started_at and last_break.ended_at:
        last_break_duration = (last_break.ended_at - last_break.started_at).total_seconds() / 60.0

    # Recent task events (last 60 minutes) — REAL data only
    one_hour_ago = now - timedelta(hours=1)
    recent_tasks = db.query(Task).filter(
        Task.profile_id == profile_id,
        Task.created_at >= one_hour_ago
    ).all()
    completed = sum(1 for t in recent_tasks if t.status == "DONE")
    total = len(recent_tasks)
    completion_rate = completed / total if total > 0 else 0.0

    # User preferences (real settings)
    settings = db.query(UserSettings).filter(UserSettings.user_id == profile.user_id if profile else False).first()
    pref_interval = settings.break_interval_minutes if settings else 30
    pref_duration = settings.break_duration_minutes if settings else 10

    # Session duration if active
    session_length_minutes = 0
    if active_session and active_session.started_at:
        session_length_minutes = (now - active_session.started_at).total_seconds() / 60.0

    # Time since last break (minutes)
    time_since_break = 9999
    if last_break and last_break.ended_at:
        time_since_break = (now - last_break.ended_at).total_seconds() / 60.0

    # Focus Rate for the active session (if exists)
    current_focus_rate = None
    if active_session and active_session.started_at:
        session_start = active_session.started_at
        session_end = active_session.ended_at or now

        # Get finished tasks in this session (with actual_minutes)
        finished_tasks = db.query(Task).filter(
            Task.work_session_id == active_session.id,
            Task.actual_minutes.isnot(None)
        ).all()
        # Get active tasks in this session (without actual_minutes but started)
        active_tasks = db.query(Task).filter(
            Task.work_session_id == active_session.id,
            Task.status == 'IN_PROGRESS',
            Task.started_at.isnot(None)
        ).all()
        all_tasks = {t.id: t for t in (finished_tasks + active_tasks)}.values()

        # Get breaks for this session that have ended_at
        breaks = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.ended_at.isnot(None)
        ).all()

        total_task_seconds = calculate_unique_task_seconds(all_tasks, session_start, session_end, breaks)
        total_work_seconds = (session_end - session_start).total_seconds()

        if total_work_seconds > 0:
            current_focus_rate = (total_task_seconds / total_work_seconds * 100)

    # Extract wellbeing features using temporal-safe join
    wellbeing_features = _extract_wellbeing_features(db, profile.user_id, now)

    # Extract personal baselines and behavioral patterns (Sprint 2 integration)
    personal_baselines = calculate_personal_baselines(db, profile.id, days=30)
    detected_patterns = detect_behavioral_patterns(db, profile.id)

    # Feature snapshot for recommendation score and reason - CANONICAL V2 SCHEMA
    feature_snapshot = {
        "session_length": round(session_length_minutes, 1),
        "time_since_break": round(time_since_break, 1) if time_since_break < 9999 else None,
        "completion_rate": round(completion_rate, 2),
        "wellbeing_overall": wellbeing_features.get("wellbeing_overall"),
        "wellbeing_fatigue": wellbeing_features.get("wellbeing_fatigue"),
        "wellbeing_workload": wellbeing_features.get("wellbeing_workload"),
        "wellbeing_focus": wellbeing_features.get("wellbeing_focus"),
        "wellbeing_recovery": wellbeing_features.get("wellbeing_recovery"),
        "wellbeing_stress": wellbeing_features.get("wellbeing_stress_count"),
        # Observability flag: True = check-in row found at generation time; False = no eligible check-in
        "wellbeing_checkin_observed": wellbeing_features.get("wellbeing_checkin_observed", False),
    }

    # Full features dict for heuristic scoring (includes extras)
    features = {
        "profile_id": str(profile_id),
        "user_id": str(profile.user_id) if profile else None,
        "session_length_minutes": round(session_length_minutes, 1),
        "time_since_last_break_minutes": round(time_since_break, 1) if time_since_break < 9999 else None,
        "recent_task_completion_rate": round(completion_rate, 2),
        "recent_task_count": total,
        "preferred_interval_minutes": pref_interval,
        "preferred_duration_minutes": pref_duration,
        "has_active_session": active_session is not None,
        "has_active_break": active_break is not None,
        "last_break_duration_minutes": round(last_break_duration, 1),
        "cold_start": (total < 2 or not active_session),
        "current_focus_rate": round(current_focus_rate, 2) if current_focus_rate is not None else None,
        "personal_baselines": personal_baselines,
        "detected_patterns": detected_patterns,
        # Wellbeing features (may be None if no eligible check-in)
        "wellbeing_overall": wellbeing_features.get("wellbeing_overall"),
        "wellbeing_fatigue": wellbeing_features.get("wellbeing_fatigue"),
        "wellbeing_workload": wellbeing_features.get("wellbeing_workload"),
        "wellbeing_focus": wellbeing_features.get("wellbeing_focus"),
        "wellbeing_recovery": wellbeing_features.get("wellbeing_recovery"),
        "wellbeing_stress_count": wellbeing_features.get("wellbeing_stress_count"),
        "feature_snapshot": feature_snapshot,
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
    }
    return features


def _extract_wellbeing_features(db: Session, user_id: uuid.UUID, generation_timestamp: datetime) -> Dict[str, Any]:
    """
    Extract wellbeing features using temporal-safe join.
    Returns the most recent eligible check-in's wellbeing data.
    All features may be None if no eligible check-in exists.
    """
    wellbeing_features = {
        "wellbeing_overall": None,
        "wellbeing_fatigue": None,
        "wellbeing_workload": None,
        "wellbeing_focus": None,
        "wellbeing_recovery": None,
        "wellbeing_stress_count": None,
        "wellbeing_checkin_observed": False,
    }

    # SQLite stores UUIDs without hyphens, so convert user_id to that format
    user_id_str = str(user_id).replace("-", "")

    stmt = text("""
        SELECT
            swc.overall_wellbeing,
            swc.mental_fatigue,
            swc.workload_manageability,
            swc.perceived_focus,
            swc.break_recovery,
            swc.stress_factors
        FROM work_sessions ws
        JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id
        WHERE
            swc.user_id = :user_id
            AND ws.ended_at IS NOT NULL
            AND ws.ended_at < :generation_timestamp
            AND swc.created_at <= :generation_timestamp
        ORDER BY ws.ended_at DESC
        LIMIT 1
    """)

    result = db.execute(stmt, {
        "user_id": user_id_str,
        "generation_timestamp": generation_timestamp
    }).fetchone()

    if result:
        overall_wellbeing, mental_fatigue, workload_manageability, perceived_focus, break_recovery, stress_factors = result

        wellbeing_features["wellbeing_checkin_observed"] = True
        wellbeing_features["wellbeing_overall"] = (overall_wellbeing - 1) / 4.0 if overall_wellbeing is not None else None
        wellbeing_features["wellbeing_fatigue"] = (mental_fatigue - 1) / 4.0 if mental_fatigue is not None else None
        wellbeing_features["wellbeing_workload"] = (workload_manageability - 1) / 4.0 if workload_manageability is not None else None
        wellbeing_features["wellbeing_focus"] = (perceived_focus - 1) / 4.0 if perceived_focus is not None else None
        wellbeing_features["wellbeing_recovery"] = (break_recovery - 1) / 4.0 if break_recovery is not None else None
        # stress_factors is stored as JSON string, parse it
        import json
        if isinstance(stress_factors, str):
            try:
                stress_factors = json.loads(stress_factors)
            except (json.JSONDecodeError, TypeError):
                stress_factors = []
        wellbeing_features["wellbeing_stress_count"] = len(stress_factors) if stress_factors is not None else None

    return wellbeing_features


def _score_candidate(candidate_type: str, features: Dict[str, Any]) -> float:
    """
    Candidate-specific scoring (ranking score, NOT calibrated probability).
    Uses extracted real features, wellbeing check-ins, and evidence-filtered behavioral patterns.
    """
    if features.get("has_active_break", False):
        return 0.0

    last_dur = features.get("last_break_duration_minutes", 0.0)
    time_since = features.get("time_since_last_break_minutes")
    if last_dur >= 60.0 and (time_since is None or time_since < 180.0):
        return 0.0

    score = 0.5  # baseline
    session_len = features.get("session_length_minutes", 0)
    time_since = features.get("time_since_last_break_minutes")

    # Higher score if long session and time since break exceeds preferred interval
    if session_len > 30:
        score += 0.15
    if time_since is not None and time_since >= features.get("preferred_interval_minutes", 30) * 0.8:
        score += 0.15

    # Lower score if recent task completion is very high (user focused)
    if features.get("recent_task_completion_rate", 0) > 0.8:
        score -= 0.05

    # Wellbeing-aware heuristic adjustments (only when data is present / not None)
    fatigue = features.get("wellbeing_fatigue")
    recovery = features.get("wellbeing_recovery")
    workload = features.get("wellbeing_workload")
    stress_count = features.get("wellbeing_stress_count", 0)

    if fatigue is not None:
        if fatigue > 0.6 and candidate_type in ["SHORT_BREAK", "WALK", "STRETCH"]:
            score += 0.12
        elif fatigue < 0.3 and candidate_type in ["SHORT_BREAK", "WALK"]:
            score -= 0.05

    if recovery is not None:
        if recovery < 0.4 and candidate_type in ["WALK", "STRETCH", "SHORT_BREAK"]:
            score += 0.10
        elif recovery > 0.7 and time_since is not None and time_since < 20:
            score -= 0.10

    if workload is not None:
        if workload < 0.4 and candidate_type in ["SHORT_BREAK", "LUNCH"]:
            score += 0.10

    if stress_count and stress_count > 0 and candidate_type in ["WALK", "STRETCH"]:
        score += min(0.15, 0.05 * stress_count)

    # Sprint 2: Evidence-Filtered Behavioral Pattern Scoring Adjustments
    # Only apply when not in cold start and evidence strength is MEDIUM or HIGH
    is_cold_start = features.get("cold_start", True)
    patterns = features.get("detected_patterns", [])

    if not is_cold_start:
        for p in patterns:
            if not p.get("detected"):
                continue
            strength = p.get("evidence_strength", "LOW")
            if strength not in ("MEDIUM", "HIGH"):
                continue

            pid = p.get("pattern_id")
            if pid == "REPEATED_SKIPPED_BREAKS" and candidate_type == "SHORT_BREAK":
                score += 0.15
            elif pid == "INSUFFICIENT_RECOVERY" and candidate_type in ["WALK", "SHORT_BREAK"]:
                score += 0.12
            elif pid == "RECURRING_FATIGUE_STRESS" and candidate_type in ["WALK", "STRETCH"]:
                score += 0.15
            elif pid == "DECLINING_MEASURABLE_FOCUS" and candidate_type == "SHORT_BREAK":
                score += 0.10
            elif pid == "RECURRING_OVERWORK" and candidate_type in ["LUNCH", "SHORT_BREAK"]:
                score += 0.12

    # Candidate-specific adjustments (derived from break categories)
    if candidate_type == "SHORT_BREAK":
        score += 0.1
    elif candidate_type == "WALK" and features.get("session_length_minutes", 0) > 45:
        score += 0.15
    elif candidate_type == "HYDRATE" and features.get("recent_task_completion_rate", 0) > 0.7:
        score += 0.1
    elif candidate_type == "STRETCH" and features.get("time_since_last_break_minutes") is not None and features.get("time_since_last_break_minutes") > 60:
        score += 0.12
    elif candidate_type in ["POSTURE_ADJUSTMENT", "WRIST_RELAXATION", "ERGONOMICS_REVIEW", "SIT_STAND_VARIATION"] and session_len > 45:
        score += 0.12
    elif candidate_type in ["FOCUS_INTERVAL_PLANNING", "TASK_BATCHING", "REDUCE_CONTEXT_SWITCHING", "COGNITIVE_RECOVERY", "LOWER_INTENSITY_TASK"] and features.get("recent_task_completion_rate", 1.0) < 0.5:
        score += 0.15
    elif candidate_type in ["TASK_PRIORITIZATION", "MILESTONE_BREAKDOWN", "DEADLINE_REVIEW", "WORKLOAD_REVIEW", "WORKLOAD_DISTRIBUTION"] and features.get("recent_task_count", 0) > 3:
        score += 0.15
    elif candidate_type in ["WLB_HOURS_REVIEW", "SHIFT_ENDING_ROUTINE", "RECOVERY_PLANNING", "WELLBEING_CHECKIN", "ROUTINE_MAINTENANCE"] and session_len > 90:
        score += 0.18

    # Clamp to [0, 1]
    return max(0.0, min(1.0, score))


def _get_ml_enhancement(db: Session, features: Dict[str, Any], candidate_type: str) -> Optional[float]:
    """
    Get ML enhancement factor for candidate scoring.
    Returns multiplicative factor (0.5 to 2.0) or None if ML unavailable.
    Uses predict_with_model for V1/V2 schema compatibility.
    """
    try:
        ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"
        if not ml_enabled:
            return None

        # Build feature dict from feature_snapshot
        feature_snapshot = features.get("feature_snapshot", {})
        feature_dict = build_feature_vector(feature_snapshot, candidate_type)

        # Use centralized predict_with_model which handles V1/V2 schemas
        from ..services.ml_training_pipeline import predict_with_model
        prob_accept = predict_with_model(db, feature_dict, candidate_type)

        if prob_accept is None:
            return None

        # Validate probability
        if not isinstance(prob_accept, (int, float)) or not (0.0 <= prob_accept <= 1.0):
            return None
        if prob_accept != prob_accept:  # NaN check
            return None

        # Convert probability to enhancement factor (0.5 to 2.0)
        enhancement = 0.5 + (prob_accept * 1.5)
        return max(0.5, min(2.0, enhancement))
    except Exception:
        return None


def _score_candidate_with_ml(candidate_type: str, features: Dict[str, Any], db: Session) -> tuple[float, Optional[float], bool]:
    """Score candidate with optional ML enhancement."""
    heuristic_score = _score_candidate(candidate_type, features)
    ml_enhancement = _get_ml_enhancement(db, features, candidate_type)
    ml_probability = None
    ml_used = False

    if ml_enhancement is not None:
        final_score = heuristic_score * ml_enhancement
        final_score = max(0.0, min(1.0, final_score))
        ml_probability = (ml_enhancement - 0.5) / 1.5
        ml_used = True
    else:
        final_score = heuristic_score

    return final_score, ml_probability, ml_used


FACTOR_WEIGHTS = [
    ("Session Length", "+0.15", "Session length exceeds 30 minutes"),
    ("Preferred Interval", "+0.15", "Time since last break is >= 80% of preferred interval"),
    ("High Focus Rate", "-0.05", "Recent task completion rate > 0.8"),
    ("High Fatigue", "+0.12", "Fatigue > 0.6"),
    ("Low Fatigue", "-0.05", "Fatigue < 0.3"),
    ("Low Recovery", "+0.10", "Recovery < 0.4"),
    ("Low Workload", "+0.10", "Workload < 0.4"),
]

PATTERN_WEIGHTS = [
    ("REPEATED_SKIPPED_BREAKS", "+0.15", ["SHORT_BREAK"], "MEDIUM or HIGH evidence", "User frequently skips breaks"),
    ("INSUFFICIENT_RECOVERY", "+0.12", ["WALK", "SHORT_BREAK"], "MEDIUM or HIGH evidence", "Recovery indicators are low across sessions"),
    ("RECURRING_FATIGUE_STRESS", "+0.15", ["WALK", "STRETCH"], "MEDIUM or HIGH evidence", "Fatigue and stress patterns recurring"),
]

CANDIDATE_BASELINES = {
    "SHORT_BREAK": 0.5,
    "WALK": 0.5,
    "HYDRATE": 0.5,
    "STRETCH": 0.5,
    "LUNCH": 0.5,
}


def _generate_reason(candidate_type: str, features: Dict[str, Any]) -> str:
    """Generate an evidence-based reason from actual features and detected behavioral patterns."""
    snapshot = features.get("feature_snapshot", {})
    session_len = snapshot.get("session_length")
    time_since = snapshot.get("time_since_break")
    rate = snapshot.get("completion_rate")
    fatigue = snapshot.get("wellbeing_fatigue")
    recovery = snapshot.get("wellbeing_recovery")
    workload = snapshot.get("wellbeing_workload")
    stress_count = snapshot.get("wellbeing_stress_count", 0)
    patterns = features.get("detected_patterns", [])

    reasons = []

    # Incorporate pattern-specific evidence wording (with cautious phrasing)
    for p in patterns:
        if not p.get("detected"):
            continue
        strength = p.get("evidence_strength", "LOW")
        if strength not in ("MEDIUM", "HIGH"):
            continue
        pid = p.get("pattern_id")
        if pid == "REPEATED_SKIPPED_BREAKS":
            reasons.append("several recent sessions had no recorded breaks")
        elif pid == "INSUFFICIENT_RECOVERY":
            reasons.append("recent lower break recovery scores")
        elif pid == "RECURRING_FATIGUE_STRESS":
            reasons.append("recurring reports of fatigue or stress")
        elif pid == "DECLINING_MEASURABLE_FOCUS":
            reasons.append("declining focus rate trend relative to personal baseline")
        elif pid == "RECURRING_OVERWORK":
            reasons.append("consistent overtime hours over recent days")

    if session_len is not None and session_len > 30:
        reasons.append(f"session duration {session_len}min")
    if time_since is not None and time_since > 30:
        reasons.append(f"last break {time_since:.0f}min ago")
    if rate is not None and rate > 0:
        reasons.append(f"task completion {rate:.0%}")
    if fatigue is not None and fatigue > 0.6:
        reasons.append(f"high fatigue")
    if recovery is not None and recovery < 0.4:
        reasons.append(f"low break recovery")
    if workload is not None and workload < 0.4:
        reasons.append(f"workload pressure")
    if stress_count > 0:
        reasons.append(f"{stress_count} stress factor(s)")

    reason_text = f"{candidate_type}: based on {', '.join(reasons)}" if reasons else f"{candidate_type}: baseline suggestion"
    return reason_text


def _recommend_for_profile(db: Session, profile_id: uuid.UUID) -> Dict[str, Any]:
    """Generate a single recommendation using the approved pipeline."""
    features = _extract_features(db, profile_id)
    profile = db.query(Profile).filter(Profile.id == profile_id).first()
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile_id,
        WorkSession.ended_at == None
    ).first()

    is_cold_start = features.get("cold_start", False)

    recommendation_source = "cold_start_rule"
    similarity_cohort_info = None

    if is_cold_start:
        candidate = "SHORT_BREAK"
        score = 0.55
        reason = f"cold-start baseline: session={features['session_length_minutes']}min, tasks={features['recent_task_count']}"
        ml_probability = None
        ml_used = False
        model_version = "cold-start-baseline"

        # Attempt similarity-based reference matching for enhanced cold-start
        try:
            from .similarity_matching_service import find_similar_reference_cohort
            sim_match = find_similar_reference_cohort(db, profile.user_id if profile else user_id)
            if sim_match.get("matched"):
                recommendation_source = "similarity_reference"
                similarity_cohort_info = sim_match
                score = min(max(score + 0.05 * sim_match.get("mean_similarity_score", 0), 0.0), 1.0)
                reason = f"similarity match: {sim_match.get('reason')}"
            else:
                recommendation_source = "population_prior"
                reason = f"cold-start baseline (fallback: {sim_match.get('reason')})"
        except Exception as e:
            recommendation_source = "cold_start_rule"
            reason = f"cold-start baseline (similarity service unavailable: {str(e)})"
    else:
        scores = {}
        ml_probs = {}
        ml_used_flags = {}

        for c in CANDIDATE_TYPES:
            final_score, ml_prob, ml_used = _score_candidate_with_ml(c, features, db)
            scores[c] = final_score
            ml_probs[c] = ml_prob
            ml_used_flags[c] = ml_used

        top_candidate = max(scores, key=scores.get)
        candidate = top_candidate
        score = scores[top_candidate]
        ml_probability = ml_probs[top_candidate]
        ml_used = ml_used_flags[top_candidate]
        reason = _generate_reason(candidate, features)

        if ml_used:
            try:
                ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"
                if ml_enabled:
                    model_record = db.query(MLModel).filter(MLModel.is_active == True).order_by(MLModel.training_date.desc()).first()
                    model_version = model_record.version if model_record else "heuristic-only"
                else:
                    model_version = "heuristic-only"
            except Exception:
                model_version = "heuristic-only"
        elif is_cold_start:
            model_version = "cold-start-baseline"
        else:
            model_version = "heuristic-only"

    recommendation_id = uuid.uuid4()
    feature_schema_version = "v2-wellbeing"

    feedback = RecommendationFeedback(
        recommendation_id=recommendation_id,
        user_id=profile.user_id if profile else None,
        model_version=model_version,
        feature_schema_version=feature_schema_version,
        recommendation_type=candidate,
        recommendation_score=score,
        context_features=features.get("feature_snapshot") or {},
        timestamp=datetime.now(),
        user_action=None,
        reason=reason,
        work_session_id=active_session.id if active_session else None,
        provenance=recommendation_source if 'recommendation_source' in locals() else 'live',
    )
    db.add(feedback)
    db.commit()
    db.refresh(feedback)

    ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"

    # Determine recommendation method provenance
    if ml_used:
        recommendation_method = "ml_enhanced"
    elif ml_enabled:
        recommendation_method = "heuristic_fallback"
    else:
        recommendation_method = "heuristic"

    result = {
        "recommendation_id": str(recommendation_id),
        "profile_id": str(profile_id),
        "user_id": str(profile.user_id) if profile else None,
        "candidate_type": candidate,
        "recommendation_score": score,
        "reason": reason,
        "context_features_snapshot": features.get("feature_snapshot"),
        "is_cold_start": is_cold_start,
        "model_version": feedback.model_version,
        "user_action": None,
        "timestamp": feedback.timestamp.isoformat() if feedback.timestamp else None,
        "feature_schema_version": feature_schema_version,
        "ml_used": ml_used,
        "recommendation_method": recommendation_method,
    }

    if ml_enabled:
        result["ml_probability"] = ml_probability

    return result


@router.post("/generate")
async def generate_recommendation(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    result = _recommend_for_profile(db, profile.id)
    return result


@router.post("/viewed")
async def mark_recommendation_viewed(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    data: dict = None,
):
    recommendation_id_str = data.get("recommendation_id") if data else None
    if not recommendation_id_str:
        raise HTTPException(status_code=400, detail="Missing recommendation_id")
    try:
        recommendation_id = uuid.UUID(recommendation_id_str)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid recommendation_id")

    feedback = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.recommendation_id == recommendation_id,
        RecommendationFeedback.user_id == current_user.id
    ).first()

    if not feedback:
        raise HTTPException(status_code=404, detail="Recommendation not found")

    if feedback.viewed_at is None:
        feedback.viewed_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(feedback)

    return {
        "status": "recorded",
        "recommendation_id": str(feedback.recommendation_id),
        "viewed_at": feedback.viewed_at.isoformat() if feedback.viewed_at else None
    }


@router.post("/feedback")
async def submit_feedback(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    data: dict = None,
):
    recommendation_id_str = data.get("recommendation_id") if data else None
    user_action = data.get("user_action") if data else None

    if not recommendation_id_str or user_action not in (
        "accepted", "dismissed", "ignored", "helpful", "not_helpful"
    ):
        raise HTTPException(status_code=400, detail="Invalid feedback data")

    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    today = datetime.now(timezone.utc).date()
    current_monday = today - timedelta(days=today.weekday())

    try:
        recommendation_id = uuid.UUID(recommendation_id_str)
    except ValueError:
        recommendation_id = wlb_recommendation_uuid(profile.id, current_monday, recommendation_id_str)

    feedback = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.recommendation_id == recommendation_id,
        RecommendationFeedback.user_id == current_user.id
    ).first()

    analysis = WLBAnalysisService(db).get_weekly_wlb_analysis(profile.id, current_monday)
    active_recommendation = next((
        item for item in analysis.get("recommendations", [])
        if str(uuid.uuid5(uuid.NAMESPACE_URL, f"intellibreak:wlb:{profile.id}:{current_monday.isoformat()}:{item['id']}")) == str(recommendation_id)
           or str(item['id']) == str(recommendation_id_str)
    ), None)

    is_wlb = (feedback and feedback.recommendation_type and feedback.recommendation_type.startswith("WLB_")) or active_recommendation is not None

    if is_wlb:
        if active_recommendation is None:
            raise HTTPException(status_code=404, detail="Recommendation not found")
        if feedback is None:
            feedback = RecommendationFeedback(
                recommendation_id=recommendation_id,
                user_id=current_user.id,
                model_version="wlb-rule-based-v1",
                recommendation_type=f"WLB_{active_recommendation['category']}",
                recommendation_score=0.0,
                context_features={
                    "recommendation_key": active_recommendation["id"],
                    "week_start": current_monday.isoformat(),
                },
                feature_schema_version="v2-wellbeing",
                reason=active_recommendation["title"],
            )
            db.add(feedback)
    else:
        if feedback is None:
            raise HTTPException(status_code=404, detail="Recommendation not found")

    feedback.user_action = user_action
    if user_action == "accepted":
        break_started_at_str = data.get("break_started_at") if data else None
        break_ended_at_str = data.get("break_ended_at") if data else None
        if break_started_at_str:
            try:
                feedback.break_started_at = datetime.fromisoformat(break_started_at_str)
            except ValueError:
                pass
        if break_ended_at_str:
            try:
                feedback.break_ended_at = datetime.fromisoformat(break_ended_at_str)
            except ValueError:
                pass
        if feedback.break_started_at and feedback.break_ended_at:
            duration_sec = (feedback.break_ended_at - feedback.break_started_at).total_seconds()
            feedback.break_duration = int(duration_sec // 60)
            if "post_break_productivity_delta" in data and data["post_break_productivity_delta"] is not None:
                feedback.post_break_productivity_delta = float(data["post_break_productivity_delta"])
    elif user_action == "dismissed":
        pass

    db.commit()
    analytics_cache.invalidate()
    db.refresh(feedback)

    return {
        "status": "updated",
        "recommendation_id": str(feedback.recommendation_id),
        "user_action": feedback.user_action,
        "break_started_at": feedback.break_started_at.isoformat() if feedback.break_started_at else None,
        "break_ended_at": feedback.break_ended_at.isoformat() if feedback.break_ended_at else None,
        "break_duration": feedback.break_duration,
    }


@router.post("/lifecycle")
async def update_recommendation_lifecycle(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    data: dict = None,
):
    """
    Update recommendation lifecycle event state (displayed, viewed, accepted, dismissed, expired, helpful, not_helpful).
    Enforces strict ownership validation (feedback.user_id == current_user.id).
    """
    if not data:
        raise HTTPException(status_code=400, detail="Missing request body")

    recommendation_id_str = data.get("recommendation_id")
    event_type = data.get("event_type")

    valid_events = {"displayed", "viewed", "accepted", "dismissed", "expired", "helpful", "not_helpful"}
    if not recommendation_id_str or event_type not in valid_events:
        raise HTTPException(status_code=400, detail="Invalid recommendation_id or event_type")

    try:
        recommendation_id = uuid.UUID(recommendation_id_str)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid recommendation_id format")

    feedback = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.recommendation_id == recommendation_id,
        RecommendationFeedback.user_id == current_user.id
    ).first()

    if not feedback:
        raise HTTPException(status_code=404, detail="Recommendation feedback record not found or unauthorized")

    now = datetime.now(timezone.utc)
    if event_type == "displayed":
        if feedback.displayed_at is None:
            feedback.displayed_at = now
        feedback.lifecycle_status = "displayed"
    elif event_type == "viewed":
        if feedback.viewed_at is None:
            feedback.viewed_at = now
        feedback.lifecycle_status = "viewed"
    elif event_type == "accepted":
        feedback.user_action = "accepted"
        feedback.lifecycle_status = "accepted"
    elif event_type == "dismissed":
        feedback.user_action = "dismissed"
        feedback.lifecycle_status = "dismissed"
    elif event_type == "expired":
        feedback.lifecycle_status = "expired"
    elif event_type == "helpful":
        feedback.usefulness_rating = "helpful"
        feedback.lifecycle_status = "helpful"
    elif event_type == "not_helpful":
        feedback.usefulness_rating = "not_helpful"
        feedback.lifecycle_status = "not_helpful"

    db.commit()
    db.refresh(feedback)

    return {
        "status": "success",
        "recommendation_id": str(recommendation_id),
        "lifecycle_status": feedback.lifecycle_status,
        "user_action": feedback.user_action,
        "usefulness_rating": feedback.usefulness_rating,
    }


@router.get("/outcomes")
async def evaluate_recommendation_outcomes(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Evaluate recommendation engagement, break execution, and post-break associations
    using actual RecommendationFeedback, Break, WorkSession, and Task records.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    feedbacks = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.user_id == current_user.id
    ).all()

    total_generated = len(feedbacks)
    if total_generated == 0:
        return {
            "total_generated": 0,
            "total_viewed": 0,
            "total_accepted": 0,
            "total_dismissed": 0,
            "total_ignored": 0,
            "total_pending": 0,
            "generated_to_viewed_rate": 0.0,
            "viewed_to_accepted_rate": 0.0,
            "dismissal_rate": 0.0,
            "ignored_rate": 0.0,
            "accepted_with_break_rate": 0.0,
            "break_completion_rate": 0.0,
            "median_time_to_view_seconds": None,
            "average_post_break_productivity_delta": None,
            "note": "No recommendation feedback records found."
        }

    v2_feedbacks = [f for f in feedbacks if f.feature_schema_version == "v2-wellbeing"]
    total_v2 = len(v2_feedbacks)

    viewed_count = sum(1 for f in feedbacks if f.viewed_at is not None)
    accepted_count = sum(1 for f in feedbacks if f.user_action == "accepted")
    dismissed_count = sum(1 for f in feedbacks if f.user_action == "dismissed")

    now = datetime.now(timezone.utc)
    ignored_count = 0
    pending_count = 0
    expired_24h_count = 0

    # V2-specific counters
    wellbeing_keys = [
        "wellbeing_overall", "wellbeing_fatigue", "wellbeing_workload",
        "wellbeing_focus", "wellbeing_recovery", "wellbeing_stress"
    ]
    v2_missing_counts = {k: 0 for k in wellbeing_keys}
    v2_complete_wellbeing = 0
    v2_users = set()
    v2_accepted = 0
    v2_dismissed = 0
    v2_ignored = 0
    v2_expired_24h = 0
    v2_unanswered = 0

    for f in feedbacks:
        if f.user_action is None:
            ts = f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp and f.timestamp.tzinfo is None else (f.timestamp or now)
            age_hours = (now - ts).total_seconds() / 3600.0

            # V2 Phase 2: Expiration is 24 hours
            if age_hours > 24.0:
                ignored_count += 1
                expired_24h_count += 1
            else:
                pending_count += 1
        else:
            # explicit action or already ignored
            if f.user_action not in ["accepted", "dismissed"]:
                ignored_count += 1

        # V2 Diagnostics
        if f.feature_schema_version == "v2-wellbeing":
            v2_users.add(f.user_id)
            context = f.context_features or {}

            is_complete = True
            for k in wellbeing_keys:
                if context.get(k) is None:
                    v2_missing_counts[k] += 1
                    is_complete = False
            if is_complete:
                v2_complete_wellbeing += 1

            if f.user_action == "accepted":
                v2_accepted += 1
            elif f.user_action == "dismissed":
                v2_dismissed += 1
            elif f.user_action is None:
                ts = f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp and f.timestamp.tzinfo is None else (f.timestamp or now)
                if (now - ts).total_seconds() > 86400:
                    v2_expired_24h += 1
                    v2_ignored += 1
                else:
                    v2_unanswered += 1
            else:
                v2_ignored += 1

    gen_to_view_rates = []
    for f in feedbacks:
        if f.viewed_at and f.timestamp:
            ts = f.timestamp.replace(tzinfo=timezone.utc) if f.timestamp.tzinfo is None else f.timestamp
            va = f.viewed_at.replace(tzinfo=timezone.utc) if f.viewed_at.tzinfo is None else f.viewed_at
            delta = (va - ts).total_seconds()
            if delta >= 0:
                gen_to_view_rates.append(delta)

    median_time_to_view = statistics.median(gen_to_view_rates) if gen_to_view_rates else None

    accepted_with_break = sum(1 for f in feedbacks if f.user_action == "accepted" and f.break_started_at is not None)
    completed_breaks = sum(1 for f in feedbacks if f.user_action == "accepted" and f.break_started_at is not None and f.break_ended_at is not None)

    productivity_deltas = [f.post_break_productivity_delta for f in feedbacks if f.post_break_productivity_delta is not None]
    avg_prod_delta = sum(productivity_deltas) / len(productivity_deltas) if productivity_deltas else None

    return {
        "total_generated": total_generated,
        "total_viewed": viewed_count,
        "total_accepted": accepted_count,
        "total_dismissed": dismissed_count,
        "total_ignored": ignored_count,
        "total_pending": pending_count,
        "total_expired_24h": expired_24h_count,
        "v2_wellbeing_diagnostics": {
            "total_v2": total_v2,
            "complete_wellbeing": v2_complete_wellbeing,
            "unique_users": len(v2_users),
            "accepted": v2_accepted,
            "dismissed": v2_dismissed,
            "ignored_or_expired": v2_ignored,
            "expired_24h": v2_expired_24h,
            "unanswered_pending": v2_unanswered,
            "missing_wellbeing_features": v2_missing_counts,
            "schema_version": "v2-wellbeing"
        },
        "generated_to_viewed_rate": round(viewed_count / total_generated, 2) if total_generated > 0 else 0.0,
        "viewed_to_accepted_rate": round(accepted_count / viewed_count, 2) if viewed_count > 0 else 0.0,
        "dismissal_rate": round(dismissed_count / total_generated, 2) if total_generated > 0 else 0.0,
        "ignored_rate": round(ignored_count / total_generated, 2) if total_generated > 0 else 0.0,
        "accepted_with_break_rate": round(accepted_with_break / accepted_count, 2) if accepted_count > 0 else 0.0,
        "break_completion_rate": round(completed_breaks / accepted_with_break, 2) if accepted_with_break > 0 else 0.0,
        "median_time_to_view_seconds": round(median_time_to_view, 1) if median_time_to_view is not None else None,
        "average_post_break_productivity_delta": round(avg_prod_delta, 2) if avg_prod_delta is not None else None,
        "evaluation_timestamp": now.isoformat(),
        "note": "Metrics reflect observed recommendation engagement and explicit break linkage. Associations reported without causal guarantees."
    }


@router.get("/health")
async def recommendation_health(db: Session = Depends(get_db)):
    ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"

    active_model_info = None
    if ml_enabled:
        try:
            active_model = db.query(MLModel).filter(MLModel.is_active == True).order_by(MLModel.training_date.desc()).first()
            if active_model:
                ml_status = "active"
                active_model_info = {
                    "version": active_model.version,
                    "feature_set_version": active_model.feature_set_version,
                    "training_date": active_model.training_date.isoformat() if active_model.training_date else None,
                    "metrics": active_model.metrics
                }
            else:
                ml_status = "enabled-but-no-active-model"
        except Exception as e:
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error querying active ML model: {e}")
            ml_status = "enabled-but-error"
    else:
        ml_status = "disabled"

    # Determine overall mode
    if ml_status == "active":
        mode = "ml-enhanced"
    elif ml_status == "enabled-but-no-active-model":
        mode = "cold-start-baseline (ML pipeline ready, awaiting feedback)"
    elif ml_status == "enabled-but-error":
        mode = "cold-start-baseline (ML pipeline error)"
    else:
        mode = "cold-start-baseline (ML disabled)"

    return {
        "status": "healthy",
        "mode": mode,
        "ml_recommendations_enabled": ml_enabled,
        "ml_status": ml_status,
        "active_model": active_model_info,
        "cold_start_baseline_active": ml_status != "active",
        "note": "Recommendation engine uses candidate scoring + ranking (cold-start heuristic). "
                "ML enhancement for recommendation-acceptance prediction is available via "
                "ml_training_pipeline.py and activates automatically when sufficient labeled "
                "feedback is collected (minimum 20 samples, 5 per class). "
                "Work-pattern decline prediction (/ml/predict-decline) is NOT deployed; "
                "thesis scope is recommendation-acceptance prediction only."
    }


@router.post("/dev/generate-test")
async def dev_generate_test_recommendation(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    import os
    if os.getenv("RENDER") == "true" and os.getenv("ENABLE_DEV_ENDPOINTS") != "true":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Development endpoints are disabled in production"
        )

    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at == None
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=400,
            detail="No active work session found. Start a work session before generating a test recommendation."
        )

    result = _recommend_for_profile(db, profile.id)

    result["_test_metadata"] = {
        "endpoint": "dev/generate-test",
        "user_id": str(current_user.id),
        "profile_id": str(profile.id),
        "work_session_id": str(active_session.id),
        "note": "Generated via development test endpoint using production recommendation pipeline"
    }

    return result
