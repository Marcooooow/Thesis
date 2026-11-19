"""
Similarity Matching Service — Weighted distance and KNN reference matching
for cold-start work-break recommendations using versioned behavioral snapshots.
Includes non-negotiable Work-Life Balance (WLB) safety constraints.
"""

from typing import Optional, Dict, Any, List, Union
import uuid
import math
import statistics
from sqlalchemy.orm import Session

from ..models import BehavioralSnapshot, User

def _encode_categorical(val: Optional[str], mapping: Dict[str, float], default: float = 0.5) -> float:
    if not val:
        return default
    return mapping.get(val.strip().lower(), default)

SCHEDULE_MAP = {"fixed": 0.0, "flexible": 0.5, "variable": 1.0}
ARRANGEMENT_MAP = {"remote": 0.0, "hybrid": 0.5, "office": 1.0}

def extract_feature_vector(snapshot: BehavioralSnapshot) -> Dict[str, float]:
    """
    Extract and normalize numerical feature vector from a BehavioralSnapshot
    combining self_reported_context and observed_baselines.
    """
    ctx = snapshot.self_reported_context or {}
    obs = snapshot.observed_baselines or {}

    sched = _encode_categorical(ctx.get("schedule_type"), SCHEDULE_MAP, 0.5)
    arr = _encode_categorical(ctx.get("arrangement"), ARRANGEMENT_MAP, 0.5)

    typ_focus = float(ctx.get("typical_focus_duration") or 60) / 180.0
    pref_focus = float(ctx.get("preferred_focus_duration") or 45) / 120.0
    typ_freq = float(ctx.get("typical_break_frequency") or 4) / 10.0

    med_session = float(obs.get("median_session_duration_minutes") or 60.0) / 120.0
    med_interval = float(obs.get("median_break_interval_minutes") or 45.0) / 120.0
    med_break_dur = float(obs.get("median_break_duration_minutes") or 15.0) / 45.0

    return {
        "schedule_type": min(max(sched, 0.0), 1.0),
        "arrangement": min(max(arr, 0.0), 1.0),
        "typical_focus_duration": min(max(typ_focus, 0.0), 1.0),
        "preferred_focus_duration": min(max(pref_focus, 0.0), 1.0),
        "typical_break_frequency": min(max(typ_freq, 0.0), 1.0),
        "median_session_duration": min(max(med_session, 0.0), 1.0),
        "median_break_interval": min(max(med_interval, 0.0), 1.0),
        "median_break_duration": min(max(med_break_dur, 0.0), 1.0),
    }

FEATURE_WEIGHTS = {
    "typical_focus_duration": 0.20,
    "preferred_focus_duration": 0.20,
    "median_break_interval": 0.20,
    "median_break_duration": 0.15,
    "schedule_type": 0.10,
    "arrangement": 0.05,
    "typical_break_frequency": 0.05,
    "median_session_duration": 0.05,
}

def calculate_weighted_distance(vec_a: Dict[str, float], vec_b: Dict[str, float]) -> float:
    """Calculate weighted Euclidean distance between two normalized feature vectors."""
    sum_sq_diff = 0.0
    total_weight = 0.0
    for feat, weight in FEATURE_WEIGHTS.items():
        val_a = vec_a.get(feat, 0.5)
        val_b = vec_b.get(feat, 0.5)
        sum_sq_diff += weight * ((val_a - val_b) ** 2)
        total_weight += weight

    if total_weight == 0:
        return 1.0
    return math.sqrt(sum_sq_diff / total_weight)

def enforce_work_life_balance_safety(aggregated_metrics: Dict[str, float]) -> Dict[str, float]:
    """
    Apply non-negotiable IntelliBreak work-life balance (WLB) safety constraints
    to aggregated reference metrics. Prevents replicating unhealthy reference habits
    (e.g., excessively long continuous work intervals or missing breaks).
    """
    safe_metrics = dict(aggregated_metrics)

    interval = safe_metrics.get("recommended_break_interval_minutes", 45.0)
    if interval > 90.0:
        safe_metrics["recommended_break_interval_minutes"] = 90.0
        safe_metrics["safety_adjustment_applied"] = "interval_capped_at_90m"
    elif interval < 15.0:
        safe_metrics["recommended_break_interval_minutes"] = 15.0
        safe_metrics["safety_adjustment_applied"] = "interval_floored_at_15m"

    duration = safe_metrics.get("recommended_break_duration_minutes", 15.0)
    if duration > 45.0:
        safe_metrics["recommended_break_duration_minutes"] = 45.0
    elif duration < 5.0:
        safe_metrics["recommended_break_duration_minutes"] = 5.0

    return safe_metrics

def find_similar_reference_cohort(
    db: Session,
    target_user_id: uuid.UUID,
    top_k: int = 5,
    min_data_quality: float = 0.3,
    min_sample_count: int = 3
) -> Dict[str, Any]:
    """
    Find top-K compatible reference employee snapshots using weighted distance matching.
    Excludes the target user, filters out unhealthy/overworked reference patterns,
    enforces WLB safety constraints, and protects privacy.
    """
    target_snapshot = db.query(BehavioralSnapshot).filter(
        BehavioralSnapshot.user_id == target_user_id
    ).order_by(BehavioralSnapshot.snapshot_date.desc()).first()

    if not target_snapshot:
        return {"matched": False, "reason": "No target snapshot found for similarity matching"}

    target_vec = extract_feature_vector(target_snapshot)

    candidates = db.query(BehavioralSnapshot).filter(
        BehavioralSnapshot.user_id != target_user_id,
        BehavioralSnapshot.data_quality >= min_data_quality,
        BehavioralSnapshot.sample_count >= min_sample_count,
        BehavioralSnapshot.schema_version == target_snapshot.schema_version
    ).all()

    if not candidates:
        return {"matched": False, "reason": "No eligible reference cohorts available"}

    scored_candidates = []
    for cand in candidates:
        # Safety filter: exclude reference profiles exhibiting active overwork or severe skipped breaks
        patterns = cand.pattern_detections or {}
        if patterns.get("overwork") is True or patterns.get("skipped_breaks_count", 0) > 3:
            continue

        cand_vec = extract_feature_vector(cand)
        dist = calculate_weighted_distance(target_vec, cand_vec)
        similarity = 1.0 / (1.0 + dist)
        scored_candidates.append({
            "snapshot_id": str(cand.id),
            "similarity_score": round(similarity, 3),
            "observed_baselines": cand.observed_baselines or {},
            "self_reported_context": cand.self_reported_context or {},
        })

    scored_candidates.sort(key=lambda x: x["similarity_score"], reverse=True)
    top_matches = scored_candidates[:top_k]

    if not top_matches or top_matches[0]["similarity_score"] < 0.4:
        return {"matched": False, "reason": "Insufficient similarity confidence with reference cohort"}

    intervals = [m["observed_baselines"].get("median_break_interval_minutes") for m in top_matches if m["observed_baselines"].get("median_break_interval_minutes")]
    durations = [m["observed_baselines"].get("median_break_duration_minutes") for m in top_matches if m["observed_baselines"].get("median_break_duration_minutes")]

    agg_interval = statistics.median(intervals) if intervals else 45.0
    agg_duration = statistics.median(durations) if durations else 15.0

    raw_metrics = {
        "recommended_break_interval_minutes": round(agg_interval, 1),
        "recommended_break_duration_minutes": round(agg_duration, 1),
    }

    safe_metrics = enforce_work_life_balance_safety(raw_metrics)

    return {
        "matched": True,
        "cohort_size": len(top_matches),
        "mean_similarity_score": round(statistics.mean([m["similarity_score"] for m in top_matches]), 3),
        "aggregated_reference_metrics": safe_metrics,
        "reason": f"Matched across {len(top_matches)} safe reference profiles (mean similarity: {round(statistics.mean([m['similarity_score'] for m in top_matches]), 2)})"
    }
