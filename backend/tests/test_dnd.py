"""Tests for Automatic DND, Notification Governance, and Manual Overrides."""

import pytest
from datetime import datetime, timezone, timedelta
from fastapi import status
from sqlalchemy.orm import Session

from app.models import User, Profile, WorkSession, UserSettings, Notification
from app.services.notification_dispatch_service import NotificationDispatchService
from app.auth.security import get_password_hash


@pytest.fixture
def test_user_and_profile(db: Session):
    user = User(
        email="dnd_test@intellibreak.com",
        password_hash=get_password_hash("password123"),
        full_name="DND Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED"
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    profile = Profile(user_id=user.id, is_test_data=True)
    db.add(profile)

    settings = UserSettings(user_id=user.id, manual_dnd_override=None)
    db.add(settings)
    db.commit()
    db.refresh(profile)
    db.refresh(settings)

    return user, profile, settings


def test_automatic_dnd_never_started(db: Session, test_user_and_profile):
    user, profile, _ = test_user_and_profile
    # Never started a shift -> automatic DND should be False
    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Test",
        message="Hello",
        notification_type="SYSTEM_ALERT"
    )
    db.commit()
    assert notif.delivery_status == "AVAILABLE"


def test_automatic_dnd_active_session(db: Session, test_user_and_profile):
    user, profile, _ = test_user_and_profile
    # Active session (ended_at is None) -> automatic DND is False (working)
    session = WorkSession(profile_id=profile.id, started_at=datetime.now(timezone.utc))
    db.add(session)
    db.commit()

    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Work Reminder",
        message="Keep going",
        notification_type="WORK_REMINDER"
    )
    db.commit()
    assert notif.delivery_status == "AVAILABLE"


def test_automatic_dnd_ended_session(db: Session, test_user_and_profile):
    user, profile, _ = test_user_and_profile
    # Ended session -> automatic DND is True (off-shift)
    start = datetime.now(timezone.utc) - timedelta(hours=8)
    end = datetime.now(timezone.utc)
    session = WorkSession(profile_id=profile.id, started_at=start, ended_at=end)
    db.add(session)
    db.commit()

    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Off-shift Reminder",
        message="Rest",
        notification_type="WORK_REMINDER"
    )
    db.commit()
    assert notif.delivery_status == "SUPPRESSED_DND"


def test_manual_override_precedence(db: Session, test_user_and_profile):
    user, profile, settings = test_user_and_profile
    # Ended session (auto DND = True), but manual override = FALSE (force off)
    start = datetime.now(timezone.utc) - timedelta(hours=8)
    end = datetime.now(timezone.utc)
    session = WorkSession(profile_id=profile.id, started_at=start, ended_at=end)
    db.add(session)

    settings.manual_dnd_override = False
    db.add(settings)
    db.commit()

    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Forced Off Notification",
        message="Should deliver",
        notification_type="WORK_REMINDER"
    )
    db.commit()
    assert notif.delivery_status == "AVAILABLE"


def test_critical_bypass(db: Session, test_user_and_profile):
    user, profile, _ = test_user_and_profile
    # Ended session (auto DND = True), but priority = CRITICAL
    start = datetime.now(timezone.utc) - timedelta(hours=8)
    end = datetime.now(timezone.utc)
    session = WorkSession(profile_id=profile.id, started_at=start, ended_at=end)
    db.add(session)
    db.commit()

    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Security Alert",
        message="Urgent",
        notification_type="SYSTEM_ALERT",
        priority="CRITICAL"
    )
    db.commit()
    assert notif.delivery_status == "AVAILABLE"


def test_idempotency_dispatch(db: Session, test_user_and_profile):
    user, _, _ = test_user_and_profile
    key = "uniq_key_123"
    notif1 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Alert 1",
        message="Msg 1",
        notification_type="SYSTEM_ALERT",
        idempotency_key=key
    )
    db.commit()

    notif2 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Alert 2",
        message="Msg 2",
        notification_type="SYSTEM_ALERT",
        idempotency_key=key
    )
    db.commit()

    assert notif1.id == notif2.id
    assert notif2.title == "Alert 1"


def test_team_invitation_notification_dnd_states(db: Session, test_user_and_profile):
    user, profile, _ = test_user_and_profile
    import uuid

    # 1. Active session (DND OFF) -> TEAM_INVITATION should be AVAILABLE
    session = WorkSession(profile_id=profile.id, started_at=datetime.now(timezone.utc))
    db.add(session)
    db.commit()

    invitation_id = uuid.uuid4()
    notif1 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Invited to Team",
        message="Join team",
        notification_type="TEAM_INVITATION",
        idempotency_key=f"team_inv_{invitation_id}",
        related_entity_id=invitation_id
    )
    db.commit()
    assert notif1.delivery_status == "AVAILABLE"

    # 2. Ended session (DND ON) -> TEAM_INVITATION_ACCEPTED should be SUPPRESSED_DND
    session.ended_at = datetime.now(timezone.utc)
    db.add(session)
    db.commit()

    notif2 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Invitation accepted",
        message="Accepted",
        notification_type="TEAM_INVITATION_ACCEPTED",
        idempotency_key=f"team_acc_{invitation_id}",
        related_entity_id=invitation_id
    )
    db.commit()
    assert notif2.delivery_status == "SUPPRESSED_DND"

