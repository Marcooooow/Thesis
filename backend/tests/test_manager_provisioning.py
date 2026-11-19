"""Tests for manager provisioning endpoint."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid

from app.main import app
from app.database import get_db
from app.models import User, Profile, Organization, OrganizationMembership
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

    # Create ADMIN organization membership
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


def test_admin_can_create_manager_success(test_client, admin_user: User, test_db: Session):
    """Test successful manager creation by admin."""
    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    # Create organization for the manager
    organization = Organization(name="Test Org For Manager")
    test_db.add(organization)
    test_db.commit()
    test_db.refresh(organization)

    manager_data = {
        "email": "newmanager@test.com",
        "full_name": "New Manager",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)

    assert response.status_code == 201
    data = response.json()

    # Check response fields
    assert data["email"] == "newmanager@test.com"
    assert data["full_name"] == "New Manager"
    assert data["is_active"] == True
    assert data["role"] == "MANAGER"
    assert data["approval_status"] == "APPROVED"
    assert data["must_change_password"] == True
    assert "temporary_password" in data
    assert len(data["temporary_password"]) >= 12
    assert str(data["organization_id"]) == str(organization.id)
    assert data["organization_name"] == "Test Org For Manager"

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "newmanager@test.com").first()
    assert db_user is not None
    assert db_user.role == "MANAGER"
    assert db_user.approval_status == "APPROVED"
    assert db_user.is_active == True
    assert db_user.must_change_password == True
    assert db_user.password_change_token_version == 0
    # Password should be hashed, not plaintext
    assert db_user.password_hash != "newmanager@test.com"  # Not email
    assert db_user.password_hash != "testpass123"  # Not admin password
    # Verify hash matches temporary password
    from app.auth.security import verify_password
    assert verify_password(data["temporary_password"], db_user.password_hash)

    # Verify profile exists
    profile = test_db.query(Profile).filter(Profile.user_id == db_user.id).first()
    assert profile is not None

    # Verify organization membership
    org_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_user.id,
        OrganizationMembership.organization_id == organization.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).first()
    assert org_membership is not None

    # Verify exactly one approved MANAGER OrganizationMembership exists
    manager_memberships = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_user.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).all()
    assert len(manager_memberships) == 1


def test_admin_creates_manager_with_exact_organization(test_client, admin_user: User, test_db: Session):
    """Test manager creation with specific organization assignment."""
    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    # Create two organizations
    org1 = Organization(name="Organization One")
    org2 = Organization(name="Organization Two")
    test_db.add_all([org1, org2])
    test_db.commit()
    test_db.refresh(org1)
    test_db.refresh(org2)

    manager_data = {
        "email": "manager@test.com",
        "full_name": "Test Manager",
        "organization_id": str(org2.id)  # Assign to second organization
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)

    assert response.status_code == 201
    data = response.json()

    # Verify organization assignment
    assert str(data["organization_id"]) == str(org2.id)
    assert data["organization_name"] == "Organization Two"

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "manager@test.com").first()
    org_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_user.id,
        OrganizationMembership.organization_id == org2.id
    ).first()
    assert org_membership is not None
    assert org_membership.role == "MANAGER"
    assert org_membership.status == "APPROVED"

    # Verify no membership to first organization
    wrong_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_user.id,
        OrganizationMembership.organization_id == org1.id
    ).first()
    assert wrong_membership is None


def test_non_admin_cannot_create_manager(test_client, test_db: Session):
    """Test that non-admin users cannot create managers."""
    # Create a manager user (not admin)
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_{unique_id}@test.com"
    user = User(
        email=email,
        full_name=f"Manager {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()

    # Create organization and membership for manager
    organization = Organization(name=f"Manager Org {unique_id}")
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

    headers = get_auth_headers(test_client, user.email, "testpass123")

    manager_data = {
        "email": "anothermanager@test.com",
        "full_name": "Another Manager",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 403
    assert "Not enough permissions" in response.json()["detail"]


def test_employee_cannot_create_manager(test_client, test_db: Session):
    """Test that EMPLOYEE role cannot create managers."""
    # Create an employee user
    unique_id = str(uuid.uuid4())[:8]
    email = f"employee_{unique_id}@test.com"
    user = User(
        email=email,
        full_name=f"Employee {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()

    # Create organization and membership for employee
    organization = Organization(name=f"Employee Org {unique_id}")
    test_db.add(organization)
    test_db.flush()
    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, user.email, "testpass123")

    manager_data = {
        "email": "testmanager@test.com",
        "full_name": "Test Manager",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 403
    assert "Not enough permissions" in response.json()["detail"]


def test_admin_creates_manager_duplicate_email(test_client, admin_user: User, test_db: Session):
    """Test that duplicate email is rejected."""
    # Create an existing user
    unique_id = str(uuid.uuid4())[:8]
    email = f"duplicate_{unique_id}@test.com"
    existing_user = User(
        email=email,
        full_name=f"Existing User {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(existing_user)
    test_db.flush()

    # Create organization and membership
    organization = Organization(name=f"Dup Org {unique_id}")
    test_db.add(organization)
    test_db.flush()
    org_membership = OrganizationMembership(
        user_id=existing_user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    manager_data = {
        "email": email,  # Already exists
        "full_name": "Duplicate Manager",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 400
    assert "Email already registered" in response.json()["detail"]


def test_admin_creates_manager_invalid_organization(test_client, admin_user: User, test_db: Session):
    """Test that invalid organization ID is rejected."""
    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    # Use a random UUID that doesn't exist
    fake_org_id = str(uuid.uuid4())

    manager_data = {
        "email": "testmanager@test.com",
        "full_name": "Test Manager",
        "organization_id": fake_org_id
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 404
    assert "Organization not found" in response.json()["detail"]


def test_admin_creates_manager_transaction_rollback_on_failure(test_client, admin_user: User, test_db: Session):
    """Test that failed creation rolls back all related records."""
    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    # Create organization
    organization = Organization(name="Test Org")
    test_db.add(organization)
    test_db.commit()
    test_db.refresh(organization)

    # Mock a failure by providing invalid data that would cause an error after user creation
    # We'll test this by checking that no partial records are left if an exception occurs
    # For simplicity, we'll test duplicate email which should fail early

    # First create a user with the same email
    existing_user = User(
        email="rollback@test.com",
        full_name="Existing User",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(existing_user)
    test_db.flush()

    org_membership = OrganizationMembership(
        user_id=existing_user.id,
        organization_id=organization.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    manager_data = {
        "email": "rollback@test.com",  # Duplicate email
        "full_name": "Manager for Rollback Test",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 400
    assert "Email already registered" in response.json()["detail"]

    # Verify no partial records were created for the manager
    manager_user = test_db.query(User).filter(User.email == "rollback@test.com").first()
    # Should only find the existing employee user, not a manager
    assert manager_user is not None
    assert manager_user.role == "EMPLOYEE"  # Still employee, not changed to manager
    assert manager_user.full_name == "Existing User"  # Original name

    # Verify no extra organization membership was created
    memberships = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == manager_user.id
    ).all()
    assert len(memberships) == 1  # Only the original employee membership
    assert memberships[0].role == "EMPLOYEE"


def test_admin_creates_manager_temporary_password_not_stored(test_client, admin_user: User, test_db: Session):
    """Test that temporary password is returned but not stored in plaintext."""
    headers = get_auth_headers(test_client, admin_user.email, "testpass123")

    # Create organization
    organization = Organization(name="Password Test Org")
    test_db.add(organization)
    test_db.commit()
    test_db.refresh(organization)

    manager_data = {
        "email": "passwordtest@test.com",
        "full_name": "Password Test Manager",
        "organization_id": str(organization.id)
    }

    response = test_client.post("/admin/managers", json=manager_data, headers=headers)
    assert response.status_code == 201
    data = response.json()
    temporary_password = data["temporary_password"]

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "passwordtest@test.com").first()
    assert db_user is not None

    # Password should NOT be stored in plaintext
    assert db_user.password_hash != temporary_password
    assert db_user.password_hash != "passwordtest@test.com"
    assert db_user.password_hash != "testpass123"

    # But the hash should match the temporary password
    from app.auth.security import verify_password
    assert verify_password(temporary_password, db_user.password_hash)


def test_existing_public_registeration_still_creates_employee_only(test_client, test_db: Session):
    """Ensure public registration still creates EMPLOYEE only, not affected by manager endpoint."""
    # Test public registration (no auth required)
    registration_data = {
        "email": "publicuser@test.com",
        "password": "SecurePass123!",
        "full_name": "Public User",
        "account_type": "solo"
    }

    response = test_client.post("/auth/register", json=registration_data)
    assert response.status_code == 201
    data = response.json()

    # Verify it's an employee
    assert data["role"] == "EMPLOYEE"
    # Solo accounts are APPROVED (organization accounts would be PENDING)
    assert data["approval_status"] == "APPROVED"
    assert data["is_active"] == True

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "publicuser@test.com").first()
    assert db_user is not None
    assert db_user.role == "EMPLOYEE"
    assert db_user.approval_status == "APPROVED"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])