import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta, time

client = TestClient(app)

def test_admin_work_sustainability_endpoint(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Sust {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_sust_{unique_id}@test.com", full_name="Admin Sust", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)

    admin_profile = models.Profile(user_id=admin_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(admin_profile)
    test_db.commit()

    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Create employee with specific schedule (strings for SQLite compatibility)
    emp_user = models.User(
        email=f"emp_sust_{unique_id}@test.com", full_name="Emp Sust", role="EMPLOYEE",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)

    emp_profile = models.Profile(
        user_id=emp_user.id,
        target_daily_hours=8,
        shift_start_time="09:00",
        shift_end_time="17:00",
        is_test_data=False
    )
    test_db.add(emp_profile)
    test_db.commit()

    test_db.add(models.OrganizationMembership(user_id=emp_user.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
    test_db.commit()

    # Create overtime work session (10 hours net work) with late ending
    now = datetime.now(timezone.utc)
    start_session = now.replace(hour=8, minute=0, second=0, microsecond=0)
    end_session = start_session + timedelta(hours=10)

    session = models.WorkSession(
        profile_id=emp_profile.id,
        started_at=start_session,
        ended_at=end_session
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    res = client.get("/analytics/admin/work-sustainability", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    data = res.json()
    assert "sustainabilityIndex" in data
    assert "overtimeFrequency" in data
    assert "breakCompliance" in data
    assert "longSessionsCount" in data
    assert "lateShiftEndingsCount" in data
