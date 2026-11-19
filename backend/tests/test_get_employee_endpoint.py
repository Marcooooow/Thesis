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

    # Create access token
    access_token = create_access_token(data={"sub": admin_user.email})
    return access_token

@pytest.fixture
def test_employee(db_session):
    """Create a test employee user."""
    admin_user = db_session.query(models.User).filter_by(role="ADMIN").first()
    if not admin_user:
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

    # Create organization membership for admin
    admin_org_mem = models.OrganizationMembership(
        user_id=admin_user.id,
        organization_id=uuid4(),  # This will be auto-generated
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(admin_org_mem)

    # Create organization membership for employee (same org as admin)
    emp_org_mem = models.OrganizationMembership(
        user_id=employee.id,
        organization_id=admin_org_mem.organization_id,  # Same org as admin
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(emp_org_mem)

    db_session.commit()
    db_session.refresh(employee)
    return employee

def test_get_employee_success(db_session, admin_token, test_employee):
    """Test that admin can get employee details by ID."""
    response = client.get(
        f"/employees/{test_employee.id}",
        headers={"Authorization": f"Bearer {admin_token}"}
    )

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(test_employee.id)
    assert data["email"] == test_employee.email
    assert data["full_name"] == test_employee.full_name
    assert data["role"] == test_employee.role
    assert data["is_active"] == test_employee.is_active
    assert data["approval_status"] == test_employee.approval_status

def test_get_employee_not_found(db_session, admin_token):
    """Test that getting non-existent employee returns 404."""
    fake_id = uuid4()
    response = client.get(
        f"/employees/{fake_id}",
        headers={"Authorization": f"Bearer {admin_token}"}
    )

    assert response.status_code == 404
    assert "Employee not found" in response.json()["detail"]

def test_get_employee_unauthorized(db_session, test_employee):
    """Test that non-admin users cannot access employee endpoint."""
    # Create a regular employee user
    regular_user = models.User(
        email="regular@example.com",
        full_name="Regular User",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("regularpassword123"),
    )
    db_session.add(regular_user)
    db_session.commit()
    db_session.refresh(regular_user)

    # Create token for regular employee
    access_token = create_access_token(data={"sub": regular_user.email})

    response = client.get(
        f"/employees/{test_employee.id}",
        headers={"Authorization": f"Bearer {access_token}"}
    )

    assert response.status_code == 403  # Forbidden
    assert "Unauthorized role" in response.json()["detail"]

def test_get_employee_cross_org_access_denied(db_session, admin_token):
    """Test that admin cannot access employee from different organization."""
    # Create admin user (already exists from fixture)
    admin_user = db_session.query(models.User).filter(models.User.email == "admin@example.com").first()

    # Create admin organization membership
    admin_org_mem = models.OrganizationMembership(
        user_id=admin_user.id,
        organization_id=uuid4(),
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(admin_org_mem)
    db_session.commit()

    # Create a second organization
    org2 = models.Organization(name="Second Organization")
    db_session.add(org2)
    db_session.commit()
    db_session.refresh(org2)

    # Create employee in second organization
    employee_in_org2 = models.User(
        email="employee2@example.com",
        full_name="Employee In Org2",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("employeepassword123"),
    )
    db_session.add(employee_in_org2)
    db_session.commit()
    db_session.refresh(employee_in_org2)

    # Create organization membership for employee in org2
    emp_org_mem2 = models.OrganizationMembership(
        user_id=employee_in_org2.id,
        organization_id=org2.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(emp_org_mem2)
    db_session.commit()

    # Try to access employee from org2 with admin token (admin is in org1)
    response = client.get(
        f"/employees/{employee_in_org2.id}",
        headers={"Authorization": f"Bearer {admin_token}"}
    )

    assert response.status_code == 403  # Forbidden
    assert "Employee does not belong to your organization" in response.json()["detail"]

def test_get_employee_invalid_uuid(db_session, admin_token):
    """Test that invalid UUID returns 400 error."""
    response = client.get(
        "/employees/invalid-uuid",
        headers={"Authorization": f"Bearer {admin_token}"}
    )

    assert response.status_code == 400
    assert "Invalid employee ID format" in response.json()["detail"]


def test_get_employee_live_status_inactive(db_session, admin_token, test_employee):
    """Test live-status for employee with no active session returns Not Started."""
    profile = models.Profile(
        user_id=test_employee.id,
        target_daily_hours=8,
        shift_start_time="09:00",
        shift_end_time="17:00",
        work_days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    )
    db_session.add(profile)
    db_session.commit()

    response = client.get(
        f"/employees/{test_employee.id}/live-status",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Not Started"
    assert data["active_work_session"] is None


def test_get_employee_live_status_active(db_session, admin_token, test_employee):
    """Test live-status for employee with active session returns Working / On Shift."""
    from datetime import datetime, timezone
    profile = models.Profile(
        user_id=test_employee.id,
        target_daily_hours=8,
        shift_start_time="09:00",
        shift_end_time="17:00",
        work_days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    )
    db_session.add(profile)
    db_session.commit()
    db_session.refresh(profile)

    session = models.WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc),
        ended_at=None
    )
    db_session.add(session)
    db_session.commit()
    db_session.refresh(session)

    response = client.get(
        f"/employees/{test_employee.id}/live-status",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Working / On Shift"
    assert data["active_work_session"] is not None
    assert data["active_work_session"]["id"] == str(session.id)


def test_get_employee_live_status_not_found(db_session, admin_token):
    """Test live-status for non-existent employee returns 404."""
    fake_id = uuid4()
    response = client.get(
        f"/employees/{fake_id}/live-status",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert response.status_code == 404


def test_get_employee_live_status_missing_profile_auto_created(db_session, admin_token):
    """Test that an employee user created without a profile record successfully auto-creates profile and returns live status."""
    org = models.Organization(name="Test Org")
    db_session.add(org)
    db_session.commit()
    db_session.refresh(org)

    admin_user = db_session.query(models.User).filter_by(email="admin@example.com").first()
    admin_org_mem = models.OrganizationMembership(
        user_id=admin_user.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db_session.add(admin_org_mem)

    employee = models.User(
        email="noprofile@example.com",
        full_name="No Profile Employee",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(employee)

    emp_org_mem = models.OrganizationMembership(
        user_id=employee.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(emp_org_mem)
    db_session.commit()

    response = client.get(
        f"/employees/{employee.id}/live-status",
        headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Not Started"


def test_get_employee_live_status_manager_without_team_membership(db_session):
    """Test that a manager can access live status for an employee in their org even without explicit team membership."""
    org = models.Organization(name="Manager Org")
    db_session.add(org)
    db_session.commit()
    db_session.refresh(org)

    manager = models.User(
        email="manager_org@example.com",
        full_name="Org Manager",
        role="MANAGER",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(manager)
    db_session.commit()
    db_session.refresh(manager)

    manager_org_mem = models.OrganizationMembership(
        user_id=manager.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(manager_org_mem)

    employee = models.User(
        email="org_employee@example.com",
        full_name="Org Employee",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(employee)

    emp_org_mem = models.OrganizationMembership(
        user_id=employee.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db_session.add(emp_org_mem)
    db_session.commit()

    manager_token = create_access_token(data={"sub": manager.email})

    response = client.get(
        f"/employees/{employee.id}/live-status",
        headers={"Authorization": f"Bearer {manager_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Not Started"


def test_get_employee_live_status_manager_cross_org_denied(db_session):
    """Test that a manager cannot access live status for an employee in a different organization."""
    org1 = models.Organization(name="Org 1")
    org2 = models.Organization(name="Org 2")
    db_session.add_all([org1, org2])
    db_session.commit()

    manager = models.User(
        email="manager1@example.com",
        full_name="Manager 1",
        role="MANAGER",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(manager)
    db_session.commit()
    db_session.refresh(manager)

    db_session.add(models.OrganizationMembership(
        user_id=manager.id,
        organization_id=org1.id,
        role="MANAGER",
        status="APPROVED"
    ))

    employee2 = models.User(
        email="employee2@example.com",
        full_name="Employee 2",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("employeepassword123"),
    )
    db_session.add(employee2)
    db_session.commit()
    db_session.refresh(employee2)

    db_session.add(models.OrganizationMembership(
        user_id=employee2.id,
        organization_id=org2.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    db_session.commit()

    manager_token = create_access_token(data={"sub": manager.email})

    response = client.get(
        f"/employees/{employee2.id}/live-status",
        headers={"Authorization": f"Bearer {manager_token}"}
    )
    assert response.status_code == 403
    assert "Employee does not belong to your organization" in response.json()["detail"]


def test_get_employee_live_status_manager_with_team_membership(db_session):
    """Test that a manager can access live status for an employee with explicit team membership."""
    org = models.Organization(name="Team Org")
    db_session.add(org)
    db_session.commit()
    db_session.refresh(org)

    manager = models.User(
        email="manager_team@example.com",
        full_name="Team Manager",
        role="MANAGER",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(manager)
    db_session.commit()
    db_session.refresh(manager)

    db_session.add(models.OrganizationMembership(
        user_id=manager.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    ))

    team = models.Team(name="Team Alpha", organization_id=org.id, manager_user_id=manager.id)
    db_session.add(team)
    db_session.commit()
    db_session.refresh(team)

    employee = models.User(
        email="team_employee@example.com",
        full_name="Team Employee",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(employee)

    db_session.add(models.OrganizationMembership(
        user_id=employee.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))

    profile = models.Profile(user_id=employee.id)
    db_session.add(profile)
    db_session.commit()
    db_session.refresh(profile)

    db_session.add(models.TeamMembership(
        team_id=team.id,
        profile_id=profile.id
    ))
    db_session.commit()

    manager_token = create_access_token(data={"sub": manager.email})

    response = client.get(
        f"/employees/{employee.id}/live-status",
        headers={"Authorization": f"Bearer {manager_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Not Started"


def test_get_employee_live_status_manager_team_member(db_session):
    """Test that a manager can access live status for an employee in their team."""
    org = models.Organization(name="Team Org 2")
    db_session.add(org)
    db_session.commit()
    db_session.refresh(org)

    manager = models.User(
        email="manager_team2@example.com",
        full_name="Team Manager 2",
        role="MANAGER",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(manager)
    db_session.commit()
    db_session.refresh(manager)

    db_session.add(models.OrganizationMembership(
        user_id=manager.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    ))

    team = models.Team(name="Team Beta", organization_id=org.id, manager_user_id=manager.id)
    db_session.add(team)
    db_session.commit()
    db_session.refresh(team)

    employee = models.User(
        email="team_member_other@example.com",
        full_name="Team Member Other",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(employee)

    db_session.add(models.OrganizationMembership(
        user_id=employee.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))

    profile = models.Profile(user_id=employee.id)
    db_session.add(profile)
    db_session.commit()
    db_session.refresh(profile)

    db_session.add(models.TeamMembership(
        team_id=team.id,
        profile_id=profile.id
    ))
    db_session.commit()

    manager_token = create_access_token(data={"sub": manager.email})

    response = client.get(
        f"/employees/{employee.id}/live-status",
        headers={"Authorization": f"Bearer {manager_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["status_category"] == "Not Started"


def test_get_employee_global_admin_success(db_session):
    """Test that an admin with no organization memberships (global admin) can access employee details."""
    global_admin = models.User(
        email="global_admin@example.com",
        full_name="Global Admin",
        role="ADMIN",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(global_admin)

    employee = models.User(
        email="emp_global@example.com",
        full_name="Emp Global",
        role="EMPLOYEE",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("password123"),
    )
    db_session.add(employee)
    db_session.commit()
    db_session.refresh(global_admin)
    db_session.refresh(employee)

    global_admin_token = create_access_token(data={"sub": global_admin.email})

    response = client.get(
        f"/employees/{employee.id}",
        headers={"Authorization": f"Bearer {global_admin_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(employee.id)
    assert data["email"] == employee.email
