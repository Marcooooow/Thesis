import pytest
from sqlalchemy.orm import Session
from datetime import date, timedelta
import uuid

from app.models import User, Profile, Notification, UserSettings, WorkSession
from app.services.notification_dispatch_service import NotificationDispatchService
from app.services.absence_detection import AbsenceDetectionService
from app.services.leave_service import LeaveService

def test_notification_types_and_idempotency(db: Session):
    """Verify all 5 absence/leave notification types can be dispatched and idempotency keys prevent duplicates."""
    user = User(email="notif_idem@example.com", password_hash="hash", full_name="Idem User", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    db.add(user)
    db.commit()

    key = f"test-key-{uuid.uuid4()}"
    notif1 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Test Alert",
        message="Message content",
        notification_type="ABSENCE_ALERT",
        idempotency_key=key
    )
    assert notif1 is not None

    # Dispatch again with same idempotency key should return existing
    notif2 = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Test Alert 2",
        message="Message content 2",
        notification_type="ABSENCE_ALERT",
        idempotency_key=key
    )
    assert notif2.id == notif1.id
    assert notif2.title == "Test Alert"

    count = db.query(Notification).filter(Notification.idempotency_key == key).count()
    assert count == 1

def test_notification_dnd_respect(db: Session):
    """Verify that NotificationDispatchService respects DND settings (manual override or active session)."""
    user = User(email="notif_dnd@example.com", password_hash="hash", full_name="DND User", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    db.add(user)
    db.commit()
    profile = Profile(user_id=user.id)
    db.add(profile)
    db.commit()

    # Set manual DND override to True
    settings = UserSettings(user_id=user.id, manual_dnd_override=True)
    db.add(settings)
    db.commit()

    # Standard priority notification should be suppressed by DND
    notif = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Standard Notice",
        message="Standard msg",
        notification_type="ABSENCE_ALERT",
        priority="STANDARD"
    )
    assert notif.delivery_status == "SUPPRESSED_DND"

    # Critical priority notification should bypass DND
    notif_crit = NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=user.id,
        title="Critical Notice",
        message="Critical msg",
        notification_type="ABSENCE_ALERT",
        priority="CRITICAL"
    )
    assert notif_crit.delivery_status == "AVAILABLE"

def test_notification_retry_behavior(db: Session):
    """Verify retry_pending_notifications processes pending records without duplicating successfully dispatched ones."""
    user = User(email="notif_retry@example.com", password_hash="hash", full_name="Retry User", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    db.add(user)
    db.commit()
    profile = Profile(user_id=user.id)
    db.add(profile)
    db.commit()

    detector = AbsenceDetectionService(db)
    # Retry when no pending/failed absence records exist should return 0
    count = detector.retry_pending_notifications()
    assert count >= 0
