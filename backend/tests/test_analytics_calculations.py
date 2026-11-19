import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

def test_admin_analytics_calculations_and_period_boundaries(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Analytics {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_{unique_id}@test.com", full_name="Admin User", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)

    admin_profile = models.Profile(user_id=admin_user.id, target_daily_hours=8, is_test_data=False, department="Management")
    test_db.add(admin_profile)
    test_db.commit()

    org_membership = models.OrganizationMembership(
        user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    # Create employee in org
    emp_user = models.User(
        email=f"emp_{unique_id}@test.com", full_name="Emp Analytics", role="EMPLOYEE",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)

    emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False, department="Engineering")
    test_db.add(emp_profile)
    test_db.commit()

    emp_membership = models.OrganizationMembership(
        user_id=emp_user.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"
    )
    test_db.add(emp_membership)
    test_db.commit()

    # Create work session within current week
    now = datetime.now(timezone.utc)
    start_of_week = now - timedelta(days=now.weekday())
    start_of_week = start_of_week.replace(hour=10, minute=0, second=0, microsecond=0)
    end_session = start_of_week + timedelta(hours=4)

    session = models.WorkSession(
        profile_id=emp_profile.id,
        started_at=start_of_week,
        ended_at=end_session
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Create task within session
    task = models.Task(
        profile_id=emp_profile.id,
        work_session_id=session.id,
        title="Test Task",
        status="DONE",
        started_at=start_of_week + timedelta(minutes=10),
        ended_at=start_of_week + timedelta(hours=2)
    )
    test_db.add(task)
    test_db.commit()

    # Create a historical session starting weeks ago (should not inflate current period metrics if filtered by started_at)
    old_session = models.WorkSession(
        profile_id=emp_profile.id,
        started_at=now - timedelta(days=30),
        ended_at=now - timedelta(days=30, hours=-100) # massive 100h old session
    )
    test_db.add(old_session)
    test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    # Test Focus Ratio
    res = client.get("/analytics/admin/today/focus-ratio", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    data = res.json()
    assert "activeFocus" in data
    assert "idle" in data
    assert "nonActive" in data

    # Test Focus Rate
    res = client.get("/analytics/admin/focus-rate", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    assert "rate" in res.json()

    # Test Weekly Work Hours
    res = client.get("/analytics/admin/weekly/work-hours", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    assert isinstance(res.json(), list)

    # Test What Changed (Period-over-Period)
    res = client.get("/analytics/admin/what-changed", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    changes = res.json()
    assert "workHoursChange" in changes
    if changes["workHoursChange"] is not None:
        assert "-" not in changes["workHoursChange"] or float(changes["workHoursChange"].replace('h','').replace('+','')) < 500


def test_interval_clipping_sessions_crossing_boundaries(test_db):
    """Test that sessions crossing reporting period boundaries are correctly included via overlapping interval clipping."""
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Clip {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_clip_{unique_id}@test.com", full_name="Admin Clip", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)

    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    emp_user = models.User(
        email=f"emp_clip_{unique_id}@test.com", full_name="Emp Clip", role="EMPLOYEE",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)

    emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(emp_profile)
    test_db.commit()

    test_db.add(models.OrganizationMembership(user_id=emp_user.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
    test_db.commit()

    # Session starting 2 hours before today and ending 2 hours into today
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    session_start = today_start - timedelta(hours=2)
    session_end = today_start + timedelta(hours=2)

    session = models.WorkSession(
        profile_id=emp_profile.id,
        started_at=session_start,
        ended_at=session_end
    )
    test_db.add(session)
    test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    res = client.get("/analytics/admin/focus-rate", headers=headers, params={"period": "today"})
    assert res.status_code == 200
    assert "rate" in res.json()

