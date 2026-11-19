"""Tests for admin user counts endpoint."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid

from app.main import app
from app.database import get_db
from app.models import User, Organization
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
def admin_user(test_db: Session) -> User:
    """Create an ADMIN user."""
    unique_id = str(uuid.uuid4())[:8]
    email = f"admin_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Admin {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()

    # Create organization
    organization = Organization(name=f"Admin Org {unique_id}")
    test_db.add(organization)
    test_db.flush()

    # Create organization membership for admin
    from app.models import OrganizationMembership
    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="ADMIN",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()
    test_db.refresh(user)
    return user


@pytest.fixture
def regular_user(test_db: Session, admin_user: User) -> User:
    """Create a regular EMPLOYEE user."""
    unique_id = str(uuid.uuid4())[:8]
    email = f"user_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"User {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()

    # Get the admin's organization (since admin_user already has one)
    organization = test_db.query(Organization).filter(Organization.id == admin_user.organization_memberships[0].organization_id).first()
    # Create organization membership for regular user
    from app.models import OrganizationMembership
    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()
    test_db.refresh(user)
    return user


@pytest.fixture
def pending_user(test_db: Session, admin_user: User) -> User:
    """Create a pending user."""
    unique_id = str(uuid.uuid4())[:8]
    email = f"pending_{unique_id}@test.com"

    user = User(
        email=email,
        full_name=f"Pending {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="PENDING",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()

    # Get the admin's organization
    organization = test_db.query(Organization).filter(Organization.id == admin_user.organization_memberships[0].organization_id).first()
    # Create organization membership for pending user
    from app.models import OrganizationMembership
    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="PENDING"
    )
    test_db.add(org_membership)
    test_db.commit()
    test_db.refresh(user)
    return user


def test_admin_user_counts_success(test_client: TestClient, admin_user: User, regular_user: User, pending_user: User):
    """Test that admin can get user counts."""
    # Login as admin
    login_response = test_client.post(
        "/auth/login",
        json={"email": admin_user.email, "password": "testpass123"}
    )
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Get user counts
    response = test_client.get("/admin/user-counts", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert "employees" in data
    assert "managers" in data
    assert "pending" in data

    # We have one regular user (employee), no managers (since admin is ADMIN role, not MANAGER), and one pending user
    assert data["employees"] == 1  # regular_user
    assert data["managers"] == 0   # no MANAGER role users
    assert data["pending"] == 1    # pending_user


def test_admin_user_counts_with_manager(test_client: TestClient, admin_user: User, regular_user: User, pending_user: User, test_db: Session):
    """Test user counts when there is a manager."""
    # Create a manager user
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_{unique_id}@test.com"

    manager = User(
        email=email,
        full_name=f"Manager {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(manager)
    test_db.flush()

    # Get the admin's organization
    organization = test_db.query(Organization).filter(Organization.id == admin_user.organization_memberships[0].organization_id).first()
    # Create organization membership for manager
    from app.models import OrganizationMembership
    org_membership = OrganizationMembership(
        user_id=manager.id,
        organization_id=organization.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()
    test_db.refresh(manager)

    # Login as admin
    login_response = test_client.post(
        "/auth/login",
        json={"email": admin_user.email, "password": "testpass123"}
    )
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Get user counts
    response = test_client.get("/admin/user-counts", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert data["employees"] == 1  # regular_user
    assert data["managers"] == 1   # manager
    assert data["pending"] == 1    # pending_user


def test_non_admin_cannot_access_user_counts(test_client: TestClient, regular_user: User, pending_user: User):
    """Test that non-admin users cannot access the user counts endpoint."""
    # Login as regular user
    login_response = test_client.post(
        "/auth/login",
        json={"email": regular_user.email, "password": "testpass123"}
    )
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Try to access user counts
    response = test_client.get("/admin/user-counts", headers=headers)
    assert response.status_code == 403  # Forbidden

    # Also test with pending user (should also be 403)
    login_response_pending = test_client.post(
        "/auth/login",
        json={"email": pending_user.email, "password": "testpass123"}
    )
    # Note: pending_user may not be able to login if approval_status is PENDING and login requires APPROVED
    # Depending on your login logic, this might fail. We'll skip if login fails.
    if login_response_pending.status_code == 200:
        token_pending = login_response_pending.json()["access_token"]
        headers_pending = {"Authorization": f"Bearer {token_pending}"}
        response_pending = test_client.get("/admin/user-counts", headers=headers_pending)
        assert response_pending.status_code == 403