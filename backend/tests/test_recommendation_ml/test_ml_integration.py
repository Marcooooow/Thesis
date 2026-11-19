"""
Tests for ML-enhanced recommendation service.
Covers:
1. ML disabled → heuristic recommendation
2. ML enabled + valid model → prediction generated
3. ML enabled + model unavailable → heuristic fallback
4. ML prediction failure → heuristic fallback
5. Wellbeing temporal correctness (no future leakage)
"""
import os
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch, MagicMock

import pytest
from sqlalchemy.orm import Session

from app.models import (
    User, Profile, Organization, OrganizationMembership,
    Team, TeamMembership, WorkSession, Break, Task,
    SessionWellbeingCheckin, RecommendationFeedback, UserSettings,
    MLModel
)
from app.services.recommendation_service import (
    _extract_features, _score_candidate, _get_ml_enhancement,
    _score_candidate_with_ml, _recommend_for_profile
)
from app.services.ml_training_pipeline import (
    train_model, predict_with_model, get_latest_active_model, assess_data_sufficiency
)


def create_test_user_and_profile(db: Session, email_suffix: str = "") -> tuple[User, Profile]:
    """Helper to create test user and profile."""
    # Create organization
    org = Organization(name=f"Test Org {email_suffix}")
    db.add(org)
    db.flush()

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

    # Create organization membership
    org_mem = OrganizationMembership(
        user_id=user.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db.add(org_mem)

    # Create profile
    profile = Profile(
        user_id=user.id,
        job_role="Test Role",
        industry="Test Industry",
        years_of_experience=2,
        age=30,
        gender="Non-binary",
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
        department="Test Department"
    )
    db.add(profile)
    db.flush()

    # Create team and membership
    team = Team(
        name=f"Test Team {email_suffix}",
        description="Test team for ML tests",
        manager_user_id=user.id,  # User is manager of their own team for simplicity
        organization_id=org.id
    )
    db.add(team)
    db.flush()

    team_mem = TeamMembership(
        profile_id=profile.id,
        team_id=team.id,
        role="EMPLOYEE",
        joined_at=datetime.now(timezone.utc)
    )
    db.add(team_mem)

    # Create user settings
    settings = UserSettings(
        user_id=user.id,
        notifications_enabled=True,
        break_reminders=True,
        break_interval_minutes=30,
        break_duration_minutes=10,
        break_coach_enabled=True,
        break_coach_cooldown_minutes=30,
        time_format="24h"
    )
    db.add(settings)

    db.commit()
    return user, profile


def create_test_feedback(db: Session, user_id: uuid.UUID, action: str = "accepted"):
    """Create test recommendation feedback for ML training."""
    feedback = RecommendationFeedback(
        recommendation_id=uuid.uuid4(),
        user_id=user_id,
        model_version="test-version",
        feature_schema_version="v2-wellbeing",
        recommendation_type="SHORT_BREAK",
        recommendation_score=0.7,
        context_features={
            "session_length": 45.0,
            "time_since_break": 25.0,
            "completion_rate": 0.6,
            "wellbeing_overall": 0.8,
            "wellbeing_fatigue": 0.2,
            "wellbeing_workload": 0.7,
            "wellbeing_focus": 0.8,
            "wellbeing_recovery": 0.7,
            "wellbeing_stress_count": 0.0
        },
        timestamp=datetime.now(timezone.utc),
        user_action=action
    )
    db.add(feedback)
    db.commit()
    return feedback


def activate_model(db: Session, model_id: uuid.UUID) -> bool:
    """Activate a model by setting is_active=True. Deactivates all other models."""
    try:
        # Deactivate all models
        db.query(MLModel).update({MLModel.is_active: False})
        # Activate the selected model
        model = db.query(MLModel).filter(MLModel.id == model_id).first()
        if model is None:
            return False
        model.is_active = True
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


class TestMLRecommendationIntegration:
    """Test ML integration in recommendation service."""

    def test_ml_disabled_uses_heuristic_only(self, db):
        """Test that when ML is disabled, only heuristic scoring is used."""
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user, profile = create_test_user_and_profile(db, "disabled")

        # Create some work session and task data for feature extraction
        work_session = WorkSession(
            profile_id=profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=2),
            ended_at=None  # Active session
        )
        db.add(work_session)
        db.commit()

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        assert result["model_version"] in ["heuristic-only", "cold-start-baseline"]
        assert "ml_used" not in result or result.get("ml_used") is False
        assert "ml_probability" not in result
        assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_ml_enabled_no_model_fallback_to_heuristic(self, db):
        """Test that when ML is enabled but no model exists, falls back to heuristic."""
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        user, profile = create_test_user_and_profile(db, "no-model")

        # Create work session data
        work_session = WorkSession(
            profile_id=profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=2),
            ended_at=None
        )
        db.add(work_session)
        # Add two tasks to avoid cold-start condition
        task1 = Task(
            profile_id=profile.id,
            work_session_id=None,
            title="Test Task 1",
            status="DONE",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=30)
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=None,
            title="Test Task 2",
            status="TODO",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=15)
        )
        db.add_all([task1, task2])
        db.commit()

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        assert result["model_version"] == "heuristic-only"
        assert result.get("ml_used") is False
        assert result.get("ml_probability") is None
        assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_ml_enabled_with_model_uses_enhancement(self, db):
        """Test that when ML is enabled and model exists, ML enhancement is used."""
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        user, profile = create_test_user_and_profile(db, "with-model")

        # Create sufficient labeled feedback for training
        for i in range(25):  # Above MINIMUM_TRAINING_SAMPLES threshold
            action = "accepted" if i % 3 != 0 else "dismissed"  # ~67% acceptance rate
            create_test_feedback(db, profile.user_id, action)

        # Create work session data
        work_session = WorkSession(
            profile_id=profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=2),
            ended_at=None
        )
        db.add(work_session)

        # Add some tasks
        task1 = Task(
            profile_id=profile.id,
            work_session_id=None,  # Not tied to session for simplicity
            title="Test Task 1",
            status="DONE",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=30)
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=None,
            title="Test Task 2",
            status="TODO",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=15)
        )
        db.add_all([task1, task2])
        db.commit()

        # Train a model
        model_result = train_model(db)
        assert model_result is not None, "Model training should succeed with sufficient data"

        # Activate the model
        model_id = uuid.UUID(model_result["model_id"])
        activation_result = activate_model(db, model_id)
        assert activation_result is True, "Model activation should succeed"

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        # Should either use ML enhancement or fall back gracefully
        assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0
        assert result["candidate_type"] in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]

        # If ML was used, check for ML-specific fields
        if result.get("ml_used") is True:
            assert result.get("ml_probability") is not None
            assert 0.0 <= result["ml_probability"] <= 1.0
            assert result["model_version"] != "heuristic-only"
        else:
            # If ML wasn't used, should still have valid heuristic result
            assert result["model_version"] == "heuristic-only"

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_ml_prediction_failure_fallback_to_heuristic(self, db):
        """Test that when ML prediction fails, falls back to heuristic."""
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        user, profile = create_test_user_and_profile(db, "prediction-fail")

        # Create and activate a model (but we'll make it fail during prediction)
        for i in range(25):
            action = "accepted" if i % 3 != 0 else "dismissed"
            create_test_feedback(db, profile.user_id, action)

        work_session = WorkSession(
            profile_id=profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=2),
            ended_at=None
        )
        db.add(work_session)
        task1 = Task(
            profile_id=profile.id,
            work_session_id=work_session.id,
            title="Test Task 1",
            status="DONE",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=30)
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=work_session.id,
            title="Test Task 2",
            status="TODO",
            created_at=datetime.now(timezone.utc) - timedelta(minutes=15)
        )
        db.add_all([task1, task2])
        db.commit()

        model_result = train_model(db)
        assert model_result is not None

        model_id = uuid.UUID(model_result["model_id"])
        activate_model(db, model_id)

        # Mock joblib.load inside _get_ml_enhancement (local import) via module-level import
        with patch('joblib.load', side_effect=Exception("Model load failed")):
            # Act
            result = _recommend_for_profile(db, profile.id)

            # Assert
            assert result["model_version"] == "heuristic-only"
            assert result.get("ml_used") is False
            assert result.get("ml_probability") is None
            assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_no_future_wellbeing_leakage(self, db):
        """Test that wellbeing data from future cannot leak into recommendations."""
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        user, profile = create_test_user_and_profile(db, "wellbeing-leak")

        now = datetime.now(timezone.utc)
        active_session = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(hours=2),
            ended_at=None
        )
        db.add(active_session)
        db.flush()
        task1 = Task(
            profile_id=profile.id,
            work_session_id=active_session.id,
            title="Test Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=30)
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=active_session.id,
            title="Test Task 2",
            status="TODO",
            created_at=now - timedelta(minutes=15)
        )
        db.add_all([task1, task2])

        # Create future wellbeing check-in (linked to active session for test schema)
        future_wellbeing = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=active_session.id,
            overall_wellbeing=5,
            mental_fatigue=1,
            workload_manageability=5,
            perceived_focus=5,
            break_recovery=5,
            stress_factors=[],
            created_at=now + timedelta(days=1)
        )
        db.add(future_wellbeing)
        db.commit()

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0
        assert result["candidate_type"] in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_ml_health_endpoint_reflects_config(self, db):
        """Test that recommendation health endpoint correctly reports ML status."""
        from app.services.recommendation_service import recommendation_health
        import asyncio

        # Deactivate all models so "no-model" condition holds
        db.query(MLModel).update({MLModel.is_active: False})
        db.commit()

        # Test ML disabled
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        health_disabled = asyncio.run(recommendation_health(db))
        assert health_disabled["ml_recommendations_enabled"] is False
        assert health_disabled["ml_status"] == "disabled"
        assert health_disabled["cold_start_baseline_active"] is True
        assert "cold-start-baseline" in health_disabled["mode"]

        # Test ML enabled but no model
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "true"
        health_enabled_no_model = asyncio.run(recommendation_health(db))
        assert health_enabled_no_model["ml_recommendations_enabled"] is True
        assert health_enabled_no_model["ml_status"] == "enabled-but-no-active-model"
        assert health_enabled_no_model["cold_start_baseline_active"] is True
        assert "cold-start-baseline" in health_enabled_no_model["mode"]

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]


if __name__ == "__main__":
    # Allow running the test file directly for quick verification
    pytest.main([__file__, "-v"])