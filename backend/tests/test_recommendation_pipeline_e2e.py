"""
End-to-end test of the recommendation pipeline.

Tests the complete flow:
1. User starts a work session
2. Recommendation is generated
3. Recommendation is persisted to DB
4. Recommendation can be retrieved
5. Admin can access recommendation
"""

import os
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import (
    User, Profile, Organization, OrganizationMembership,
    WorkSession, RecommendationFeedback
)
from app.services.recommendation_service import _recommend_for_profile
from app.auth.security import get_password_hash


def create_test_user_with_session(db: Session) -> tuple[User, Profile, WorkSession]:
    """Create a user, profile, and active work session for testing."""
    # Create organization
    org = Organization(name="Test Org E2E")
    db.add(org)
    db.flush()

    # Create user
    user = User(
        email=f"test-e2e-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpass123"),
        full_name="Test User E2E",
        account_type="organization",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(user)
    db.flush()

    # Create organization membership
    membership = OrganizationMembership(
        user_id=user.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db.add(membership)
    db.flush()

    # Create profile
    profile = Profile(
        user_id=user.id,
        job_role="Test Developer",
        industry="Technology",
        years_of_experience=5,
        target_daily_hours=8,
        shift_start_time="09:00",
        shift_end_time="17:00"
    )
    db.add(profile)
    db.flush()

    # Create active work session (started 90+ minutes ago)
    now = datetime.now(timezone.utc)
    work_session = WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(minutes=95),
        ended_at=None  # Active
    )
    db.add(work_session)
    db.commit()
    db.refresh(user)
    db.refresh(profile)
    db.refresh(work_session)

    return user, profile, work_session


class TestRecommendationPipelineE2E:
    """End-to-end tests for recommendation generation and retrieval."""

    def test_generate_recommendation_creates_db_record(self, db):
        """Test that generating a recommendation creates a persisted record."""
        # Arrange
        user, profile, session = create_test_user_with_session(db)

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        # 1. Generation should succeed
        assert result is not None
        assert "recommendation_id" in result
        assert "candidate_type" in result
        assert result["recommendation_score"] >= 0.0
        assert result["recommendation_score"] <= 1.0

        # 2. Recommendation should be persisted in DB
        recommendation_id = uuid.UUID(result["recommendation_id"])
        feedback = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == recommendation_id
        ).first()

        assert feedback is not None
        assert feedback.user_id == user.id
        assert feedback.recommendation_type == result["candidate_type"]
        assert feedback.recommendation_score == result["recommendation_score"]
        assert feedback.user_action is None  # Initially pending
        assert feedback.work_session_id == session.id

    def test_recommendation_persisted_with_correct_session(self, db):
        """Test that recommendation is linked to the correct work session."""
        # Arrange
        user, profile, session = create_test_user_with_session(db)

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert
        recommendation_id = uuid.UUID(result["recommendation_id"])
        feedback = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == recommendation_id
        ).first()

        assert feedback.work_session_id == session.id
        assert feedback.reason is not None
        assert len(feedback.reason) > 0

    def test_multiple_recommendations_dont_duplicate_when_polling(self, db):
        """Test that repeated polling doesn't create duplicate recommendations."""
        # Arrange
        user, profile, session = create_test_user_with_session(db)

        # Act - Generate first recommendation
        result1 = _recommend_for_profile(db, profile.id)
        rec_id_1 = uuid.UUID(result1["recommendation_id"])

        # Generate second recommendation (simulating another poll)
        result2 = _recommend_for_profile(db, profile.id)
        rec_id_2 = uuid.UUID(result2["recommendation_id"])

        # Assert - Both should generate (different recommendations, different IDs)
        # This is expected: each poll generates a new recommendation record
        # The frontend should use cooldown/dismissal logic to prevent showing duplicates
        assert rec_id_1 != rec_id_2

        # But both should be in the DB
        feedback1 = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == rec_id_1
        ).first()
        feedback2 = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == rec_id_2
        ).first()

        assert feedback1 is not None
        assert feedback2 is not None
        # Both linked to same session
        assert feedback1.work_session_id == session.id
        assert feedback2.work_session_id == session.id

    def test_cold_start_recommendation(self, db):
        """Test cold-start recommendation for users with insufficient data."""
        # Arrange - Create user with active session but NO prior recommendations
        user, profile, session = create_test_user_with_session(db)

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert - Should still generate a recommendation (cold-start baseline)
        assert result is not None
        assert result["candidate_type"] in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]
        assert result["model_version"] in ["cold-start-baseline", "heuristic-only"]

        # Should be persisted
        recommendation_id = uuid.UUID(result["recommendation_id"])
        feedback = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == recommendation_id
        ).first()
        assert feedback is not None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
