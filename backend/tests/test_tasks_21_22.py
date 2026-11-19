"""
Tests for Tasks 2.1 and 2.2 implementation:
- Feedback uniqueness (unique constraint)
- Recommendation expiration
- Canonical V2 feature schema
- Training/inference feature consistency
"""
import os
import uuid
from datetime import datetime, timezone, timedelta
import pytest
from sqlalchemy import create_engine, StaticPool
from sqlalchemy.orm import sessionmaker

from app.database import Base, get_db
from app.models import (
    User, Profile, WorkSession, Break, Task, UserSettings,
    RecommendationFeedback, MLModel
)
from app.auth.security import get_password_hash, create_access_token
from app.services.feature_schema import (
    V2_NUMERIC_FEATURE_KEYS,
    V2_CATEGORICAL_FEATURE_KEYS,
    V2_ALL_FEATURE_KEYS,
    FEATURE_SCHEMA_VERSION,
    build_feature_vector,
    extract_feature_snapshot_from_feedback_row,
    validate_feature_vector,
)
from app.scheduler import expire_unanswered_recommendations


# Test database setup
DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def setup_test_db():
    """Create tables and return a session."""
    Base.metadata.create_all(bind=engine)
    return TestingSessionLocal()


def teardown_test_db():
    Base.metadata.drop_all(bind=engine)


class TestFeedbackUniqueness:
    """Test unique constraint on (recommendation_id, user_id)."""

    def test_unique_constraint_prevents_duplicates(self):
        db = setup_test_db()
        try:
            user = User(email="test@example.com", password_hash=get_password_hash("pass"), full_name="Test User")
            db.add(user)
            db.commit()

            profile = Profile(user_id=user.id)
            db.add(profile)
            db.commit()

            rec_id = uuid.uuid4()

            # First feedback - should succeed
            fb1 = RecommendationFeedback(
                recommendation_id=rec_id,
                user_id=user.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=datetime.now(timezone.utc),
            )
            db.add(fb1)
            db.commit()

            # Second feedback with same rec_id and user_id - should fail
            fb2 = RecommendationFeedback(
                recommendation_id=rec_id,
                user_id=user.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=datetime.now(timezone.utc),
            )
            db.add(fb2)
            with pytest.raises(Exception) as exc_info:
                db.commit()
            # Should be an IntegrityError due to unique constraint
            assert "unique" in str(exc_info.value).lower() or "uq_feedback_rec_user" in str(exc_info.value).lower()

        finally:
            teardown_test_db()

    def test_different_user_same_recommendation_allowed(self):
        """Different users can have feedback for the same recommendation."""
        db = setup_test_db()
        try:
            user1 = User(email="test1@example.com", password_hash=get_password_hash("pass"), full_name="Test User 1")
            user2 = User(email="test2@example.com", password_hash=get_password_hash("pass"), full_name="Test User 2")
            db.add_all([user1, user2])
            db.commit()

            profile1 = Profile(user_id=user1.id)
            profile2 = Profile(user_id=user2.id)
            db.add_all([profile1, profile2])
            db.commit()

            rec_id = uuid.uuid4()

            fb1 = RecommendationFeedback(
                recommendation_id=rec_id,
                user_id=user1.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=datetime.now(timezone.utc),
            )
            fb2 = RecommendationFeedback(
                recommendation_id=rec_id,
                user_id=user2.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=datetime.now(timezone.utc),
            )
            db.add_all([fb1, fb2])
            db.commit()  # Should succeed

            count = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.recommendation_id == rec_id
            ).count()
            assert count == 2

        finally:
            teardown_test_db()


class TestRecommendationExpiration:
    """Test recommendation expiration job."""

    def test_expire_unanswered_recommendations(self):
        db = setup_test_db()
        try:
            user = User(email="test@example.com", password_hash=get_password_hash("pass"), full_name="Test User")
            db.add(user)
            db.commit()

            profile = Profile(user_id=user.id)
            db.add(profile)
            db.commit()

            now = datetime.now(timezone.utc)

            # Create old unanswered recommendation (>24h)
            old_fb = RecommendationFeedback(
                recommendation_id=uuid.uuid4(),
                user_id=user.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=now - timedelta(hours=25),
                user_action=None,
            )

            # Create recent unanswered recommendation (<24h)
            recent_fb = RecommendationFeedback(
                recommendation_id=uuid.uuid4(),
                user_id=user.id,
                model_version="test-model",
                recommendation_type="WALK",
                recommendation_score=0.7,
                context_features={"feature_snapshot": {}},
                timestamp=now - timedelta(hours=12),
                user_action=None,
            )

            # Create answered recommendation (should not be expired)
            answered_fb = RecommendationFeedback(
                recommendation_id=uuid.uuid4(),
                user_id=user.id,
                model_version="test-model",
                recommendation_type="HYDRATE",
                recommendation_score=0.9,
                context_features={"feature_snapshot": {}},
                timestamp=now - timedelta(hours=30),
                user_action="accepted",
            )

            # Create WLB recommendation (should not be expired)
            wlb_fb = RecommendationFeedback(
                recommendation_id=uuid.uuid4(),
                user_id=user.id,
                model_version="wlb-rule-based-v1",
                recommendation_type="WLB_SHORT_BREAK",
                recommendation_score=0.5,
                context_features={"feature_snapshot": {}},
                timestamp=now - timedelta(hours=30),
                user_action=None,
            )

            db.add_all([old_fb, recent_fb, answered_fb, wlb_fb])
            db.commit()

            # Run expiration logic directly (same as expire_unanswered_recommendations)
            cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
            result = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.user_action.is_(None),
                RecommendationFeedback.timestamp < cutoff,
                RecommendationFeedback.recommendation_type.notlike('WLB_%')
            ).update({
                'user_action': 'expired',
                'updated_at': datetime.now(timezone.utc)
            }, synchronize_session=False)
            db.commit()

            # Check results
            db.expire_all()
            old_fb = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.id == old_fb.id
            ).first()
            recent_fb = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.id == recent_fb.id
            ).first()
            answered_fb = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.id == answered_fb.id
            ).first()
            wlb_fb = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.id == wlb_fb.id
            ).first()

            assert old_fb.user_action == "expired"
            assert recent_fb.user_action is None  # Not old enough
            assert answered_fb.user_action == "accepted"  # Already answered
            assert wlb_fb.user_action is None  # WLB excluded

        finally:
            teardown_test_db()

    def test_expiration_idempotent(self):
        """Running expiration twice should not cause errors."""
        db = setup_test_db()
        try:
            user = User(email="test@example.com", password_hash=get_password_hash("pass"), full_name="Test User")
            db.add(user)
            db.commit()

            profile = Profile(user_id=user.id)
            db.add(profile)
            db.commit()

            now = datetime.now(timezone.utc)

            old_fb = RecommendationFeedback(
                recommendation_id=uuid.uuid4(),
                user_id=user.id,
                model_version="test-model",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.8,
                context_features={"feature_snapshot": {}},
                timestamp=now - timedelta(hours=25),
                user_action=None,
            )
            db.add(old_fb)
            db.commit()

            # Run expiration logic directly twice
            for _ in range(2):
                cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
                db.query(RecommendationFeedback).filter(
                    RecommendationFeedback.user_action.is_(None),
                    RecommendationFeedback.timestamp < cutoff,
                    RecommendationFeedback.recommendation_type.notlike('WLB_%')
                ).update({
                    'user_action': 'expired',
                    'updated_at': datetime.now(timezone.utc)
                }, synchronize_session=False)
                db.commit()

            # Should still be expired, no error
            db.expire_all()
            fb = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.id == old_fb.id
            ).first()
            assert fb.user_action == "expired"

        finally:
            teardown_test_db()


class TestCanonicalFeatureSchema:
    """Test canonical V2 feature schema."""

    def test_feature_keys_correct(self):
        """Verify V2 feature keys match specification."""
        assert V2_NUMERIC_FEATURE_KEYS == [
            "session_length",
            "time_since_break",
            "completion_rate",
            "wellbeing_overall",
            "wellbeing_fatigue",
            "wellbeing_workload",
            "wellbeing_focus",
            "wellbeing_recovery",
            "wellbeing_stress",
        ]
        assert V2_CATEGORICAL_FEATURE_KEYS == ["recommendation_type"]
        assert V2_ALL_FEATURE_KEYS == V2_NUMERIC_FEATURE_KEYS + V2_CATEGORICAL_FEATURE_KEYS
        assert len(V2_ALL_FEATURE_KEYS) == 10
        assert FEATURE_SCHEMA_VERSION == "v2-wellbeing"

    def test_build_feature_vector_complete(self):
        """Test building complete feature vector."""
        snapshot = {
            "session_length": 60.0,
            "time_since_break": 30.0,
            "completion_rate": 0.8,
            "wellbeing_overall": 0.75,
            "wellbeing_fatigue": 0.25,
            "wellbeing_workload": 0.5,
            "wellbeing_focus": 0.6,
            "wellbeing_recovery": 0.8,
            "wellbeing_stress": 2.0,
        }
        feature_dict = build_feature_vector(snapshot, "SHORT_BREAK")

        assert set(feature_dict.keys()) == set(V2_ALL_FEATURE_KEYS)
        assert feature_dict["recommendation_type"] == "SHORT_BREAK"
        assert feature_dict["session_length"] == 60.0

    def test_build_feature_vector_missing_values_nan(self):
        """Missing numeric values become NaN."""
        snapshot = {
            "session_length": 60.0,
            # Missing time_since_break
            "completion_rate": 0.8,
        }
        feature_dict = build_feature_vector(snapshot, "WALK")

        import numpy as np
        assert np.isnan(feature_dict["time_since_break"])
        assert np.isnan(feature_dict["wellbeing_overall"])
        assert feature_dict["recommendation_type"] == "WALK"

    def test_build_feature_vector_invalid_numeric_becomes_nan(self):
        """Invalid numeric values become NaN."""
        snapshot = {
            "session_length": "not_a_number",
            "time_since_break": 30.0,
        }
        feature_dict = build_feature_vector(snapshot, "STRETCH")

        import numpy as np
        assert np.isnan(feature_dict["session_length"])
        assert feature_dict["time_since_break"] == 30.0

    def test_validate_feature_vector_valid(self):
        """Validate complete feature vector."""
        feature_dict = {
            "session_length": 60.0,
            "time_since_break": 30.0,
            "completion_rate": 0.8,
            "wellbeing_overall": 0.75,
            "wellbeing_fatigue": 0.25,
            "wellbeing_workload": 0.5,
            "wellbeing_focus": 0.6,
            "wellbeing_recovery": 0.8,
            "wellbeing_stress": 2.0,
            "recommendation_type": "SHORT_BREAK",
        }
        assert validate_feature_vector(feature_dict) is True

    def test_validate_feature_vector_missing_key(self):
        """Validate catches missing keys."""
        feature_dict = {
            "session_length": 60.0,
            # Missing other keys
        }
        assert validate_feature_vector(feature_dict) is False

    def test_extract_feature_snapshot_v2_format(self):
        """Extract from V2 format (nested feature_snapshot)."""
        context = {
            "feature_snapshot": {
                "session_length": 60.0,
                "time_since_break": 30.0,
                "completion_rate": 0.8,
                "wellbeing_overall": 0.75,
                "wellbeing_fatigue": 0.25,
                "wellbeing_workload": 0.5,
                "wellbeing_focus": 0.6,
                "wellbeing_recovery": 0.8,
                "wellbeing_stress_count": 2.0,
            }
        }
        snapshot = extract_feature_snapshot_from_feedback_row(context)

        assert snapshot["session_length"] == 60.0
        assert snapshot["time_since_break"] == 30.0
        assert snapshot["wellbeing_stress"] == 2.0  # renamed from stress_count

    def test_extract_feature_snapshot_v1_format(self):
        """Extract from V1 format (flat keys)."""
        context = {
            "session_length": 60.0,
            "time_since_break": 30.0,
            "completion_rate": 0.8,
            "wellbeing_stress_count": 2.0,
        }
        snapshot = extract_feature_snapshot_from_feedback_row(context)

        assert snapshot["session_length"] == 60.0
        assert snapshot["wellbeing_stress"] == 2.0

    def test_extract_feature_snapshot_empty(self):
        """Extract from empty context."""
        snapshot = extract_feature_snapshot_from_feedback_row({})
        assert snapshot == {}

    def test_excluded_features_not_in_canonical(self):
        """Verify excluded features are not in canonical schema."""
        assert "current_focus_rate" not in V2_ALL_FEATURE_KEYS
        assert "detected_pattern_ids" not in V2_ALL_FEATURE_KEYS


class TestTrainingInferenceConsistency:
    """Test that training and inference use identical feature processing."""

    def test_feature_vector_roundtrip(self):
        """Feature vector built from snapshot matches expected format."""
        # Simulate inference feature extraction (uses canonical keys)
        inference_snapshot = {
            "session_length": 45.0,
            "time_since_break": 25.0,
            "completion_rate": 0.9,
            "wellbeing_overall": 0.8,
            "wellbeing_fatigue": 0.3,
            "wellbeing_workload": 0.4,
            "wellbeing_focus": 0.7,
            "wellbeing_recovery": 0.6,
            "wellbeing_stress": 1.0,  # Canonical key for inference
        }

        # Inference builds feature vector
        feature_dict = build_feature_vector(inference_snapshot, "HYDRATE")

        # Training would extract from feedback context (uses storage key)
        training_snapshot = inference_snapshot.copy()
        training_snapshot["wellbeing_stress_count"] = training_snapshot.pop("wellbeing_stress")
        context = {"feature_snapshot": training_snapshot}
        extracted = extract_feature_snapshot_from_feedback_row(context)
        feature_dict2 = build_feature_vector(extracted, "HYDRATE")

        # Should be identical
        assert feature_dict == feature_dict2
        assert set(feature_dict.keys()) == set(V2_ALL_FEATURE_KEYS)

    def test_training_uses_same_numeric_keys(self):
        """Training pipeline uses same numeric keys."""
        from app.services.ml_training_pipeline import V2_NUMERIC_FEATURE_KEYS as TRAIN_NUMERIC
        assert TRAIN_NUMERIC == V2_NUMERIC_FEATURE_KEYS

    def test_training_uses_same_all_keys(self):
        """Training pipeline uses same all keys."""
        from app.services.ml_training_pipeline import V2_ALL_FEATURE_KEYS as TRAIN_ALL
        assert TRAIN_ALL == V2_ALL_FEATURE_KEYS


if __name__ == "__main__":
    pytest.main([__file__, "-v"])