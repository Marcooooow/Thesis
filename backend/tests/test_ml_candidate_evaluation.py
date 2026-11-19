import uuid
from datetime import datetime, timezone, timedelta
import pytest
from sqlalchemy.orm import Session

from app.models import User, Profile, RecommendationFeedback, MLModel
from app.services.ml_training_pipeline import (
    assess_data_sufficiency,
    evaluate_candidate,
    MINIMUM_TRAINING_SAMPLES
)
from app.auth.security import get_password_hash

def seed_feedback_data(db: Session, user_id: uuid.UUID, count: int):
    base_time = datetime.now(timezone.utc) - timedelta(days=30)
    for i in range(count):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=user_id,
            recommendation_id=uuid.uuid4(),
            model_version="test-v1",
            recommendation_type="SHORT_BREAK" if i % 2 == 0 else "WALK",
            recommendation_score=0.5,
            context_features={},
            user_action="accepted" if i % 3 == 0 else "dismissed",
            timestamp=base_time + timedelta(minutes=i*10),
            provenance="live"
        )
        db.add(feedback)
    db.commit()

def test_assess_data_sufficiency_insufficient(test_db):
    # Create a new test user for this test
    user = User(
        email="test_insufficient@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    seed_feedback_data(test_db, user.id, 5)

    result = assess_data_sufficiency(test_db, dataset="all")
    assert result["sufficient_for_training"] is False
    assert result["labeled_feedback"] < MINIMUM_TRAINING_SAMPLES

def test_assess_data_sufficiency_sufficient(test_db):
    user = User(
        email="test_sufficient@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    seed_feedback_data(test_db, user.id, MINIMUM_TRAINING_SAMPLES + 5)

    result = assess_data_sufficiency(test_db, dataset="all")
    assert result["sufficient_for_training"] is True
    assert result["labeled_feedback"] >= MINIMUM_TRAINING_SAMPLES

def test_evaluate_candidate_missing_model(test_db):
    fake_id = uuid.uuid4()
    result = evaluate_candidate(test_db, fake_id)
    assert result["result"] == "FAILED"
    assert "reason" in result
