from sqlalchemy.orm import Session
from datetime import time, datetime
from typing import Optional, Dict, Any
import uuid

from ..models import UserWorkProfile
from ..schemas.user_work_profile import UserWorkProfileCreate, UserWorkProfileUpdate

def _parse_time(time_str: Optional[str]) -> Optional[time]:
    if not time_str:
        return None
    if isinstance(time_str, time):
        return time_str
    try:
        parts = time_str.split(":")
        return time(int(parts[0]), int(parts[1]))
    except Exception:
        return None

def _format_time(t: Optional[time]) -> Optional[str]:
    if not t:
        return None
    if isinstance(t, str):
        return t[:5]
    return t.strftime("%H:%M")

def get_work_profile(db: Session, user_id: uuid.UUID) -> Optional[UserWorkProfile]:
    return db.query(UserWorkProfile).filter(UserWorkProfile.user_id == user_id).first()

def create_or_update_work_profile(
    db: Session,
    user_id: uuid.UUID,
    data: UserWorkProfileCreate | UserWorkProfileUpdate,
    commit: bool = True,
) -> UserWorkProfile:
    try:
        profile = get_work_profile(db, user_id)

        update_data = data.model_dump(exclude_unset=True)

        for time_field in ['typical_start_time', 'typical_end_time', 'lunch_start_time']:
            if time_field in update_data:
                update_data[time_field] = _parse_time(update_data[time_field])

        if profile:
            for key, value in update_data.items():
                setattr(profile, key, value)
            profile.updated_at = datetime.utcnow()
        else:
            profile = UserWorkProfile(user_id=user_id, **update_data)
            db.add(profile)

        if commit:
            db.commit()
            db.refresh(profile)
        else:
            db.flush()
        return profile
    except Exception:
        db.rollback()
        raise

def serialize_work_profile(profile: UserWorkProfile) -> Dict[str, Any]:
    return {
        "id": str(profile.id),
        "user_id": str(profile.user_id),
        "schedule_type": profile.schedule_type,
        "typical_start_time": _format_time(profile.typical_start_time),
        "typical_end_time": _format_time(profile.typical_end_time),
        "working_days": profile.working_days,
        "arrangement": profile.arrangement,
        "typical_focus_duration": profile.typical_focus_duration,
        "preferred_focus_duration": profile.preferred_focus_duration,
        "typical_break_frequency": profile.typical_break_frequency,
        "typical_break_duration": profile.typical_break_duration,
        "lunch_start_time": _format_time(profile.lunch_start_time),
        "lunch_duration": profile.lunch_duration,
        "lunch_consistency": profile.lunch_consistency,
        "responsibilities": profile.responsibilities,
        "reminder_preference": profile.reminder_preference,
        "recommendation_style": profile.recommendation_style,
        "additional_preferences": profile.additional_preferences,
        "profile_completed": profile.profile_completed,
        "created_at": profile.created_at.isoformat() if profile.created_at else None,
        "updated_at": profile.updated_at.isoformat() if profile.updated_at else None,
    }
