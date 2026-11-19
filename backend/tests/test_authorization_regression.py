"""
Authorization regression tests.
"""
import pytest
from app.auth.security import SECRET_KEY, ALGORITHM
from jose import jwt
from datetime import datetime, timedelta
from app.models import User, Organization, OrganizationMembership
from app.auth.security import get_password_hash


def get_auth_headers(client, email, password):
    """Get authentication headers for a user."""
    login_data = {"email": email, "password": password}
    response = client.post("/auth/login", json=login_data)
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_employee_cannot_access_manager_endpoints(test_client, test_user):
    """Employee cannot access manager-only endpoints."""
    # test_user is an Employee fixture from conftest.py
    headers = get_auth_headers(test_client, test_user.email, "testpassword123")
    # Create endpoint requires manager role
    response = test_client.post("/employees/", json={
        "email": "new@test.com", "full_name": "New"
    }, headers=headers)
    assert response.status_code == 403


def test_unauthenticated_requests_rejected(test_client):
    """Unauthenticated requests are rejected."""
    endpoints = [
        ("GET", "/auth/me"),
        ("GET", "/employees/"),
    ]
    for method, endpoint in endpoints:
        if method == "GET":
            response = test_client.get(endpoint)
        else:
            response = test_client.post(endpoint)
        assert response.status_code == 401


def test_expired_token_rejected(test_client, test_user):
    """Expired JWT tokens are rejected."""
    expired_token = jwt.encode(
        {"sub": test_user.email, "type": "access", "exp": datetime.utcnow() - timedelta(minutes=10)},
        SECRET_KEY, algorithm=ALGORITHM
    )
    response = test_client.get("/auth/me", headers={"Authorization": f"Bearer {expired_token}"})
    assert response.status_code == 401


def test_manager_can_only_see_own_org_employees(test_client, test_db):
    """Manager can only list employees from their own organization."""
    # Create org A
    org_a = Organization(name="Org A")
    test_db.add(org_a)
    test_db.flush()

    # Create manager in org A
    manager = User(
        email="manager@test.com",
        full_name="Manager",
        password_hash=get_password_hash("testpass123"),
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(manager)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=manager.id,
        organization_id=org_a.id,
        role="MANAGER",
        status="APPROVED"
    ))

    # Create employee in org A
    emp_a = User(
        email="emp_a@test.com",
        full_name="Employee A",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(emp_a)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=emp_a.id,
        organization_id=org_a.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))

    # Create org B
    org_b = Organization(name="Org B")
    test_db.add(org_b)
    test_db.flush()

    # Create employee in org B
    emp_b = User(
        email="emp_b@test.com",
        full_name="Employee B",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(emp_b)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=emp_b.id,
        organization_id=org_b.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()

    # Login as manager
    login_resp = test_client.post("/auth/login", json={
        "email": manager.email,
        "password": "testpass123"
    })
    manager_token = login_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {manager_token}"}

    # Manager lists employees
    response = test_client.get("/employees/", headers=headers)
    assert response.status_code == 200
    data = response.json()
    # Should only see employees from org A (emp_a)
    emails = [emp["email"] for emp in data]
    assert emp_a.email in emails
    assert emp_b.email not in emails


def test_global_admin_can_access_any_employee(test_client, test_db):
    """Global admin (no org memberships) can access employees across orgs."""
    global_admin = User(
        email="global_admin@test.com",
        full_name="Global Admin",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(global_admin)
    test_db.flush()

    emp = User(
        email="emp_global@test.com",
        full_name="Employee Global",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(emp)
    test_db.commit()

    headers = get_auth_headers(test_client, global_admin.email, "testpass123")
    response = test_client.get(f"/employees/{emp.id}/live-status", headers=headers)
    assert response.status_code == 200


def test_org_scoped_admin_cross_org_access_denied(test_client, test_db):
    """Org-scoped admin cannot access employee in another organization."""
    org_a = Organization(name="Admin Org A")
    org_b = Organization(name="Employee Org B")
    test_db.add_all([org_a, org_b])
    test_db.flush()

    admin_scoped = User(
        email="scoped_admin@test.com",
        full_name="Scoped Admin",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(admin_scoped)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=admin_scoped.id,
        organization_id=org_a.id,
        role="MANAGER",
        status="APPROVED"
    ))

    emp_b = User(
        email="emp_orgb@test.com",
        full_name="Emp Org B",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(emp_b)
    test_db.flush()
    test_db.add(OrganizationMembership(
        user_id=emp_b.id,
        organization_id=org_b.id,
        role="EMPLOYEE",
        status="APPROVED"
    ))
    test_db.commit()

    headers = get_auth_headers(test_client, admin_scoped.email, "testpass123")
    response = test_client.get(f"/employees/{emp_b.id}/live-status", headers=headers)
    assert response.status_code == 403
    assert "does not belong to your organization" in response.json()["detail"]


def test_global_admin_can_access_recommendations_and_wellbeing(test_client, test_db):
    """Global admin can access recommendations and wellbeing endpoints for any user."""
    global_admin = User(
        email="global_admin_rec@test.com",
        full_name="Global Admin Rec",
        password_hash=get_password_hash("testpass123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(global_admin)
    test_db.flush()

    emp = User(
        email="emp_rec@test.com",
        full_name="Emp Rec",
        password_hash=get_password_hash("testpass123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    test_db.add(emp)
    test_db.flush()
    org = Organization(name="Global Admin Access Org")
    test_db.add(org)
    test_db.flush()
    test_db.add_all([
        OrganizationMembership(user_id=global_admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"),
        OrganizationMembership(user_id=emp.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"),
    ])
    test_db.commit()

    headers = get_auth_headers(test_client, global_admin.email, "testpass123")

    res_emp = test_client.get(f"/employees/{emp.id}", headers=headers)
    assert res_emp.status_code == 200

    res_rec = test_client.get(f"/admin/users/{emp.id}/recommendations", headers=headers)
    assert res_rec.status_code == 200

    res_wb = test_client.get(f"/admin/users/{emp.id}/wellbeing", headers=headers)
    assert res_wb.status_code == 200