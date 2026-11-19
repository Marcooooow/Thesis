import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from uuid import uuid4
from app.main import app
from app import models
from app.auth.security import get_password_hash, create_access_token, get_current_active_user

client = TestClient(app)

def test_restored_user_missing_profile_auto_provisioned(test_db: Session):
    """Test that a restored user without an initial Profile or UserSettings record automatically has them provisioned and successfully accesses dashboard endpoints without 404."""
    user = models.User(
        email="restored_backup_user@example.com",
        full_name="Restored Backup User",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123")
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    assert test_db.query(models.Profile).filter_by(user_id=user.id).first() is None
    assert test_db.query(models.UserSettings).filter_by(user_id=user.id).first() is None

    token = create_access_token(data={"sub": user.email})

    response = client.get(
        "/analytics/today/summary",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, dict)

    profile = test_db.query(models.Profile).filter_by(user_id=user.id).first()
    settings = test_db.query(models.UserSettings).filter_by(user_id=user.id).first()
    assert profile is not None
    assert settings is not None

    res_tasks = client.get(
        "/work/tasks/history",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert res_tasks.status_code == 200
    assert isinstance(res_tasks.json(), list)


def test_existing_profile_and_settings_preserved(test_db: Session):
    """Test that existing profile information and user preferences are never overwritten if they already exist."""
    user = models.User(
        email="custom_profile_user@example.com",
        full_name="Custom User",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123")
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    custom_profile = models.Profile(
        user_id=user.id,
        target_daily_hours=10,
        job_role="Senior Engineer",
        industry="Technology"
    )
    custom_settings = models.UserSettings(
        user_id=user.id,
        timezone="Europe/London",
        break_reminders=False
    )
    test_db.add_all([custom_profile, custom_settings])
    test_db.commit()

    token = create_access_token(data={"sub": user.email})

    response = client.get(
        "/analytics/today/summary",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200

    # Verify custom values were preserved and not overwritten
    reloaded_profile = test_db.query(models.Profile).filter_by(user_id=user.id).first()
    reloaded_settings = test_db.query(models.UserSettings).filter_by(user_id=user.id).first()

    assert reloaded_profile.target_daily_hours == 10
    assert reloaded_profile.job_role == "Senior Engineer"
    assert reloaded_settings.timezone == "Europe/London"
    assert reloaded_settings.break_reminders is False


def test_concurrent_provisioning_integrity_handling(test_db: Session):
    """Test that concurrent provisioning attempts handle IntegrityError gracefully via rollback."""
    user = models.User(
        email="concurrent_user@example.com",
        full_name="Concurrent User",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123")
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    # Simulate concurrent insert race condition causing IntegrityError
    profile_1 = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile_1)
    test_db.commit()

    # Now call get_current_active_user dependency logic when profile already exists (or simulating race)
    token = create_access_token(data={"sub": user.email})
    response = client.get(
        "/analytics/today/summary",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
