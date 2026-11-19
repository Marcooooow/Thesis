"""
Comprehensive verification tests for time accounting formulas and edge cases (Section C).
"""
import pytest
from datetime import datetime, timezone, timedelta
from app.database import get_db
from app import models
from app.auth.security import get_password_hash
from app.services.analytics_service import AnalyticsEngine


def test_time_accounting_scenarios(test_db):
    """Test exact time accounting scenarios: work, breaks, meals, away, and meetings."""
    user = models.User(
        email="time_accounting@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Time Accounting User",
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

    # Scenario 1: 5h work + 2h breaks = 7h shift duration, 5h worked, 2h breaks
    s1_start = now - timedelta(hours=9)
    s1_end = now - timedelta(hours=2)
    session1 = models.WorkSession(profile_id=profile.id, started_at=s1_start, ended_at=s1_end)
    test_db.add(session1)
    test_db.commit()
    test_db.refresh(session1)

    # 2h break inside session1
    break1 = models.Break(
        work_session_id=session1.id,
        break_type="SHORT_BREAK",
        started_at=s1_start + timedelta(hours=2),
        ended_at=s1_start + timedelta(hours=4)
    )
    test_db.add(break1)
    test_db.commit()

    metrics1 = AnalyticsEngine.calculate_session_metrics(test_db, session1)
    assert metrics1["shift_duration_seconds"] == pytest.approx(7 * 3600, abs=5)
    assert metrics1["break_seconds"] == pytest.approx(2 * 3600, abs=5)
    assert metrics1["worked_seconds"] == pytest.approx(5 * 3600, abs=5)

    # Scenario 2: 5h work + 30m meal = 5.5h shift, 30m meal break, 5h worked
    s2_start = now - timedelta(hours=16)
    s2_end = now - timedelta(hours=10.5)
    session2 = models.WorkSession(profile_id=profile.id, started_at=s2_start, ended_at=s2_end)
    test_db.add(session2)
    test_db.commit()
    test_db.refresh(session2)

    meal_break = models.Break(
        work_session_id=session2.id,
        break_type="MEAL",
        started_at=s2_start + timedelta(hours=2),
        ended_at=s2_start + timedelta(hours=2, minutes=30)
    )
    test_db.add(meal_break)
    test_db.commit()

    metrics2 = AnalyticsEngine.calculate_session_metrics(test_db, session2)
    assert metrics2["shift_duration_seconds"] == pytest.approx(5.5 * 3600, abs=5)
    assert metrics2["break_seconds"] == pytest.approx(0.5 * 3600, abs=5)
    assert metrics2["worked_seconds"] == pytest.approx(5 * 3600, abs=5)

    # Scenario 3: 5h work + 1h personal away (OTHER) = 6h shift, 1h away, 5h worked
    s3_start = now - timedelta(hours=24)
    s3_end = now - timedelta(hours=18)
    session3 = models.WorkSession(profile_id=profile.id, started_at=s3_start, ended_at=s3_end)
    test_db.add(session3)
    test_db.commit()
    test_db.refresh(session3)

    away_break = models.Break(
        work_session_id=session3.id,
        break_type="OTHER",
        started_at=s3_start + timedelta(hours=3),
        ended_at=s3_start + timedelta(hours=4)
    )
    test_db.add(away_break)
    test_db.commit()

    metrics3 = AnalyticsEngine.calculate_session_metrics(test_db, session3)
    assert metrics3["shift_duration_seconds"] == pytest.approx(6 * 3600, abs=5)
    assert metrics3["break_seconds"] == pytest.approx(1 * 3600, abs=5)
    assert metrics3["worked_seconds"] == pytest.approx(5 * 3600, abs=5)

    # Scenario 4: 5h work + 1h meeting task = 6h worked/focused seconds
    s4_start = now - timedelta(hours=32)
    s4_end = now - timedelta(hours=26)
    session4 = models.WorkSession(profile_id=profile.id, started_at=s4_start, ended_at=s4_end)
    test_db.add(session4)
    test_db.commit()
    test_db.refresh(session4)

    task_meeting = models.Task(
        profile_id=profile.id,
        work_session_id=session4.id,
        title="Client Sync Meeting",
        category="Meeting",
        status="DONE",
        started_at=s4_start,
        ended_at=s4_start + timedelta(hours=1),
        actual_minutes=60
    )
    task_work = models.Task(
        profile_id=profile.id,
        work_session_id=session4.id,
        title="Coding Feature",
        category="Development",
        status="DONE",
        started_at=s4_start + timedelta(hours=1),
        ended_at=s4_end,
        actual_minutes=300
    )
    test_db.add_all([task_meeting, task_work])
    test_db.commit()

    metrics4 = AnalyticsEngine.calculate_session_metrics(test_db, session4)
    assert metrics4["worked_seconds"] == pytest.approx(6 * 3600, abs=5)
    assert metrics4["focused_seconds"] == pytest.approx(6 * 3600, abs=5)


def test_overlapping_intervals_not_double_counted(test_db):
    """Test that overlapping or touching intervals (breaks/tasks) are merged correctly without double-counting."""
    user = models.User(
        email="overlap_user@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Overlap User",
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
        started_at=now - timedelta(hours=5),
        ended_at=now
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Two overlapping break records that should merge into 1 hour total break time
    b1 = models.Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=now - timedelta(hours=4),
        ended_at=now - timedelta(hours=3)
    )
    b2 = models.Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=now - timedelta(hours=3, minutes=30),
        ended_at=now - timedelta(hours=2, minutes=30)
    )
    test_db.add_all([b1, b2])
    test_db.commit()

    metrics = AnalyticsEngine.calculate_session_metrics(test_db, session)
    # Total shift = 5h. Break interval span = [now-4h, now-2.5h] = 1.5h.
    assert metrics["break_seconds"] == pytest.approx(1.5 * 3600, abs=5)
    assert metrics["worked_seconds"] == pytest.approx(3.5 * 3600, abs=5)
