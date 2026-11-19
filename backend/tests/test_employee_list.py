"""Tests for employee list endpoint."""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid

from app.main import app
from app.database import get_db
from app.models import User, Profile, Organization, OrganizationMembership, Team, TeamMembership
from app.auth.security import get_password_hash


@pytest.fixture
def test_client(test_db: Session):
    return TestClient(app)


def get_auth_headers(client: TestClient, email: str, password: str):
    response = client.post("/auth/login", json={"email": email, "password": password})
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def manager_user(test_db: Session) -> User:
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
    profile = Profile(
        user_id=user.id,
        job_role="Manager",
        industry="Technology",
        years_of_experience=10,
        age=35,
    )
    test_db.add(profile)
    test_db.flush()
    org = Organization(name=f"Test Org {unique_id}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=user.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    ))
    test_db.commit()
    test_db.refresh(user)
    return user


@pytest.fixture
def employee_user_in_org(test_db: Session, manager_user: User) -> User:
    """Create employee with approved membership in manager's organization."""
    # Resolve manager's org
    from app.models import OrganizationMembership
    manager_mem = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == manager_user.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).first()
    unique_id = str(uuid.uuid4())[:8]
    email = f"emp_{unique_id}@test.com"
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
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=user.id,
        organization_id=manager_mem.organization_id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()
    test_db.refresh(user)
    return user


# 1. Manager can list employees in their own organization

def test_manager_lists_own_employees(test_client, manager_user, employee_user_in_org, test_db):
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert any(item["email"] == employee_user_in_org.email for item in data)


# 2. Employees from another organization are excluded

def test_cross_org_employee_excluded(test_client, manager_user, test_db):
    # Create another manager + org + employee
    unique_id = str(uuid.uuid4())[:8]
    other_email = f"other_{unique_id}@test.com"
    other_user = User(
        email=other_email,
        full_name=f"Other {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(other_user)
    test_db.flush()
    profile = Profile(user_id=other_user.id)
    test_db.add(profile)
    test_db.flush()
    other_org = Organization(name=f"Other Org {unique_id}")
    test_db.add(other_org)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=other_user.id,
        organization_id=other_org.id,
        role="MANAGER",
        status="APPROVED"
    ))
    # Create employee in OTHER org
    other_employee_email = f"other_emp_{unique_id}@test.com"
    other_employee = User(
        email=other_employee_email,
        full_name=f"Other Emp {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(other_employee)
    test_db.flush()
    other_emp_profile = Profile(user_id=other_employee.id)
    test_db.add(other_emp_profile)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=other_employee.id,
        organization_id=other_org.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert not any(item["email"] == other_employee_email for item in data)


# 3. Managers are excluded

def test_managers_excluded_from_list(test_client, manager_user, test_db):
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert not any(item.get("role") == "MANAGER" for item in data)
    # Manager user themselves should not appear
    assert not any(item["email"] == manager_user.email for item in data)


# 4. Admins are excluded

def test_admins_excluded(test_client, manager_user, test_db):
    admin_email = f"admin_{str(uuid.uuid4())[:8]}@test.com"
    admin_user = User(
        email=admin_email,
        full_name="Admin User",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(admin_user)
    test_db.flush()
    profile = Profile(user_id=admin_user.id)
    test_db.add(profile)
    test_db.flush()
    # Give admin an org membership to avoid authorization errors
    org = test_db.query(Organization).first()
    if not org:
        org = Organization(name="Admin Org")
        test_db.add(org)
        test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=admin_user.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    ))
    test_db.commit()
    # Admin should not be able to access manager endpoint anyway,
    # but if they did, they shouldn't appear in list.
    # This test verifies the endpoint excludes ADMIN role users.
    # We test by using manager headers and ensuring admin isn't in list.
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert not any(item["email"] == admin_email for item in data)


# 5. Non-manager cannot access endpoint

def test_non_manager_cannot_access(test_client, employee_user_in_org, test_db):
    headers = get_auth_headers(test_client, employee_user_in_org.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 403


# 6. Manager with no approved organization membership receives forbidden

def test_manager_no_approved_membership_forbidden(test_client, test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_no_{unique_id}@test.com"
    user = User(
        email=email,
        full_name=f"No Org Manager {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.commit()
    headers = get_auth_headers(test_client, user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 403


# 7. Inactive employees still returned with is_active=False

def test_inactive_employee_returned(test_client, manager_user, test_db):
    # Create active employee then deactivate via patch
    unique_id = str(uuid.uuid4())[:8]
    email = f"inactive_{unique_id}@test.com"
    user = User(
        email=email,
        full_name=f"Inactive {unique_id}",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.flush()
    manager_mem = test_db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == manager_user.id,
        OrganizationMembership.role == "MANAGER",
        OrganizationMembership.status == "APPROVED"
    ).first()
    test_db.add(OrganizationMembership(
        user_id=user.id,
        organization_id=manager_mem.organization_id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()

    # Deactivate
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    deactivate_response = test_client.patch(f"/employees/{user.id}/deactivate", headers=headers)
    assert deactivate_response.status_code == 200

    # List should include with is_active=False
    list_response = test_client.get("/employees", headers=headers)
    assert list_response.status_code == 200
    data = list_response.json()
    item = next((i for i in data if i["email"] == email), None)
    assert item is not None
    assert item["is_active"] == False


# 8. Team information is correct when employee belongs to a team

def test_employee_team_info_correct(test_client, manager_user, test_db):
    # Create team
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    team_data = {"name": "Team For List", "description": "Test"}
    team_resp = test_client.post("/teams", json=team_data, headers=headers)
    assert team_resp.status_code == 201
    team_id = team_resp.json()["id"]

    # Create employee with team assignment
    unique_id = str(uuid.uuid4())[:8]
    email = f"teamemp_{unique_id}@test.com"
    employee_data = {
        "email": email,
        "full_name": f"Team Emp {unique_id}",
        "team_id": team_id
    }
    create_resp = test_client.post("/employees", json=employee_data, headers=headers)
    assert create_resp.status_code == 201

    # List and verify team info
    list_resp = test_client.get("/employees", headers=headers)
    assert list_resp.status_code == 200
    data = list_resp.json()
    item = next((i for i in data if i["email"] == email), None)
    assert item is not None
    assert item.get("team_name") == "Team For List"
    assert item.get("team_id") == team_id


# 9. No employee data outside the manager's organization is leaked

def test_no_cross_org_leak(test_client, manager_user, test_db):
    # This is a stronger version of test 2 ensuring strict isolation
    unique_id = str(uuid.uuid4())[:8]
    other_email = f"leak_{unique_id}@test.com"
    other_org_name = f"Leak Org {unique_id}"

    # Another manager/org/employee
    other_manager_email = f"leak_mgr_{unique_id}@test.com"
    other_manager = User(
        email=other_manager_email,
        full_name="Leak Manager",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    test_db.add(other_manager)
    test_db.flush()
    test_db.add(Profile(user_id=other_manager.id))
    test_db.flush()
    other_org = Organization(name=other_org_name)
    test_db.add(other_org)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=other_manager.id,
        organization_id=other_org.id,
        role="MANAGER",
        status="APPROVED"
    ))
    # Employee in other org
    other_emp_email = f"leak_emp_{unique_id}@test.com"
    other_emp = User(
        email=other_emp_email,
        full_name="Leak Employee",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(other_emp)
    test_db.flush()
    test_db.add(Profile(user_id=other_emp.id))
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=other_emp.id,
        organization_id=other_org.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    response = test_client.get("/employees", headers=headers)
    assert response.status_code == 200
    data = response.json()
    # Ensure no leak of other manager, other employee, or other org details
    assert not any(item["email"] == other_manager_email for item in data)
    assert not any(item["email"] == other_emp_email for item in data)
