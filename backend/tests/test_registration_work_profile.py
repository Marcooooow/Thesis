from datetime import date, datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import inspect
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import (
    BehavioralSnapshot,
    Profile,
    RecommendationFeedback,
    User,
    UserWorkProfile,
)
from app.routers.auth import register_user
from app.schemas.auth import UserCreate
from app.schemas.user_work_profile import UserWorkProfileResponse
from app.services.work_profile_service import serialize_work_profile


def test_registration_persists_completed_work_profile(
    test_db: Session,
):
    work_profile = {
        "schedule_type": "fixed",
        "typical_start_time": "08:30",
        "typical_end_time": "17:30",
        "working_days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
        "arrangement": "hybrid",
        "typical_focus_duration": 60,
        "preferred_focus_duration": 90,
        "typical_break_frequency": 3,
        "typical_break_duration": 15,
        "lunch_start_time": "12:00",
        "lunch_duration": 60,
        "lunch_consistency": "consistent",
        "responsibilities": ["childcare", "pet care"],
        "reminder_preference": "gentle",
        "recommendation_style": "flexible",
        "additional_preferences": "Avoid meetings during focus time.",
        "profile_completed": True,
    }

    user_data = UserCreate.model_validate(
        {
            "email": "work-profile-registration@test.com",
            "password": "securepass123",
            "full_name": "Work Profile User",
            "account_type": "solo",
            "work_profile": work_profile,
        }
    )

    registered_user = register_user(user_data, test_db)
    assert registered_user.email == user_data.email
    user = test_db.query(User).filter_by(
        email="work-profile-registration@test.com"
    ).one()
    profile = test_db.query(UserWorkProfile).filter_by(user_id=user.id).one()

    assert profile.working_days == work_profile["working_days"]
    assert profile.responsibilities == work_profile["responsibilities"]
    assert profile.profile_completed is True

    if test_db.get_bind().dialect.name == "postgresql":
        columns = {
            column["name"]: column["type"]
            for column in inspect(test_db.get_bind()).get_columns(
                "user_work_profiles"
            )
        }
        assert str(columns["working_days"]).upper() == "JSON"
        assert str(columns["responsibilities"]).upper() == "JSON"

    serialized = UserWorkProfileResponse.model_validate(
        serialize_work_profile(profile)
    )
    assert serialized.working_days == work_profile["working_days"]
    assert serialized.responsibilities == work_profile["responsibilities"]

    profile_record = test_db.query(Profile).filter_by(user_id=user.id).one()
    feedback = RecommendationFeedback(
        user_id=user.id,
        recommendation_id=uuid4(),
        model_version="migration-audit",
        recommendation_type="break_reminder",
        recommendation_score=0.8,
        context_features={"audit": True},
        lifecycle_status="displayed",
        usefulness_rating="useful",
    )
    snapshot = BehavioralSnapshot(
        user_id=user.id,
        profile_id=profile_record.id,
        snapshot_date=date.today(),
        window_start=datetime.now(timezone.utc),
        window_end=datetime.now(timezone.utc),
        self_reported_context={"schedule_type": "fixed"},
        observed_baselines={"focus_minutes": 60},
        pattern_detections={"skipped_breaks": False},
    )
    test_db.add_all([feedback, snapshot])
    test_db.commit()
    test_db.refresh(feedback)
    test_db.refresh(snapshot)

    assert feedback.lifecycle_status == "displayed"
    assert feedback.usefulness_rating == "useful"
    assert snapshot.profile_id == profile_record.id
    assert snapshot.self_reported_context == {"schedule_type": "fixed"}
    assert snapshot.observed_baselines == {"focus_minutes": 60}


def test_registration_rolls_back_when_work_profile_write_fails(
    test_db: Session,
    monkeypatch,
):
    user_data = UserCreate.model_validate(
        {
            "email": "work-profile-rollback@test.com",
            "password": "securepass123",
            "full_name": "Rollback User",
            "account_type": "solo",
            "work_profile": {
                "working_days": ["monday"],
                "responsibilities": ["childcare"],
                "profile_completed": True,
            },
        }
    )
    original_flush = test_db.flush
    flush_count = 0

    def fail_profile_flush(*args, **kwargs):
        nonlocal flush_count
        flush_count += 1
        if flush_count == 3:
            raise IntegrityError(
                "INSERT user_work_profiles",
                {},
                RuntimeError("simulated database constraint failure"),
            )
        return original_flush(*args, **kwargs)

    monkeypatch.setattr(test_db, "flush", fail_profile_flush)

    with pytest.raises(IntegrityError):
        register_user(user_data, test_db)

    monkeypatch.setattr(test_db, "flush", original_flush)
    assert test_db.query(User).filter_by(email=user_data.email).first() is None
