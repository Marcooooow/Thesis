"""
Tests for Break Coach recommendation intelligence guards (active break & recent long break like 125-min).
"""
import pytest
from datetime import datetime, timezone, timedelta
from app.database import get_db
from app import models
from app.auth.security import get_password_hash
from app.services.recommendation_service import _score_candidate, _extract_features


def test_recommendation_suppressed_during_active_break(test_db):
    """Test that recommendation scoring returns 0.0 when user is currently on an active break."""
    user = models.User(
        email="activebreak_rec@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Active Break User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    now = datetime.now(timezone.utc)
    session = models.WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=2)
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Active break (ended_at is None)
    active_break = models.Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=now - timedelta(minutes=10)
    )
    test_db.add(active_break)
    test_db.commit()

    features = _extract_features(test_db, profile.id)
    assert features["has_active_break"] is True

    score = _score_candidate("SHORT_BREAK", features)
    assert score == 0.0


def test_recommendation_suppressed_after_recent_long_break(test_db):
    """Test that recommendation scoring returns 0.0 after a recent 125-minute break."""
    user = models.User(
        email="longbreak_rec@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Long Break User",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    now = datetime.now(timezone.utc)
    session = models.WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=4)
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Recent long break (125 minutes long, ended 20 minutes ago)
    long_break = models.Break(
        work_session_id=session.id,
        break_type="LUNCH",
        started_at=now - timedelta(minutes=145),
        ended_at=now - timedelta(minutes=20)
    )
    test_db.add(long_break)
    test_db.commit()

    features = _extract_features(test_db, profile.id)
    assert features["last_break_duration_minutes"] == 125.0

    score = _score_candidate("SHORT_BREAK", features)
    assert score == 0.0
