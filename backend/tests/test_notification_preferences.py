import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone

client = TestClient(app)

@pytest.fixture
def pref_user_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"pref_user_{unique_id}@test.com"
    user = models.User(
        email=email,
        full_name="Pref Test User",
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
        quiet_hours_enabled=True,
        quiet_hours_start="22:00",
        quiet_hours_end="08:00",
        break_reminders=False,
        task_reminders=True
    )
    test_db.add(settings)
    test_db.commit()

    return create_access_token(data={"sub": user.email})

def test_get_and_patch_notification_settings(pref_user_token):
    headers = {"Authorization": f"Bearer {pref_user_token}"}

    # GET settings
    response = client.get("/settings", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["quiet_hours_enabled"] is True
    assert data["quiet_hours_start"] == "22:00"
    assert data["quiet_hours_end"] == "08:00"
    assert data["break_reminders"] is False

    # PATCH settings with valid time and category toggles
    patch_response = client.patch(
        "/settings",
        headers=headers,
        json={
            "quiet_hours_start": "23:00",
            "task_reminders": False,
            "wellness_reminders": False
        }
    )
    assert patch_response.status_code == 200
    updated = patch_response.json()
    assert updated["quiet_hours_start"] == "23:00"
    assert updated["task_reminders"] is False
    assert updated["wellness_reminders"] is False

    # PATCH with invalid time format should fail validation
    invalid_response = client.patch(
        "/settings",
        headers=headers,
        json={"quiet_hours_start": "25:60"}
    )
    assert invalid_response.status_code == 422


def test_notification_dispatch_category_and_quiet_hours(test_db):
    from app.services.notification_dispatch_service import NotificationDispatchService
    from unittest.mock import patch
    from datetime import datetime
    from zoneinfo import ZoneInfo

    # Create test user
    unique_id = str(uuid.uuid4())[:8]
    user = models.User(
        email=f"dispatch_test_{unique_id}@test.com",
        full_name="Dispatch Test User",
        role="EMPLOYEE",
        account_type="solo",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass"),
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    settings = models.UserSettings(
        user_id=user.id,
        notifications_enabled=True,
        break_reminders=False,
        task_reminders=True,
        quiet_hours_enabled=True,
        quiet_hours_start="22:00",
        quiet_hours_end="08:00",
        timezone="UTC"
    )
    test_db.add(settings)
    test_db.commit()

    # 1. Break reminder disabled via category preference -> SUPPRESSED_PREFERENCE
    with patch("app.services.notification_dispatch_service.datetime") as mock_dt:
        # Mock current time outside quiet hours e.g. 14:00 UTC
        mock_dt.now.return_value = datetime(2026, 11, 6, 14, 0, tzinfo=ZoneInfo("UTC"))
        mock_dt.side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)

        notif1 = NotificationDispatchService.dispatch(
            db=test_db,
            recipient_user_id=user.id,
            title="Break",
            message="Take a break",
            notification_type="BREAK_REMINDER"
        )
        assert notif1.delivery_status == "SUPPRESSED_PREFERENCE"

    # 2. Task reminder enabled, but during quiet hours (e.g. 23:00 UTC) -> SUPPRESSED_QUIET_HOURS
    with patch("app.services.notification_dispatch_service.datetime") as mock_dt:
        mock_dt.now.return_value = datetime(2026, 11, 6, 23, 0, tzinfo=ZoneInfo("UTC"))
        mock_dt.side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)

        notif2 = NotificationDispatchService.dispatch(
            db=test_db,
            recipient_user_id=user.id,
            title="Task",
            message="Due soon",
            notification_type="TASK_REMINDER"
        )
        assert notif2.delivery_status == "SUPPRESSED_QUIET_HOURS"

    # 3. Critical priority bypasses quiet hours and category preference -> AVAILABLE
    with patch("app.services.notification_dispatch_service.datetime") as mock_dt:
        mock_dt.now.return_value = datetime(2026, 11, 6, 23, 0, tzinfo=ZoneInfo("UTC"))
        mock_dt.side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)

        notif3 = NotificationDispatchService.dispatch(
            db=test_db,
            recipient_user_id=user.id,
            title="Emergency",
            message="Critical alert",
            notification_type="BREAK_REMINDER",
            priority="CRITICAL"
        )
        assert notif3.delivery_status == "AVAILABLE"

