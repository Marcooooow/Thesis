"""Tests for Daily Progress Summary analytics endpoint."""

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

@pytest.fixture
def summary_user_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"summary_user_{unique_id}@test.com"
    user = models.User(
        email=email,
        full_name="Summary Test User",
        role="EMPLOYEE",
        account_type="solo",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass"),
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(profile)
    test_db.commit()

    settings = models.UserSettings(
        user_id=user.id,
        timezone="UTC",
        work_target_daily_hours=8
    )
    test_db.add(settings)
    test_db.commit()

    return create_access_token(data={"sub": user.email}), user, profile


def test_daily_summary_empty(summary_user_token, test_db):
    token, user, profile = summary_user_token
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/analytics/daily-summary", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "workSummary" in data
    assert "taskSummary" in data
    assert "breakSummary" in data
    assert "wellbeingSummary" in data
    assert "recommendationSummary" in data
    assert "dailyTarget" in data

    assert data["workSummary"]["totalSessions"] == 0
    assert data["taskSummary"]["totalTasks"] == 0
    assert data["breakSummary"]["totalBreaks"] == 0


def test_daily_summary_with_sessions_tasks_breaks(summary_user_token, test_db):
    token, user, profile = summary_user_token
    headers = {"Authorization": f"Bearer {token}"}

    # Create work session today (e.g. 2026-11-06)
    today_str = "2026-11-06"
    start_dt = datetime(2026, 11, 6, 9, 0, 0, tzinfo=timezone.utc)
    end_dt = datetime(2026, 11, 6, 17, 0, 0, tzinfo=timezone.utc)

    session = models.WorkSession(
        profile_id=profile.id,
        started_at=start_dt,
        ended_at=end_dt
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Add task
    task = models.Task(
        profile_id=profile.id,
        work_session_id=session.id,
        title="Complete feature",
        status="DONE",
        started_at=start_dt + timedelta(minutes=30),
        ended_at=start_dt + timedelta(hours=2)
    )
    test_db.add(task)

    # Add break
    brk = models.Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=start_dt + timedelta(hours=3),
        ended_at=start_dt + timedelta(hours=3, minutes=15)
    )
    test_db.add(brk)
    test_db.commit()

    response = client.get(f"/analytics/daily-summary?date={today_str}", headers=headers)
    assert response.status_code == 200
    data = response.json()

    assert data["workSummary"]["totalSessions"] == 1
    assert data["workSummary"]["completedSessions"] == 1
    assert data["taskSummary"]["totalTasks"] == 1
    assert data["taskSummary"]["completedTasks"] == 1
    assert data["breakSummary"]["totalBreaks"] == 1
    assert data["dailyTarget"]["targetHours"] == 8.0


def test_daily_summary_invalid_date(summary_user_token):
    token, _, _ = summary_user_token
    headers = {"Authorization": f"Bearer {token}"}

    response = client.get("/analytics/daily-summary?date=invalid-date", headers=headers)
    assert response.status_code == 400
