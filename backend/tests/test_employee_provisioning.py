"""Tests for employee provisioning endpoint."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid

from app.main import app
from app.database import get_db
from uuid import UUID
from app.models import User, Profile, Organization, OrganizationMembership, Team, TeamMembership
from app.auth.security import get_password_hash


@pytest.fixture
def test_client(test_db: Session):
    """Create test client."""
    return TestClient(app)


def get_auth_headers(client: TestClient, email: str, password: str):
    """Get authentication headers for a user."""
    login_data = {"email": email, "password": password}
    response = client.post("/auth/login", json=login_data)
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def manager_user(test_db: Session) -> User:
    """Create a MANAGER user with approved organization membership."""
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
    test_db.add(user)
    test_db.flush()

    # Create profile
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
    test_db.add(profile)
    test_db.flush()

    # Create organization and MANAGER membership
    organization = Organization(name=f"Test Org {unique_id}")
    test_db.add(organization)
    test_db.flush()

    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    test_db.refresh(user)
    return user


@pytest.fixture
def employee_user(test_db: Session) -> User:
    """Create an EMPLOYEE user (to test duplicate email)."""
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
    test_db.add(user)
    test_db.flush()

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
    test_db.add(profile)
    test_db.commit()

    return user


def test_manager_creates_employee_success(test_client, manager_user: User, test_db: Session):
    """Test successful employee creation by manager."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    employee_data = {
        "email": "newemployee@test.com",
        "full_name": "New Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)

    assert response.status_code == 201
    data = response.json()

    # Check response fields
    assert data["email"] == "newemployee@test.com"
    assert data["full_name"] == "New Employee"
    assert data["is_active"] == True
    assert data["role"] == "EMPLOYEE"
    assert data["approval_status"] == "APPROVED"
    assert data["must_change_password"] == True
    assert "temporary_password" in data
    assert len(data["temporary_password"]) >= 12
    assert data["organization_id"] is not None
    assert data["team_id"] is None

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "newemployee@test.com").first()
    assert db_user is not None
    assert db_user.role == "EMPLOYEE"
    assert db_user.approval_status == "APPROVED"
    assert db_user.is_active == True
    assert db_user.must_change_password == True
    assert db_user.password_change_token_version == 0
    # Password should be hashed, not plaintext
    assert db_user.password_hash != "newemployee@test.com"  # Not email
    assert db_user.password_hash != "testpass123"  # Not manager password
    # Verify hash matches temporary password
    from app.auth.security import verify_password
    assert verify_password(data["temporary_password"], db_user.password_hash)

    # Verify profile exists
    profile = test_db.query(Profile).filter(Profile.user_id == db_user.id).first()
    assert profile is not None

    # Verify organization membership
    org_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_user.id,
        OrganizationMembership.role == "EMPLOYEE",
        OrganizationMembership.status == "APPROVED"
    ).first()
    assert org_membership is not None
    # Should be same organization as manager
    manager_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == manager_user.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).first()
    assert org_membership.organization_id == manager_membership.organization_id

    # Verify no team membership (since team_id was None)
    team_membership = test_db.query(TeamMembership).filter(
        TeamMembership.profile_id == profile.id
    ).first()
    assert team_membership is None


def test_manager_creates_employee_with_team(test_client, manager_user: User, test_db: Session):
    """Test employee creation with valid team assignment."""
    # First create a team for the manager
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    team_data = {"name": "Engineering Team", "description": "Test team"}
    team_response = test_client.post("/teams", json=team_data, headers=headers)
    assert team_response.status_code == 201
    team_id = team_response.json()["id"]

    # Now create employee with team_id
    employee_data = {
        "email": "teammember@test.com",
        "full_name": "Team Member",
        "team_id": team_id
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 201
    data = response.json()
    assert data["team_id"] == team_id
    assert data["team_name"] == "Engineering Team"

    # Verify team membership exists
    db_user = test_db.query(User).filter(User.email == "teammember@test.com").first()
    profile = test_db.query(Profile).filter(Profile.user_id == db_user.id).first()
    team_membership = test_db.query(TeamMembership).filter(
        TeamMembership.profile_id == profile.id,
        TeamMembership.team_id == UUID(team_id)
    ).first()
    assert team_membership is not None
    assert team_membership.role == "EMPLOYEE"


def test_manager_creates_employee_duplicate_email(test_client, manager_user: User, employee_user: User, test_db: Session):
    """Test that duplicate email is rejected."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    employee_data = {
        "email": employee_user.email,  # Already exists
        "full_name": "Duplicate Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 400
    assert "Email already registered" in response.json()["detail"]


def test_employee_cannot_create_employee(test_client, employee_user: User, test_db: Session):
    """Test that EMPLOYEE role cannot create employees."""
    headers = get_auth_headers(test_client, employee_user.email, "testpass123")

    employee_data = {
        "email": "another@test.com",
        "full_name": "Another Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 403
    assert "Not enough permissions" in response.json()["detail"]


def test_manager_no_organization_membership_rejected(test_client, test_db: Session):
    """Test manager with no approved MANAGER organization membership is rejected."""
    # Create a user with MANAGER role but no organization membership
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_no_org_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Manager No Org {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(user)
    test_db.flush()

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
    test_db.add(profile)
    test_db.commit()

    headers = get_auth_headers(test_client, user.email, "testpass123")

    employee_data = {
        "email": "test@test.com",
        "full_name": "Test Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 403
    assert "must have an approved MANAGER organization membership" in response.json()["detail"]


def test_manager_multiple_organization_memberships_ambiguous(test_client, test_db: Session):
    """Test manager with multiple approved MANAGER memberships gets 400 error."""
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_multi_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Manager Multi {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(user)
    test_db.flush()

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
    test_db.add(profile)
    test_db.flush()

    # Create two organizations and MANAGER memberships
    org1 = Organization(name=f"Test Org 1 {unique_id}")
    org2 = Organization(name=f"Test Org 2 {unique_id}")
    test_db.add_all([org1, org2])
    test_db.flush()

    org_membership1 = OrganizationMembership(
        user_id=user.id,
        organization_id=org1.id,
        role="MANAGER",
        status="APPROVED"
    )
    org_membership2 = OrganizationMembership(
        user_id=user.id,
        organization_id=org2.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add_all([org_membership1, org_membership2])
    test_db.commit()

    headers = get_auth_headers(test_client, user.email, "testpass123")

    employee_data = {
        "email": "test@test.com",
        "full_name": "Test Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 400
    assert "Ambiguous organization" in response.json()["detail"]


def test_manager_cannot_assign_cross_organization_team(test_client, manager_user: User, test_db: Session):
    """Test that assigning employee to team from different organization is rejected."""
    # Create another manager with their own organization and team
    unique_id = str(uuid.uuid4())[:8]
    other_email = f"other_manager_{unique_id}@test.com"

    other_manager = User(
        email=other_email,
        full_name=f"Other Manager {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(other_manager)
    test_db.flush()

    other_profile = Profile(
        user_id=other_manager.id,
        job_role="Manager",
        industry="Technology",
        years_of_experience=8,
        age=40,
        education_attainment="MBA",
        marital_status="Married",
        target_daily_hours=8,
    )
    test_db.add(other_profile)
    test_db.flush()

    other_org = Organization(name=f"Other Org {unique_id}")
    test_db.add(other_org)
    test_db.flush()

    other_org_membership = OrganizationMembership(
        user_id=other_manager.id,
        organization_id=other_org.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add(other_org_membership)
    test_db.flush()

    # Create team for other manager
    other_team = Team(
        name="Other Team",
        description="Other manager's team",
        manager_user_id=other_manager.id,
        organization_id=other_org.id,
        is_active=True
    )
    test_db.add(other_team)
    test_db.commit()

    # Now try to create employee in manager's organization but assign to other manager's team
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    employee_data = {
        "email": "crossorg@test.com",
        "full_name": "Cross Org Employee",
        "team_id": str(other_team.id)  # This team belongs to other organization
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 400
    assert "Team does not belong to your organization" in response.json()["detail"]


def test_temporary_password_can_login(test_client, manager_user: User, test_db: Session):
    """Test that the temporary password can be used to login."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    employee_data = {
        "email": "loginemployee@test.com",
        "full_name": "Login Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 201
    data = response.json()
    temp_password = data["temporary_password"]

    # Now try to login with the temporary password
    login_response = test_client.post("/auth/login", json={
        "email": "loginemployee@test.com",
        "password": temp_password
    })

    # Login should succeed and return a token
    assert login_response.status_code == 200
    login_data = login_response.json()
    assert "access_token" in login_data
    assert login_data["token_type"] == "bearer"
    # Should NOT require 2FA (we didn't set it up)
    assert login_data["requires_2fa"] == False