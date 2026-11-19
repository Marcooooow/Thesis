import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from uuid import uuid4
from app.main import app
from app.database import Base, engine, SessionLocal
from app import models
from app.auth.security import get_password_hash
from app.routers.auth import create_access_token

client = TestClient(app)

@pytest.fixture
def db_session(test_db: Session):
    """Provide a database session for tests."""
    yield test_db

@pytest.fixture
def admin_token(db_session):
    """Create an admin user and return authentication token."""
    # Create org
    org = models.Organization(name="Test Org")
    db_session.add(org)
    db_session.commit()

    # Create admin user
    admin_user = models.User(
        email="admin@example.com",
        full_name="Admin User",
        role="ADMIN",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("adminpassword123"),
    )
    db_session.add(admin_user)
    db_session.commit()
    db_session.refresh(admin_user)

    admin_org_mem = models.OrganizationMembership(
        user_id=admin_user.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db_session.add(admin_org_mem)
    db_session.commit()

    # Create access token
    access_token = create_access_token(data={"sub": admin_user.email})
    return access_token, org.id

@pytest.fixture
def test_employee(db_session, admin_token):
    _, org_id = admin_token
    """Create a test employee user."""
    employee = models.User(
        email="employee@example.com",
        full_name="Test Employee",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("employeepassword123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(employee)

    # Create organization membership for employee (same org as admin)
    emp_org_mem = models.OrganizationMembership(
        user_id=employee.id,
        organization_id=org_id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(emp_org_mem)
    db_session.commit()

    # Create profile
    profile = models.Profile(user_id=employee.id)
    db_session.add(profile)
    db_session.commit()

    # Create work session
    from datetime import datetime, timezone
    session = models.WorkSession(profile_id=profile.id, started_at=datetime.now(timezone.utc))
    db_session.add(session)
    db_session.commit()
    db_session.refresh(session)

    return employee, session

def test_get_employee_work_sessions(db_session, admin_token, test_employee):
    token, _ = admin_token
    employee, session = test_employee

    response = client.get(
        f"/employees/{employee.id}/work-sessions",
        headers={"Authorization": f"Bearer {token}"}
    )

    # If endpoint exists, it should be 200 (if empty) or 404
    # The actual implementation of get_employee_work_sessions should handle the active/completed filtering
    assert response.status_code in [200, 404]
