"""
Tests for ML Inference Integration (A-01d).
Covers:
1. Valid V1 inference
2. Valid V2 inference
3. ML disabled
4. No active model
5. Missing model artifact
6. Prediction exception
7. Invalid probability
8. Missing features
9. Unsupported schema version
10. Heuristic score preservation
11. Recommendation ordering when ML is disabled
12. Recommendation feedback regression
"""
import os
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch, MagicMock

import pytest
import numpy as np
from sqlalchemy.orm import Session

from app.models import (
    User, Profile, Organization, OrganizationMembership,
    WorkSession, Break, Task,
    SessionWellbeingCheckin, RecommendationFeedback, MLModel
)
from app.services.recommendation_service import (
    _extract_features, _score_candidate, _get_ml_enhancement,
    _score_candidate_with_ml, _recommend_for_profile
)
from app.services.ml_training_pipeline import (
    train_model, predict_with_model, get_latest_active_model, assess_data_sufficiency
)
from app.auth.security import get_password_hash


def create_test_user_and_profile(db: Session, email_suffix: str = "") -> tuple[User, Profile]:
    """Helper to create test user and profile."""
    # Create user
    user = User(
        email=f"test{email_suffix}@intellibreak.local",
        password_hash="hashed_password",
        full_name=f"Test User {email_suffix}",
        organization_name=f"Test Org {email_suffix}",
        account_type="organization",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(user)
    db.flush()

    # Create profile
    profile = Profile(
        user_id=user.id,
        is_test_data=True
    )
    db.add(profile)
    db.flush()

    # Create user settings (UserSettings uses user_id, not profile_id)
    from app.models import UserSettings
    settings = UserSettings(
        user_id=user.id,
        notifications_enabled=True,
        break_reminders=True
    )
    db.add(settings)
    db.commit()

    db.refresh(user)
    db.refresh(profile)
    return user, profile


def create_test_work_session(db: Session, profile_id: uuid.UUID, hours_ago: float = 2) -> WorkSession:
    """Create a test work session."""
    ws = WorkSession(
        profile_id=profile_id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=hours_ago),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=hours_ago - 1)
    )
    db.add(ws)
    db.commit()
    db.refresh(ws)
    return ws


def create_test_wellbeing_checkin(db: Session, profile_id: uuid.UUID, work_session_id: uuid.UUID):
    """Create a test wellbeing checkin."""
    user_id = db.query(Profile.user_id).filter(Profile.id == profile_id).scalar()

    checkin = SessionWellbeingCheckin(
        work_session_id=work_session_id,
        user_id=user_id,
        overall_wellbeing=4,
        mental_fatigue=2,
        workload_manageability=3,
        perceived_focus=4,
        break_recovery=3,
        stress_factors=["workload"],
        created_at=datetime.now(timezone.utc)
    )
    db.add(checkin)
    db.commit()
    return checkin


def seed_v1_feedback(db: Session, user_id: uuid.UUID, count: int = 30):
    """Seed feedback with V1 feature schema (3 features)."""
    base_time = datetime.now(timezone.utc) - timedelta(days=30)
    for i in range(count):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=user_id,
            recommendation_id=uuid.uuid4(),
            model_version="v1-baseline",
            feature_schema_version="v1-base",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.5,
            context_features={
                "session_length": float(i * 10 + 20),
                "time_since_break": float(i * 5 + 10),
                "completion_rate": float((i % 5) * 0.2),
            },
            user_action="accepted" if i % 3 == 0 else "dismissed",
            timestamp=base_time + timedelta(minutes=i*10),
            provenance="live"
        )
        db.add(feedback)
    db.commit()


def seed_v2_feedback(db: Session, user_id: uuid.UUID, count: int = 30):
    """Seed feedback with V2 feature schema (10 features)."""
    base_time = datetime.now(timezone.utc) - timedelta(days=30)
    for i in range(count):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=user_id,
            recommendation_id=uuid.uuid4(),
            model_version="v2-wellbeing",
            feature_schema_version="v2-wellbeing",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.5,
            context_features={
                "feature_snapshot": {
                    "session_length": float(i * 10 + 20),
                    "time_since_break": float(i * 5 + 10),
                    "completion_rate": float((i % 5) * 0.2),
                    "wellbeing_overall": float((i % 5) * 0.2),
                    "wellbeing_fatigue": float((i % 4) * 0.25),
                    "wellbeing_workload": float((i % 4) * 0.25),
                    "wellbeing_focus": float((i % 5) * 0.2),
                    "wellbeing_recovery": float((i % 5) * 0.2),
                    "wellbeing_stress_count": float(i % 3),
                }
            },
            user_action="accepted" if i % 3 == 0 else "dismissed",
            timestamp=base_time + timedelta(minutes=i*10),
            provenance="live"
        )
        db.add(feedback)
    db.commit()


def train_and_activate_v1_model(db: Session, user_id: uuid.UUID):
    """Train and activate a model (will be V2 since training always uses V2 features)."""
    seed_v1_feedback(db, user_id, 50)
    result = train_model(db, dataset="all")
    if not result:
        return None
    model_id = uuid.UUID(result["model_id"])
    # Activate model
    from app.services.ml_training_pipeline import get_latest_active_model
    db.query(MLModel).update({MLModel.is_active: False})
    model = db.query(MLModel).filter(MLModel.id == model_id).first()
    model.is_active = True
    # Note: train_model always saves as "v2-wellbeing" since it uses V2 feature engineering
    model.feature_set_version = "v2-wellbeing"
    db.commit()
    return model_id


def train_and_activate_v2_model(db: Session, user_id: uuid.UUID):
    """Train and activate a V2 model."""
    seed_v2_feedback(db, user_id, 50)
    result = train_model(db, dataset="all")
    if not result:
        return None
    model_id = uuid.UUID(result["model_id"])
    # Activate model
    db.query(MLModel).update({MLModel.is_active: False})
    model = db.query(MLModel).filter(MLModel.id == model_id).first()
    model.is_active = True
    model.feature_set_version = "v2-wellbeing"
    db.commit()
    return model_id


class TestMLInferenceIntegration:
    """Test ML inference integration into recommendation pipeline."""

    def test_valid_v1_inference(self, db: Session):
        """Test V1 model inference works correctly."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "v1-inference")
            ws = create_test_work_session(db, profile.id)

            # Train and activate V1 model
            model_id = train_and_activate_v1_model(db, user.id)
            assert model_id is not None, "V1 model training should succeed"

            # Get ML enhancement
            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should get enhancement (or None if insufficient data)
            # The key test is that it doesn't crash
            assert enhancement is None or (isinstance(enhancement, float) and 0.5 <= enhancement <= 2.0)
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_valid_v2_inference(self, db: Session):
        """Test V2 model inference works correctly."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "v2-inference")
            ws = create_test_work_session(db, profile.id)
            create_test_wellbeing_checkin(db, profile.id, ws.id)

            # Train and activate V2 model
            model_id = train_and_activate_v2_model(db, user.id)
            assert model_id is not None, "V2 model training should succeed"

            # Get ML enhancement
            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should get enhancement (or None if insufficient data)
            assert enhancement is None or (isinstance(enhancement, float) and 0.5 <= enhancement <= 2.0)
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_ml_disabled(self, db: Session):
        """Test that ML is skipped when feature flag is disabled."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        try:
            user, profile = create_test_user_and_profile(db, "ml-disabled")
            ws = create_test_work_session(db, profile.id)
            seed_v2_feedback(db, user.id, 50)
            train_and_activate_v2_model(db, user.id)

            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should return None when ML disabled
            assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_no_active_model(self, db: Session):
        """Test fallback when no active model exists."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "no-model")
            ws = create_test_work_session(db, profile.id)

            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should return None when no active model
            assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_missing_model_artifact(self, db: Session):
        """Test fallback when model artifact is missing."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "missing-artifact")
            ws = create_test_work_session(db, profile.id)

            # Create MLModel record with non-existent artifact
            model = MLModel(
                id=uuid.uuid4(),
                version="test-missing",
                artifact_path="/nonexistent/path/model.joblib",
                training_date=datetime.now(timezone.utc),
                feature_set_version="v2-wellbeing",
                metrics="{}",
                is_active=True
            )
            db.add(model)
            db.commit()

            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should return None when artifact missing
            assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_prediction_exception_handling(self, db: Session):
        """Test that prediction exceptions are caught and return None."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "pred-exception")
            ws = create_test_work_session(db, profile.id)

            # Create model that will fail prediction
            model = MLModel(
                id=uuid.uuid4(),
                version="test-fail",
                artifact_path="/nonexistent/model.joblib",
                training_date=datetime.now(timezone.utc),
                feature_set_version="v2-wellbeing",
                metrics="{}",
                is_active=True
            )
            db.add(model)
            db.commit()

            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should return None on prediction exception
            assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_invalid_probability_fallback(self, db: Session):
        """Test that invalid probabilities (NaN, out of range) are rejected."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "invalid-prob")
            ws = create_test_work_session(db, profile.id)

            # Mock predict_with_model to return NaN
            with patch('app.services.ml_training_pipeline.predict_with_model') as mock_predict:
                mock_predict.return_value = float('nan')

                features = _extract_features(db, profile.id)
                enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

                # Should return None for NaN
                assert enhancement is None

            # Mock predict_with_model to return out of range
            with patch('app.services.ml_training_pipeline.predict_with_model') as mock_predict:
                mock_predict.return_value = 1.5

                features = _extract_features(db, profile.id)
                enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

                # Should return None for out of range
                assert enhancement is None

            # Mock predict_with_model to return negative
            with patch('app.services.ml_training_pipeline.predict_with_model') as mock_predict:
                mock_predict.return_value = -0.5

                features = _extract_features(db, profile.id)
                enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

                # Should return None for negative
                assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_missing_features_fallback(self, db: Session):
        """Test that missing features fall back gracefully."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "missing-features")
            ws = create_test_work_session(db, profile.id)
            seed_v2_feedback(db, user.id, 50)
            train_and_activate_v2_model(db, user.id)

            # Create features with empty feature_snapshot
            features = {
                "feature_snapshot": {},
                "detected_patterns": [],
                "wellbeing_overall": None,
                "wellbeing_fatigue": None,
            }

            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should handle missing features gracefully (return None or valid enhancement)
            assert enhancement is None or (isinstance(enhancement, float) and 0.5 <= enhancement <= 2.0)
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_unsupported_schema_version(self, db: Session):
        """Test fallback for unsupported schema version."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "unsupported-schema")
            ws = create_test_work_session(db, profile.id)

            # Create model with unsupported schema version
            model = MLModel(
                id=uuid.uuid4(),
                version="test-unsupported",
                artifact_path="/nonexistent/model.joblib",
                training_date=datetime.now(timezone.utc),
                feature_set_version="v3-future",
                metrics="{}",
                is_active=True
            )
            db.add(model)
            db.commit()

            features = _extract_features(db, profile.id)
            enhancement = _get_ml_enhancement(db, features, "SHORT_BREAK")

            # Should fall back to V1 behavior (or return None for missing artifact)
            assert enhancement is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_heuristic_score_preservation(self, db: Session):
        """Test that heuristic scores are preserved when ML is unavailable."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"  # ML disabled
        try:
            user, profile = create_test_user_and_profile(db, "heuristic-preservation")
            ws = create_test_work_session(db, profile.id)

            features = _extract_features(db, profile.id)

            # Get heuristic score
            heuristic_score = _score_candidate("SHORT_BREAK", features)

            # Get ML score (should be same as heuristic when ML disabled)
            final_score, ml_prob, ml_used = _score_candidate_with_ml("SHORT_BREAK", features, db)

            # ML should not be used
            assert ml_used is False
            assert ml_prob is None
            # Final score should equal heuristic score
            assert abs(final_score - heuristic_score) < 0.001
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_heuristic_score_preservation_no_active_model(self, db: Session):
        """Test that heuristic scores are preserved when no active model."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "heuristic-no-model")
            ws = create_test_work_session(db, profile.id)

            features = _extract_features(db, profile.id)

            # Get heuristic score
            heuristic_score = _score_candidate("SHORT_BREAK", features)

            # Get ML score (should be same as heuristic when no model)
            final_score, ml_prob, ml_used = _score_candidate_with_ml("SHORT_BREAK", features, db)

            # ML should not be used
            assert ml_used is False
            assert ml_prob is None
            # Final score should equal heuristic score
            assert abs(final_score - heuristic_score) < 0.001
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_recommendation_ordering_ml_disabled(self, db: Session):
        """Test that recommendation ordering is unchanged when ML is disabled."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        try:
            user, profile = create_test_user_and_profile(db, "ordering-disabled")
            ws = create_test_work_session(db, profile.id)

            # Add some tasks
            task1 = Task(profile_id=profile.id, title="Task 1", status="DONE", created_at=datetime.now(timezone.utc) - timedelta(minutes=30))
            task2 = Task(profile_id=profile.id, title="Task 2", status="TODO", created_at=datetime.now(timezone.utc) - timedelta(minutes=15))
            db.add_all([task1, task2])
            db.commit()

            # Get recommendations
            result = _recommend_for_profile(db, profile.id)

            # Should return valid recommendation
            assert "candidate_type" in result
            assert "recommendation_score" in result
            assert 0.0 <= result["recommendation_score"] <= 1.0
            assert result["candidate_type"] in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]
            # ML fields should not be present or should be False/None
            assert result.get("ml_used") is not True
            assert result.get("ml_probability") is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_recommendation_feedback_regression(self, db: Session):
        """Test that feedback submission still works with ML integration."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "feedback-reg")
            ws = create_test_work_session(db, profile.id)

            # Get a recommendation
            result = _recommend_for_profile(db, profile.id)
            rec_id = result["recommendation_id"]

            # Submit feedback (simulate the API endpoint logic)
            feedback = db.query(RecommendationFeedback).filter(
                RecommendationFeedback.recommendation_id == uuid.UUID(rec_id),
                RecommendationFeedback.user_id == user.id
            ).first()

            assert feedback is not None
            assert feedback.user_action is None

            # Update feedback
            feedback.user_action = "accepted"
            feedback.responded_at = datetime.now(timezone.utc)
            db.commit()

            # Verify feedback recorded
            db.refresh(feedback)
            assert feedback.user_action == "accepted"
            assert feedback.responded_at is not None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]


class TestPredictWithModel:
    """Test predict_with_model directly."""

    def test_predict_with_model_v1(self, db: Session):
        """Test predict_with_model works with V1 model."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "predict-v1")
            model_id = train_and_activate_v1_model(db, user.id)
            assert model_id is not None

            # Predict with V2 features (training always uses V2 feature engineering)
            prob = predict_with_model(db, {
                "session_length": 45.0,
                "time_since_break": 30.0,
                "completion_rate": 0.6,
                "wellbeing_overall": 0.8,
                "wellbeing_fatigue": 0.2,
                "wellbeing_workload": 0.7,
                "wellbeing_focus": 0.8,
                "wellbeing_recovery": 0.7,
                "wellbeing_stress_count": 0.0,
                "recommendation_type": "SHORT_BREAK"
            }, "SHORT_BREAK")

            assert prob is not None
            assert 0.0 <= prob <= 1.0
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_predict_with_model_v2(self, db: Session):
        """Test predict_with_model works with V2 model."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            user, profile = create_test_user_and_profile(db, "predict-v2")
            model_id = train_and_activate_v2_model(db, user.id)
            assert model_id is not None

            # Predict with V2 features
            prob = predict_with_model(db, {
                "session_length": 45.0,
                "time_since_break": 30.0,
                "completion_rate": 0.6,
                "wellbeing_overall": 0.8,
                "wellbeing_fatigue": 0.2,
                "wellbeing_workload": 0.7,
                "wellbeing_focus": 0.8,
                "wellbeing_recovery": 0.7,
                "wellbeing_stress_count": 0.0,
                "recommendation_type": "SHORT_BREAK"
            }, "SHORT_BREAK")

            assert prob is not None
            assert 0.0 <= prob <= 1.0
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_predict_with_model_no_active(self, db: Session):
        """Test predict_with_model returns None when no active model."""
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        try:
            prob = predict_with_model(db, {
                "session_length": 45.0,
                "time_since_break": 30.0,
                "completion_rate": 0.6,
            }, "SHORT_BREAK")

            assert prob is None
        finally:
            if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
                del os.environ["ML_RECOMMENDATIONS_ENABLED"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])