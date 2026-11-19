"""Tests for employee deactivation endpoint."""

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
def employee_user(manager_user: User, test_db: Session) -> User:
    """Create an EMPLOYEE user in the same organization as the manager."""
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

    # Create profile
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
    test_db.flush()

    # Use the same organization as the manager
    manager_org_id = None
    for membership in test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == manager_user.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).all():
        manager_org_id = membership.organization_id
        break

    org_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=manager_org_id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(org_membership)
    test_db.commit()

    return user


def test_manager_can_deactivate_employee_in_own_org(test_client, manager_user: User, employee_user: User, test_db: Session):
    """Test that a manager can deactivate an employee in their own organization."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Deactivate the employee
    response = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)

    assert response.status_code == 200
    data = response.json()

    # Verify response indicates deactivation
    assert data["is_active"] == False
    assert str(data["id"]) == str(employee_user.id)
    assert data["email"] == employee_user.email
    assert data["role"] == "EMPLOYEE"
    assert data["approval_status"] == "APPROVED"

    # Verify in database
    db_employee = test_db.query(User).filter(User.id == employee_user.id).first()
    assert db_employee is not None
    assert db_employee.is_active == False
    assert db_employee.role == "EMPLOYEE"  # Role unchanged
    assert db_employee.email == employee_user.email
    assert db_employee.full_name == employee_user.full_name

    # Verify profile still exists
    profile = test_db.query(Profile).filter(Profile.user_id == db_employee.id).first()
    assert profile is not None

    # Verify organization membership still exists
    org_membership = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_employee.id,
        OrganizationMembership.role == "EMPLOYEE",
        OrganizationMembership.status == "APPROVED"
    ).first()
    assert org_membership is not None


def test_manager_cannot_deactivate_employee_from_other_org(test_client, manager_user: User, test_db: Session):
    """Test that a manager cannot deactivate an employee from another organization."""
    # Create another organization and employee
    other_org = Organization(name=f"Other Org {uuid.uuid4().hex[:8]}")
    test_db.add(other_org)
    test_db.flush()

    other_employee = User(
        email=f"otheremployee_{uuid.uuid4().hex[:8]}@test.com",
        full_name=f"Other Employee {uuid.uuid4().hex[:8]}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(other_employee)
    test_db.flush()

    other_profile = Profile(
        user_id=other_employee.id,
        job_role="Developer",
        industry="Technology",
        years_of_experience=5,
        age=28,
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
    )
    test_db.add(other_profile)
    test_db.flush()

    other_org_membership = OrganizationMembership(
        user_id=other_employee.id,
        organization_id=other_org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(other_org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Try to deactivate employee from other organization
    response = test_client.patch(f"/employees/{other_employee.id}/deactivate", headers=headers)

    # Should be forbidden
    assert response.status_code == 403
    assert "Employee does not belong to your organization" in response.json()["detail"]

    # Verify employee is still active
    db_employee = test_db.query(User).filter(User.id == other_employee.id).first()
    assert db_employee.is_active == True


def test_manager_cannot_deactivate_another_manager(test_client, manager_user: User, test_db: Session):
    """Test that a manager cannot deactivate another manager."""
    # Create another manager
    other_manager = User(
        email=f"othermanager_{uuid.uuid4().hex[:8]}@test.com",
        full_name=f"Other Manager {uuid.uuid4().hex[:8]}",
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

    # Create organization and MANAGER membership for other manager
    other_org = Organization(name=f"Other Org {uuid.uuid4().hex[:8]}")
    test_db.add(other_org)
    test_db.flush()

    other_org_membership = OrganizationMembership(
        user_id=other_manager.id,
        organization_id=other_org.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add(other_org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Try to deactivate the other manager
    response = test_client.patch(f"/employees/{other_manager.id}/deactivate", headers=headers)

    # Should be bad request (can only deactivate employees)
    assert response.status_code == 400
    assert "Can only deactivate employees with role=EMPLOYEE" in response.json()["detail"]

    # Verify other manager is still active
    db_manager = test_db.query(User).filter(User.id == other_manager.id).first()
    assert db_manager.is_active == True
    assert db_manager.role == "MANAGER"


def test_manager_cannot_deactivate_admin(test_client, manager_user: User, test_db: Session):
    """Test that a manager cannot deactivate an admin user."""
    # Create an admin user
    admin_user = User(
        email=f"admin_{uuid.uuid4().hex[:8]}@test.com",
        full_name=f"Admin User {uuid.uuid4().hex[:8]}",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(admin_user)
    test_db.flush()

    admin_profile = Profile(
        user_id=admin_user.id,
        job_role="Admin",
        industry="Technology",
        years_of_experience=10,
        age=35,
        education_attainment="PhD",
        marital_status="Married",
        target_daily_hours=8,
    )
    test_db.add(admin_profile)
    test_db.flush()

    # Create organization and ADMIN membership for admin
    admin_org = Organization(name=f"Admin Org {uuid.uuid4().hex[:8]}")
    test_db.add(admin_org)
    test_db.flush()

    admin_org_membership = OrganizationMembership(
        user_id=admin_user.id,
        organization_id=admin_org.id,
        role="ADMIN",
        status="APPROVED"
    )
    test_db.add(admin_org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Try to deactivate the admin
    response = test_client.patch(f"/employees/{admin_user.id}/deactivate", headers=headers)

    # Should be bad request (can only deactivate employees)
    assert response.status_code == 400
    assert "Can only deactivate employees with role=EMPLOYEE" in response.json()["detail"]

    # Verify admin is still active
    db_admin = test_db.query(User).filter(User.id == admin_user.id).first()
    assert db_admin.is_active == True
    assert db_admin.role == "ADMIN"


def test_non_manager_cannot_use_endpoint(test_client, employee_user: User, test_db: Session):
    """Test that non-manager users cannot use the deactivation endpoint."""
    # Create a regular employee (not manager)
    regular_employee = User(
        email=f"regular_{uuid.uuid4().hex[:8]}@test.com",
        full_name=f"Regular Employee {uuid.uuid4().hex[:8]}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(regular_employee)
    test_db.flush()

    regular_profile = Profile(
        user_id=regular_employee.id,
        job_role="Developer",
        industry="Technology",
        years_of_experience=3,
        age=25,
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
    )
    test_db.add(regular_profile)
    test_db.flush()

    # Create organization and EMPLOYEE membership
    regular_org = Organization(name=f"Regular Org {uuid.uuid4().hex[:8]}")
    test_db.add(regular_org)
    test_db.flush()

    regular_org_membership = OrganizationMembership(
        user_id=regular_employee.id,
        organization_id=regular_org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(regular_org_membership)
    test_db.commit()

    headers = get_auth_headers(test_client, regular_employee.email, "testpass123")

    # Try to deactivate an employee (should be forbidden)
    response = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)

    # Should be forbidden
    assert response.status_code == 403
    assert "Not enough permissions" in response.json()["detail"]


def test_nonexistent_employee_returns_404(test_client, manager_user: User, test_db: Session):
    """Test that deactivating a nonexistent employee returns 404."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    fake_employee_id = str(uuid.uuid4())

    response = test_client.patch(f"/employees/{fake_employee_id}/deactivate", headers=headers)

    assert response.status_code == 404
    assert "Employee not found" in response.json()["detail"]


def test_deactivating_already_inactive_employee(test_client, manager_user: User, employee_user: User, test_db: Session):
    """Test that deactivating an already inactive employee is handled consistently."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # First deactivate the employee
    response1 = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)
    assert response1.status_code == 200
    assert response1.json()["is_active"] == False

    # Try to deactivate again (should still succeed)
    response2 = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)
    assert response2.status_code == 200
    assert response2.json()["is_active"] == False

    # Verify in database
    db_employee = test_db.query(User).filter(User.id == employee_user.id).first()
    assert db_employee.is_active == False


def test_deactivation_preserves_profile_and_membership(test_client, manager_user: User, employee_user: User, test_db: Session):
    """Test that deactivation preserves Profile and OrganizationMembership."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Get initial counts
    initial_profile_count = test_db.query(Profile).filter(Profile.user_id == employee_user.id).count()
    initial_membership_count = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == employee_user.id,
        OrganizationMembership.role == "EMPLOYEE"
    ).count()

    # Deactivate the employee
    response = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)
    assert response.status_code == 200

    # Verify profile still exists
    profile_after = test_db.query(Profile).filter(Profile.user_id == employee_user.id).count()
    assert profile_after == initial_profile_count

    # Verify organization membership still exists
    membership_after = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == employee_user.id,
        OrganizationMembership.role == "EMPLOYEE"
    ).count()
    assert membership_after == initial_membership_count

    # Verify user still exists but is inactive
    db_employee = test_db.query(User).filter(User.id == employee_user.id).first()
    assert db_employee is not None
    assert db_employee.is_active == False


def test_deactivation_does_not_change_user_role(test_client, manager_user: User, employee_user: User, test_db: Session):
    """Test that deactivation does not change the user's role."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Verify initial role
    db_employee_before = test_db.query(User).filter(User.id == employee_user.id).first()
    assert db_employee_before.role == "EMPLOYEE"

    # Deactivate the employee
    response = test_client.patch(f"/employees/{employee_user.id}/deactivate", headers=headers)
    assert response.status_code == 200

    # Verify role unchanged
    db_employee_after = test_db.query(User).filter(User.id == employee_user.id).first()
    assert db_employee_after.role == "EMPLOYEE"
    assert db_employee_after.is_active == False


def test_existing_employee_provisioning_unaffected(test_client, manager_user: User, test_db: Session):
    """Test that existing employee provisioning behavior remains unaffected."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Create a new employee via provisioning
    employee_data = {
        "email": "newemployee@test.com",
        "full_name": "New Employee",
        "team_id": None
    }

    response = test_client.post("/employees", json=employee_data, headers=headers)
    assert response.status_code == 201
    data = response.json()

    # Verify creation still works
    assert data["is_active"] == True
    assert data["role"] == "EMPLOYEE"
    assert data["must_change_password"] == True
    assert "temporary_password" in data

    # Verify in database
    db_user = test_db.query(User).filter(User.email == "newemployee@test.com").first()
    assert db_user is not None
    assert db_user.is_active == True
    assert db_user.role == "EMPLOYEE"
    assert db_user.approval_status == "APPROVED"

    # Now deactivate it
    deactivate_response = test_client.patch(f"/employees/{db_user.id}/deactivate", headers=headers)
    assert deactivate_response.status_code == 200
    assert deactivate_response.json()["is_active"] == False

    # Verify still in database but inactive
    db_user_after = test_db.query(User).filter(User.email == "newemployee@test.com").first()
    assert db_user_after.is_active == False
    assert db_user_after.role == "EMPLOYEE"