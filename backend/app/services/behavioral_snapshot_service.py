from datetime import datetime, timezone, date, timedelta
from typing import Optional, Dict, Any, List, Union
import uuid
from sqlalchemy.orm import Session

from ..models import BehavioralSnapshot, Profile, WorkSession, Break, SessionWellbeingCheckin
from .behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from .work_profile_service import get_work_profile

SCHEMA_VERSION = "v2_behavioral_snapshot_20261117"
AGGREGATION_VERSION = "v2_median_robust"

def generate_daily_snapshot(db: Session, user_id: Union[str, uuid.UUID], window_days: int = 30) -> BehavioralSnapshot:
    """
    Generate or update a versioned behavioral observation snapshot for an employee
    combining self-reported profile context and observed robust baselines (7, 14, or 30 days).
    Idempotent per user, snapshot_date, window days, and schema version.
    """
    if isinstance(user_id, str):
        user_id = uuid.UUID(user_id)

    if window_days not in [7, 14, 30]:
        window_days = 30

    now = datetime.now(timezone.utc)
    today = now.date()
    window_start = now - timedelta(days=window_days)
    window_end = now

    # 1. Fetch profile and self-reported context
    profile = db.query(Profile).filter(Profile.user_id == user_id).first()
    work_profile = get_work_profile(db, user_id)

    self_reported_context = {}
    if work_profile:
        self_reported_context = {
            "schedule_type": work_profile.schedule_type,
            "arrangement": work_profile.arrangement,
            "typical_start_time": str(work_profile.typical_start_time) if work_profile.typical_start_time else None,
            "typical_end_time": str(work_profile.typical_end_time) if work_profile.typical_end_time else None,
            "typical_focus_duration": work_profile.typical_focus_duration,
            "preferred_focus_duration": work_profile.preferred_focus_duration,
            "typical_break_frequency": work_profile.typical_break_frequency,
            "typical_break_duration": work_profile.typical_break_duration,
            "recommendation_style": work_profile.recommendation_style,
            "reminder_preference": work_profile.reminder_preference,
            "profile_completed": work_profile.profile_completed,
        }
    elif profile:
        self_reported_context = {
            "job_role": profile.job_role,
            "industry": profile.industry,
            "target_daily_hours": profile.target_daily_hours,
        }

    # 2. Calculate observed baselines and pattern detections
    observed_baselines = {}
    pattern_detections = {}
    sample_count = 0
    source_watermark = None

    if profile:
        observed_baselines = calculate_personal_baselines(db, profile.id, days=window_days)
        pattern_detections = detect_behavioral_patterns(db, profile.id)

        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id == profile.id,
            WorkSession.ended_at.isnot(None),
            WorkSession.started_at >= window_start
        ).all()
        sample_count = len(sessions)
        ended_at_list = [s.ended_at for s in sessions if s.ended_at]
        if ended_at_list:
            source_watermark = max(ended_at_list)

    data_quality = min(1.0, sample_count / float(window_days)) if window_days > 0 else 0.0

    # 3. Upsert snapshot idempotently
    snapshot = db.query(BehavioralSnapshot).filter(
        BehavioralSnapshot.user_id == user_id,
        BehavioralSnapshot.snapshot_date == today,
        BehavioralSnapshot.observation_window_days == window_days,
        BehavioralSnapshot.schema_version == SCHEMA_VERSION
    ).first()

    if snapshot:
        snapshot.window_start = window_start
        snapshot.window_end = window_end
        snapshot.self_reported_context = self_reported_context
        snapshot.observed_baselines = observed_baselines
        snapshot.pattern_detections = pattern_detections
        snapshot.source_event_watermark = source_watermark
        snapshot.sample_count = sample_count
        snapshot.data_quality = data_quality
        snapshot.updated_at = now
    else:
        snapshot = BehavioralSnapshot(
            user_id=user_id,
            profile_id=profile.id if profile else None,
            snapshot_date=today,
            window_start=window_start,
            window_end=window_end,
            observation_window_days=window_days,
            self_reported_context=self_reported_context,
            observed_baselines=observed_baselines,
            pattern_detections=pattern_detections,
            provenance="derived_snapshot",
            schema_version=SCHEMA_VERSION,
            aggregation_version=AGGREGATION_VERSION,
            source_event_watermark=source_watermark,
            sample_count=sample_count,
            data_quality=data_quality,
        )
        db.add(snapshot)

    db.commit()
    db.refresh(snapshot)
    return snapshot

def get_latest_snapshot(db: Session, user_id: Union[str, uuid.UUID], window_days: int = 30) -> Optional[BehavioralSnapshot]:
    if isinstance(user_id, str):
        user_id = uuid.UUID(user_id)
    return db.query(BehavioralSnapshot).filter(
        BehavioralSnapshot.user_id == user_id,
        BehavioralSnapshot.observation_window_days == window_days,
        BehavioralSnapshot.schema_version == SCHEMA_VERSION
    ).order_by(BehavioralSnapshot.snapshot_date.desc()).first()

def get_snapshot_history(db: Session, user_id: Union[str, uuid.UUID], limit: int = 10) -> List[BehavioralSnapshot]:
    if isinstance(user_id, str):
        user_id = uuid.UUID(user_id)
    return db.query(BehavioralSnapshot).filter(
        BehavioralSnapshot.user_id == user_id,
        BehavioralSnapshot.schema_version == SCHEMA_VERSION
    ).order_by(BehavioralSnapshot.snapshot_date.desc()).limit(limit).all()

def serialize_snapshot(snapshot: BehavioralSnapshot) -> Dict[str, Any]:
    return {
        "id": str(snapshot.id),
        "user_id": str(snapshot.user_id),
        "snapshot_date": snapshot.snapshot_date.isoformat(),
        "window_start": snapshot.window_start.isoformat() if snapshot.window_start else None,
        "window_end": snapshot.window_end.isoformat() if snapshot.window_end else None,
        "observation_window_days": snapshot.observation_window_days,
        "self_reported_context": snapshot.self_reported_context,
        "observed_baselines": snapshot.observed_baselines,
        "pattern_detections": snapshot.pattern_detections,
        "provenance": snapshot.provenance,
        "schema_version": snapshot.schema_version,
        "aggregation_version": snapshot.aggregation_version,
        "source_event_watermark": snapshot.source_event_watermark.isoformat() if snapshot.source_event_watermark else None,
        "sample_count": snapshot.sample_count,
        "data_quality": snapshot.data_quality,
        "generated_at": snapshot.generated_at.isoformat() if snapshot.generated_at else None,
    }
