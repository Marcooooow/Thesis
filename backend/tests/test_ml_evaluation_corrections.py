import uuid
from datetime import datetime, timezone, timedelta
import pytest
from sqlalchemy.orm import Session

from app.models import User, Profile, RecommendationFeedback, MLModel
from app.services.ml_training_pipeline import (
    assess_data_sufficiency,
    evaluate_candidate,
    evaluate_model_on_test_set,
    evaluate_heuristic_baseline,
    MINIMUM_TRAINING_SAMPLES,
    RANDOM_STATE
)
from app.auth.security import get_password_hash

def seed_feedback_data(db: Session, user_id: uuid.UUID, count: int):
    base_time = datetime.now(timezone.utc) - timedelta(days=30)
    import json
    for i in range(count):
        # Create realistic context_features with feature_snapshot (V2 format)
        context = {
            "feature_snapshot": {
                "session_length": float(i * 10 + 20),  # 20-200+ min sessions
                "time_since_break": float(i * 5 + 10),  # 10+ min since break
                "completion_rate": float((i % 5) * 0.2),  # 0.0-0.8
                "wellbeing_overall": float((i % 5) * 0.2),  # 0.0-0.8
                "wellbeing_fatigue": float((i % 4) * 0.25),  # 0.0-0.75
                "wellbeing_workload": float((i % 4) * 0.25),  # 0.0-0.75
                "wellbeing_focus": float((i % 5) * 0.2),  # 0.0-0.8
                "wellbeing_recovery": float((i % 5) * 0.2),  # 0.0-0.8
                "wellbeing_stress_count": float(i % 3),  # 0-2
            }
        }
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=user_id,
            recommendation_id=uuid.uuid4(),
            model_version="test-v1",
            recommendation_type="SHORT_BREAK" if i % 2 == 0 else "WALK",
            recommendation_score=0.5,
            context_features=context,
            user_action="accepted" if i % 3 == 0 else "dismissed",
            timestamp=base_time + timedelta(minutes=i*10),
            provenance="live"
        )
        db.add(feedback)
    db.commit()

def test_evaluate_heuristic_baseline(test_db):
    user = User(
        email="test_heuristic@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = User(
        email="test_heuristic_2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([user, user2])
    test_db.commit()
    test_db.refresh(user)
    test_db.refresh(user2)

    # Seed enough data for train/test split across both users
    seed_feedback_data(test_db, user.id, (MINIMUM_TRAINING_SAMPLES + 20) // 2)
    seed_feedback_data(test_db, user2.id, (MINIMUM_TRAINING_SAMPLES + 20) // 2)

    result = evaluate_heuristic_baseline(test_db, dataset="all")

    # Should return metrics for comparison
    assert result is not None
    assert "f1" in result
    assert "test_sample_count" in result
    assert result["test_sample_count"] >= 5
    assert "evaluation_scope" in result
    assert result["evaluation_scope"] == "SHORT_BREAK only"

def test_evaluate_candidate_insufficient_data(test_db):
    fake_id = uuid.uuid4()
    result = evaluate_candidate(test_db, fake_id)
    assert result["result"] == "FAILED"
    assert "reason" in result

def test_evaluate_candidate_no_model(test_db):
    fake_id = uuid.uuid4()
    result = evaluate_model_on_test_set(test_db, fake_id)
    assert result is None

def test_evaluate_candidate_acceptance_criteria_structure(test_db):
    """Test that evaluation returns proper acceptance criteria structure."""
    user = User(
        email="test_eval_structure@example.com",
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

    seed_feedback_data(test_db, user.id, MINIMUM_TRAINING_SAMPLES + 20)

    # Train a model first to have something to evaluate
    # This test just verifies the structure of the response
    from app.services.ml_training_pipeline import train_model

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_candidate(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        # Verify acceptance criteria structure
        assert "acceptance_criteria" in result
        assert "f1_gt_05" in result["acceptance_criteria"]
        assert "sufficient_test_samples" in result["acceptance_criteria"]
        assert "beats_heuristic" in result["acceptance_criteria"]
        assert "beats_or_matches_active" in result["acceptance_criteria"]

        # Verify comparison structure
        assert "comparison" in result
        assert "active_model" in result["comparison"]
        assert "heuristic_baseline" in result["comparison"]

def test_evaluate_candidate_comparison_fields(test_db):
    """Test that evaluation comparison includes required fields."""
    user = User(
        email="test_eval_comparison@example.com",
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

    seed_feedback_data(test_db, user.id, MINIMUM_TRAINING_SAMPLES + 20)

    from app.services.ml_training_pipeline import train_model

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_candidate(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        # If heuristic baseline comparison exists, it should have improvement field
        if result["comparison"]["heuristic_baseline"]:
            hb = result["comparison"]["heuristic_baseline"]
            assert "f1" in hb
            assert "improvement" in hb

def test_evaluate_model_on_test_set_requires_sufficient_data(test_db):
    user = User(
        email="test_eval_insufficient@example.com",
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

    seed_feedback_data(test_db, user.id, 5)  # Insufficient for train/test split

    from app.services.ml_training_pipeline import train_model

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_model_on_test_set(test_db, uuid.UUID(model_result["model_id"]), dataset="all")
        # Should be None or FAILED due to insufficient test samples
        assert result is None or result.get("test_sample_count", 0) < 10


def test_group_aware_split_prevents_user_leakage(test_db):
    """Test that group-aware split separates users between train and test."""
    user1 = User(
        email="test_split_1@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = User(
        email="test_split_2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([user1, user2])
    test_db.commit()
    test_db.refresh(user1)
    test_db.refresh(user2)

    seed_feedback_data(test_db, user1.id, 30)
    seed_feedback_data(test_db, user2.id, 30)

    from app.services.ml_training_pipeline import train_model, evaluate_model_on_test_set

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_model_on_test_set(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        if result:
            # Verify group-aware split was used (or fallback noted)
            assert "group_aware_split_used" in result
            assert "train_unique_users" in result
            assert "test_unique_users" in result
            # Test set should have at least 1 user
            assert result["test_unique_users"] >= 1
            assert result["train_unique_users"] >= 1
            # Total users should be 2
            assert result["train_unique_users"] + result["test_unique_users"] == 2


def test_insufficient_users_fallback(test_db):
    """Test fallback when only 1 user is available."""
    user = User(
        email="test_fallback@example.com",
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

    seed_feedback_data(test_db, user.id, 30)

    from app.services.ml_training_pipeline import train_model, evaluate_model_on_test_set

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_model_on_test_set(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        if result:
            # Should fall back to stratified split
            assert "group_aware_split_used" in result
            assert result["group_aware_split_used"] is False


def test_f1_threshold_provisional_metadata(test_db):
    """Test that evaluation includes provisional F1 threshold metadata."""
    user1 = User(
        email="test_f1_1@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = User(
        email="test_f1_2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([user1, user2])
    test_db.commit()
    test_db.refresh(user1)
    test_db.refresh(user2)

    seed_feedback_data(test_db, user1.id, 30)
    seed_feedback_data(test_db, user2.id, 30)

    from app.services.ml_training_pipeline import train_model, evaluate_model_on_test_set

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_model_on_test_set(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        if result:
            assert "f1_threshold" in result
            assert result["f1_threshold"] == 0.5
            assert "f1_threshold_status" in result
            assert result["f1_threshold_status"] == "provisional"
            assert "f1_threshold_note" in result
            assert "provisional" in result["f1_threshold_note"].lower()


def test_heuristic_evaluation_scope(test_db):
    """Test that heuristic evaluation documents its scope limitation."""
    user1 = User(
        email="test_scope_1@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = User(
        email="test_scope_2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([user1, user2])
    test_db.commit()
    test_db.refresh(user1)
    test_db.refresh(user2)

    seed_feedback_data(test_db, user1.id, 30)
    seed_feedback_data(test_db, user2.id, 30)

    result = evaluate_heuristic_baseline(test_db, dataset="all")

    assert result is not None
    assert "evaluation_scope" in result
    assert result["evaluation_scope"] == "SHORT_BREAK only"
    assert "evaluation_scope_note" in result
    assert "SHORT_BREAK" in result["evaluation_scope_note"]


def test_evaluate_candidate_single_user_pending(test_db):
    """Test that candidate evaluation returns PENDING for single user (no independent evaluation)."""
    user = User(
        email="test_single_user@example.com",
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

    seed_feedback_data(test_db, user.id, 50)

    from app.services.ml_training_pipeline import train_model, evaluate_candidate

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_candidate(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        # Should be PENDING because no independent user-level evaluation possible
        assert result["result"] == "PENDING"
        assert "independent_evaluation" in result["acceptance_criteria"]
        assert result["acceptance_criteria"]["independent_evaluation"] is False
        assert "reason" in result
        assert "insufficient unique users" in result["reason"].lower() or "leakage" in result["reason"].lower()


def test_evaluate_candidate_multi_user_passes(test_db):
    """Test that candidate evaluation can PASS with multiple users and independent evaluation."""
    user1 = User(
        email="test_multi_1@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = User(
        email="test_multi_2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([user1, user2])
    test_db.commit()
    test_db.refresh(user1)
    test_db.refresh(user2)

    seed_feedback_data(test_db, user1.id, 40)
    seed_feedback_data(test_db, user2.id, 40)

    from app.services.ml_training_pipeline import train_model, evaluate_candidate

    model_result = train_model(test_db, dataset="all")
    if model_result:
        result = evaluate_candidate(test_db, uuid.UUID(model_result["model_id"]), dataset="all")

        # Should be PASSED or FAILED (not PENDING) because independent evaluation available
        assert result["result"] in ["PASSED", "FAILED"]
        assert "independent_evaluation" in result["acceptance_criteria"]
        assert result["acceptance_criteria"]["independent_evaluation"] is True


def test_v1_feature_schema_compatibility():
    """Test that V1 feature schema matches actual V1 model artifacts."""
    from app.services.feature_schema import V1_NUMERIC_FEATURE_KEYS, V1_CATEGORICAL_FEATURE_KEYS, V1_ALL_FEATURE_KEYS

    # V1 models used exactly these 3 features
    assert V1_NUMERIC_FEATURE_KEYS == ["session_length", "time_since_break", "completion_rate"]
    assert V1_CATEGORICAL_FEATURE_KEYS == []
    assert V1_ALL_FEATURE_KEYS == ["session_length", "time_since_break", "completion_rate"]


def test_v2_feature_schema_differs_from_v1():
    """Test that V2 feature schema differs from V1 (adds wellbeing features)."""
    from app.services.feature_schema import V1_NUMERIC_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS

    # V2 has more features than V1
    assert len(V2_NUMERIC_FEATURE_KEYS) > len(V1_NUMERIC_FEATURE_KEYS)
    assert "wellbeing_overall" in V2_NUMERIC_FEATURE_KEYS
    assert "wellbeing_fatigue" in V2_NUMERIC_FEATURE_KEYS
    assert "wellbeing_overall" not in V1_NUMERIC_FEATURE_KEYS