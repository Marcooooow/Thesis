"""Tests for team creation authorization by role."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid

from app.main import app
from app.database import get_db, SessionLocal
from app.models import User, Profile, Organization, OrganizationMembership
from app.auth.security import get_password_hash


@pytest.fixture
def db_session(test_db: Session):
    """Provide a database session for tests."""
    yield test_db


def get_auth_headers(client: TestClient, email: str, password: str):
    """Get authentication headers for a user."""
    login_data = {"email": email, "password": password}
    response = client.post("/auth/login", json=login_data)
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def manager_user(db_session):
    """Create a MANAGER user."""
    # Use UUID to ensure unique email per test run
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Manager {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    db_session.add(user)
    db_session.flush()

    # Create profile for team membership
    profile = Profile(
        user_id=user.id,
        job_role="Manager",
        industry="Technology",
        years_of_experience=10,
        age=35,
        education_attainment="Master's",
        marital_status="Married",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.flush()

    # Create organization and membership for team creation authorization
    organization = Organization(name=f"Test Org {unique_id}")
    db_session.add(organization)
    db_session.flush()

    organization_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(organization_membership)
    db_session.commit()

    # Store email for auth
    user.email_for_auth = email
    return user


@pytest.fixture
def employee_user(db_session):
    """Create an EMPLOYEE user."""
    # Use UUID to ensure unique email per test run
    unique_id = str(uuid.uuid4())[:8]
    email = f"employee_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Employee {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    db_session.add(user)
    db_session.flush()

    # Create profile for team membership
    profile = Profile(
        user_id=user.id,
        job_role="Developer",
        industry="Technology",
        years_of_experience=5,
        age=28,
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.flush()

    # Create organization and membership (employee role)
    organization = Organization(name=f"Test Org Employee {unique_id}")
    db_session.add(organization)
    db_session.flush()

    organization_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(organization_membership)
    db_session.commit()

    # Store email for auth
    user.email_for_auth = email
    return user


def test_manager_can_create_team(test_client, manager_user):
    """MANAGER role + valid team data → 201 success."""
    headers = get_auth_headers(test_client, manager_user.email_for_auth, "testpass123")

    payload = {
        "name": f"Engineering Team {uuid.uuid4()}",
        "description": "Main engineering team",
    }

    response = test_client.post("/teams", json=payload, headers=headers)

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == payload["name"]
    assert data["description"] == "Main engineering team"
    assert data["manager_id"] == str(manager_user.id)


def test_employee_cannot_create_team(test_client, employee_user):
    """EMPLOYEE role + valid team data → 403."""
    headers = get_auth_headers(test_client, employee_user.email_for_auth, "testpass123")

    payload = {
        "name": f"Unauthorized Team {uuid.uuid4()}",
        "description": "This should fail",
    }

    response = test_client.post("/teams", json=payload, headers=headers)

    assert response.status_code == 403
    data = response.json()
    assert "Only managers and admins can create teams" in data["detail"]


def test_manager_remains_manager_after_creating_team(test_client, db_session, manager_user):
    """Manager remains MANAGER after creating team."""
    headers = get_auth_headers(test_client, manager_user.email_for_auth, "testpass123")

    payload = {
        "name": f"Test Team {uuid.uuid4()}",
        "description": "Role preservation test",
    }

    response = test_client.post("/teams", json=payload, headers=headers)
    assert response.status_code == 201

    # Verify user role is still MANAGER
    db_session.refresh(manager_user)
    assert manager_user.role == "MANAGER"


def test_team_membership_and_ownership_after_creation(test_client, db_session, manager_user):
    """Team membership/ownership is correctly assigned to the Manager."""
    headers = get_auth_headers(test_client, manager_user.email_for_auth, "testpass123")

    payload = {
        "name": f"Ownership Test Team {uuid.uuid4()}",
        "description": "Testing membership",
    }

    response = test_client.post("/teams", json=payload, headers=headers)
    assert response.status_code == 201
    team_data = response.json()
    team_id_str = team_data["id"]
    team_id = uuid.UUID(team_id_str)  # Convert string to UUID object

    # Verify team ownership
    from app.models import Team, TeamMembership
    team = db_session.query(Team).filter(Team.id == team_id).first()
    assert team is not None
    assert team.manager_user_id == manager_user.id

    # Verify team membership with MANAGER role
    membership = db_session.query(TeamMembership).filter(
        TeamMembership.team_id == team.id,
        TeamMembership.profile_id == manager_user.profile.id,
    ).first()
    assert membership is not None
    assert membership.role == "MANAGER"
