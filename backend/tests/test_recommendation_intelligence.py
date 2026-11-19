"""
Tests for personal baseline calculations, behavioral pattern detection, and recommendation intelligence.
"""

import pytest
import uuid
from datetime import datetime, timezone, timedelta
from app.database import get_db
from app import models
from app.auth.security import get_password_hash
from app.services.behavioral_analytics import calculate_personal_baselines, detect_behavioral_patterns
from app.services.recommendation_service import _score_candidate, _extract_features


@pytest.fixture
def test_db_session(test_db):
    yield test_db


def test_personal_baselines_cold_start(test_db_session):
    """Test baseline calculation for a cold-start employee with no sessions."""
    user = models.User(
        email="coldstart@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Cold Start User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    baselines = calculate_personal_baselines(test_db_session, profile.id, days=30)
    assert baselines["is_cold_start"] is True
    assert baselines["observation_count_sessions"] == 0
    assert baselines["median_session_duration_minutes"] is None


def test_personal_baselines_with_history(test_db_session):
    """Test robust baseline calculations with completed sessions, breaks, and check-ins."""
    user = models.User(
        email="baseline_hist@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="History User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    now = datetime.now(timezone.utc)

    # Add 4 completed sessions (exceeds cold start threshold of 3)
    for i in range(4):
        s_start = now - timedelta(days=i, hours=4)
        s_end = now - timedelta(days=i, hours=1) # 3 hours duration
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=s_start,
            ended_at=s_end
        )
        test_db_session.add(session)
        test_db_session.commit()
        test_db_session.refresh(session)

        # Add break
        b_start = s_start + timedelta(minutes=60)
        b_end = b_start + timedelta(minutes=15)
        break_rec = models.Break(
            work_session_id=session.id,
            break_type="SHORT_BREAK",
            started_at=b_start,
            ended_at=b_end
        )
        test_db_session.add(break_rec)

        # Add checkin
        checkin = models.SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=session.id,
            overall_wellbeing=4,
            mental_fatigue=2,
            workload_manageability=4,
            perceived_focus=4,
            break_recovery=4
        )
        test_db_session.add(checkin)
        test_db_session.commit()

    baselines = calculate_personal_baselines(test_db_session, profile.id, days=30)
    assert baselines["is_cold_start"] is False
    assert baselines["observation_count_sessions"] == 4
    assert baselines["median_session_duration_minutes"] == 180.0  # 3 hours = 180 mins
    assert baselines["median_break_duration_minutes"] == 15.0
    assert baselines["median_mental_fatigue"] == 2.0


def test_overwork_detection(test_db_session):
    """Test detection of recurring overwork when hours exceed target daily hours."""
    user = models.User(
        email="overwork@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Overwork User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    now = datetime.now(timezone.utc)

    # Create 3 days where work hours = 10 hours (> target 8 + 1)
    for i in range(3):
        s_start = now - timedelta(days=i, hours=11)
        s_end = now - timedelta(days=i, hours=1) # 10 hours
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=s_start,
            ended_at=s_end
        )
        test_db_session.add(session)
        test_db_session.commit()

    patterns = detect_behavioral_patterns(test_db_session, str(profile.id))
    overwork_pattern = next((p for p in patterns if p["pattern_id"] == "RECURRING_OVERWORK"), None)
    assert overwork_pattern is not None
    assert overwork_pattern["detected"] is True
    assert "days exceeded target" in overwork_pattern["measurement"]
    assert "3" in overwork_pattern["measurement"]  # 3 overwork days


def test_skipped_breaks_detection(test_db_session):
    """Test detection of repeated skipped breaks during long sessions."""
    user = models.User(
        email="skippedbreaks@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Skipped Breaks User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    now = datetime.now(timezone.utc)

    # Create 3 long sessions (>60 mins) with ZERO breaks
    for i in range(3):
        s_start = now - timedelta(days=i, hours=3)
        s_end = now - timedelta(days=i)
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=s_start,
            ended_at=s_end
        )
        test_db_session.add(session)
        test_db_session.commit()

    patterns = detect_behavioral_patterns(test_db_session, str(profile.id))
    skipped_pattern = next((p for p in patterns if p["pattern_id"] == "REPEATED_SKIPPED_BREAKS"), None)
    assert skipped_pattern is not None
    assert skipped_pattern["detected"] is True
    assert "had no breaks" in skipped_pattern["measurement"]
    assert "3" in skipped_pattern["measurement"]  # 3 skipped sessions


def test_multi_user_isolation(test_db_session):
    """Test that behavioral baseline calculations and patterns do not mix different employees' records."""
    u1 = models.User(email="u1@intellibreak.local", password_hash=get_password_hash("pw"), full_name="U1", approval_status="APPROVED")
    test_db_session.add(u1)
    test_db_session.commit()
    p1 = models.Profile(user_id=u1.id, target_daily_hours=8)
    test_db_session.add(p1)
    test_db_session.commit()

    u2 = models.User(email="u2@intellibreak.local", password_hash=get_password_hash("pw"), full_name="U2", approval_status="APPROVED")
    test_db_session.add(u2)
    test_db_session.commit()
    p2 = models.Profile(user_id=u2.id, target_daily_hours=8)
    test_db_session.add(p2)
    test_db_session.commit()

    now = datetime.now(timezone.utc)
    s1 = models.WorkSession(profile_id=p1.id, started_at=now - timedelta(hours=5), ended_at=now - timedelta(hours=1))
    test_db_session.add(s1)
    test_db_session.commit()

    b1 = calculate_personal_baselines(test_db_session, str(p1.id), days=30)
    b2 = calculate_personal_baselines(test_db_session, str(p2.id), days=30)

    assert b1["observation_count_sessions"] == 1
    assert b2["observation_count_sessions"] == 0
    assert b2["is_cold_start"] is True


def test_recommendation_scoring_integration_skipped_breaks(test_db_session):
    """Test that detected skipped breaks pattern boosts SHORT_BREAK score and ignores unrelated types."""
    features_base = {
        "cold_start": False,
        "session_length_minutes": 45,
        "time_since_last_break_minutes": 25,
        "preferred_interval_minutes": 30,
        "detected_patterns": [
            {
                "pattern_id": "REPEATED_SKIPPED_BREAKS",
                "detected": True,
                "evidence_strength": "HIGH"
            }
        ]
    }

    score_short_break = _score_candidate("SHORT_BREAK", features_base)
    score_hydrate = _score_candidate("HYDRATE", features_base)

    # SHORT_BREAK should receive pattern boost; HYDRATE should not
    features_no_pattern = {
        "cold_start": False,
        "session_length_minutes": 45,
        "time_since_last_break_minutes": 25,
        "preferred_interval_minutes": 30,
        "detected_patterns": []
    }
    base_short_break = _score_candidate("SHORT_BREAK", features_no_pattern)
    base_hydrate = _score_candidate("HYDRATE", features_no_pattern)

    assert score_short_break > base_short_break
    assert score_hydrate == base_hydrate


from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import create_access_token

@pytest.fixture
def client(test_db):
    def override_get_db():
        try:
            yield test_db
        finally:
            pass
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_recommendation_impression_tracking(client, test_db_session):
    """Test explicit recommendation impression tracking (viewed_at)."""
    user = models.User(
        email="impression@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Impression User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    # Create recommendation feedback record
    rec_id = uuid.uuid4()
    feedback = models.RecommendationFeedback(
        recommendation_id=rec_id,
        user_id=user.id,
        model_version="test-model",
        recommendation_type="SHORT_BREAK",
        recommendation_score=0.85,
        context_features={},
        reason="test reason"
    )
    test_db_session.add(feedback)
    test_db_session.commit()

    assert feedback.viewed_at is None

    # Mark as viewed
    response = client.post("/recommend/viewed", json={"recommendation_id": str(rec_id)}, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "recorded"
    assert data["recommendation_id"] == str(rec_id)
    assert data["viewed_at"] is not None

    first_viewed_at = data["viewed_at"]

    # Test idempotence (subsequent view request should not change viewed_at)
    response2 = client.post("/recommend/viewed", json={"recommendation_id": str(rec_id)}, headers=headers)
    assert response2.status_code == 200
    assert response2.json()["viewed_at"] == first_viewed_at


def test_recommendation_to_break_linkage(client, test_db_session):
    """Test explicit recommendation-to-break linkage when starting a break."""
    user = models.User(
        email="breaklink@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Break Link User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    # Start active work session
    session = models.WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=1)
    )
    test_db_session.add(session)
    test_db_session.commit()
    test_db_session.refresh(session)

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    # Create recommendation feedback record
    rec_id = uuid.uuid4()
    feedback = models.RecommendationFeedback(
        recommendation_id=rec_id,
        user_id=user.id,
        model_version="test-model",
        recommendation_type="SHORT_BREAK",
        recommendation_score=0.90,
        context_features={},
        reason="test reason",
        work_session_id=session.id
    )
    test_db_session.add(feedback)
    test_db_session.commit()

    assert feedback.user_action is None

    # Start break linking the recommendation
    response = client.post(
        "/work/break/start",
        json={"break_type": "SHORT_BREAK", "notes": "Taking suggested break", "recommendation_id": str(rec_id)},
        headers=headers
    )
    assert response.status_code == 200
    break_data = response.json()
    assert break_data["break_type"] == "SHORT_BREAK"

    # Verify recommendation feedback was updated with accepted status and break linkage
    test_db_session.refresh(feedback)
    assert feedback.user_action == "accepted"
    assert feedback.break_started_at is not None
    assert feedback.break_type == "SHORT_BREAK"


def test_recommendation_outcomes_evaluation(client, test_db_session):
    """Test recommendation outcomes evaluation endpoint (/recommend/outcomes)."""
    user = models.User(
        email="outcomes@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Outcomes User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db_session.add(user)
    test_db_session.commit()
    test_db_session.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db_session.add(profile)
    test_db_session.commit()
    test_db_session.refresh(profile)

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    # Create test feedbacks with various states
    now = datetime.now(timezone.utc)

    # 1. Viewed & Accepted with break
    f1 = models.RecommendationFeedback(
        recommendation_id=uuid.uuid4(),
        user_id=user.id,
        model_version="test-model",
        recommendation_type="SHORT_BREAK",
        recommendation_score=0.8,
        context_features={},
        timestamp=now - timedelta(hours=3),
        viewed_at=now - timedelta(hours=3, minutes=5),
        user_action="accepted",
        break_started_at=now - timedelta(hours=2, minutes=30),
        break_ended_at=now - timedelta(hours=2, minutes=15),
        break_duration=15,
        post_break_productivity_delta=0.15
    )
    # 2. Viewed & Dismissed
    f2 = models.RecommendationFeedback(
        recommendation_id=uuid.uuid4(),
        user_id=user.id,
        model_version="test-model",
        recommendation_type="WALK",
        recommendation_score=0.7,
        context_features={},
        timestamp=now - timedelta(hours=4),
        viewed_at=now - timedelta(hours=4, minutes=2),
        user_action="dismissed"
    )
    # 3. Ignored (older than 2 hours, user_action NULL)
    f3 = models.RecommendationFeedback(
        recommendation_id=uuid.uuid4(),
        user_id=user.id,
        model_version="test-model",
        recommendation_type="HYDRATE",
        recommendation_score=0.6,
        context_features={},
        timestamp=now - timedelta(hours=5),
        user_action=None
    )

    test_db_session.add_all([f1, f2, f3])
    test_db_session.commit()

    response = client.get("/recommend/outcomes", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["total_generated"] == 3
    assert data["total_viewed"] == 2
    assert data["total_accepted"] == 1
    assert data["total_dismissed"] == 1
    assert data["total_ignored"] == 1
    assert data["generated_to_viewed_rate"] == round(2/3, 2)
    assert data["viewed_to_accepted_rate"] == 1/2
    assert data["dismissal_rate"] == round(1/3, 2)
    assert data["ignored_rate"] == round(1/3, 2)
    assert data["accepted_with_break_rate"] == 1.0
    assert data["break_completion_rate"] == 1.0
    assert data["average_post_break_productivity_delta"] == 0.15


def test_evidence_strength_filtering(test_db_session):
    """Test that LOW evidence strength patterns do NOT influence scores."""
    features_low_evidence = {
        "cold_start": False,
        "session_length_minutes": 45,
        "time_since_last_break_minutes": 25,
        "preferred_interval_minutes": 30,
        "detected_patterns": [
            {
                "pattern_id": "REPEATED_SKIPPED_BREAKS",
                "detected": True,
                "evidence_strength": "LOW"
            }
        ]
    }
    features_no_pattern = {
        "cold_start": False,
        "session_length_minutes": 45,
        "time_since_last_break_minutes": 25,
        "preferred_interval_minutes": 30,
        "detected_patterns": []
    }

    assert _score_candidate("SHORT_BREAK", features_low_evidence) == _score_candidate("SHORT_BREAK", features_no_pattern)
