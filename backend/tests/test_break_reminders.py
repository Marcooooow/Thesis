"""Tests for Smart Break Reminders service and decision rules."""

import pytest
import uuid
from datetime import datetime, timezone, timedelta
from sqlalchemy.orm import Session

from app.models import User, Profile, WorkSession, Break, UserSettings, Notification
from app.services.break_reminder_service import BreakReminderService
from app.auth.security import get_password_hash


def test_no_active_session(db: Session, test_user: User):
    """Verify no reminder is dispatched when user has no active session."""
    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is None


def test_active_session_below_threshold(db: Session, test_user: User):
    """Verify no reminder is dispatched when active session work duration is below threshold."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    # Create active session started 15 minutes ago (threshold is 30 mins by default)
    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=15)
    )
    db.add(session)
    db.commit()

    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is None


def test_threshold_reached_dispatches_reminder(db: Session, test_user: User):
    """Verify reminder is dispatched when continuous work duration exceeds threshold."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    # Set user break interval to 30 mins
    settings = db.query(UserSettings).filter(UserSettings.user_id == test_user.id).first()
    if settings:
        settings.break_interval_minutes = 30
        db.add(settings)
        db.commit()

    # Create active session started 35 minutes ago
    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=35)
    )
    db.add(session)
    db.commit()

    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is not None
    assert notif.type == "BREAK_REMINDER"
    assert "Time for a Break" in notif.title
    assert notif.delivery_status == "AVAILABLE"


def test_completed_break_resets_continuous_work(db: Session, test_user: User):
    """Verify a completed break resets the continuous work timer, suppressing premature reminders."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    # Active session started 60 mins ago
    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=60)
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # But user took a completed break 10 minutes ago
    brk = Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=datetime.now(timezone.utc) - timedelta(minutes=20),
        ended_at=datetime.now(timezone.utc) - timedelta(minutes=10)
    )
    db.add(brk)
    db.commit()

    # Continuous work since last break is only 10 mins (< 30 min threshold)
    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is None


def test_active_break_suppresses_reminders(db: Session, test_user: User):
    """Verify reminders are suppressed while an employee is currently on an active break."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=50)
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # Active break (ended_at is None)
    brk = Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=datetime.now(timezone.utc) - timedelta(minutes=10),
        ended_at=None
    )
    db.add(brk)
    db.commit()

    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is None


def test_disabled_preferences_suppress_reminders(db: Session, test_user: User):
    """Verify disabled break reminders or notifications suppress reminders."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=50)
    )
    db.add(session)
    db.commit()

    settings = db.query(UserSettings).filter(UserSettings.user_id == test_user.id).first()
    if not settings:
        settings = UserSettings(user_id=test_user.id, break_reminders=False)
        db.add(settings)
    else:
        settings.break_reminders = False
    db.add(settings)
    db.commit()

    notif = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    assert notif is None


def test_idempotency_prevents_duplicate_reminders(db: Session, test_user: User):
    """Verify calling evaluation multiple times in the same window returns the existing notification without duplication."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=40)
    )
    db.add(session)
    db.commit()

    notif1 = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)
    notif2 = BreakReminderService.evaluate_and_dispatch_for_user(db, test_user.id)

    assert notif1 is not None
    assert notif2 is not None
    assert notif1.id == notif2.id

    # Verify only 1 notification exists in DB for this user
    count = db.query(Notification).filter(Notification.recipient_user_id == test_user.id).count()
    assert count == 1


def test_evaluate_reminders_api(test_client, db: Session, test_user: User):
    """Test POST /notifications/evaluate-reminders endpoint."""
    profile = db.query(Profile).filter(Profile.user_id == test_user.id).first()

    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(minutes=45)
    )
    db.add(session)
    db.commit()

    # Authenticate test client or get token
    from app.auth.security import create_access_token
    token = create_access_token(data={"sub": test_user.email})
    headers = {"Authorization": f"Bearer {token}"}

    response = test_client.post("/notifications/evaluate-reminders", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["dispatched"] is True
    assert "notification_id" in data

