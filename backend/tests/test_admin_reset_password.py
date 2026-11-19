"""
Tests for Admin Reset Password endpoint.
"""
import pytest
from app.models import User
from app.auth.security import get_password_hash


def test_admin_reset_password_success(test_client, test_db):
    """Test that admin can successfully reset a user's password."""
    # Create admin user
    admin_user = User(
        email="admin_reset@example.com",
        full_name="Admin Reset",
        password_hash=get_password_hash("testpassword123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    # Create employee user
    employee_user = User(
        email="emp_reset@example.com",
        full_name="Employee Reset",
        password_hash=get_password_hash("oldpassword123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    test_db.add_all([admin_user, employee_user])
    test_db.commit()
    test_db.refresh(employee_user)

    # Login as admin
    login_response = test_client.post("/auth/login", json={
        "email": "admin_reset@example.com",
        "password": "testpassword123"
    })
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Reset employee password
    reset_response = test_client.post(f"/auth/admin/users/{employee_user.id}/reset-password", headers=headers)
    assert reset_response.status_code == 200
    data = reset_response.json()
    assert "temporary_password" in data
    temp_password = data["temporary_password"]
    assert len(temp_password) > 0

    # Verify employee can login with temporary password and must_change_password is True
    emp_login = test_client.post("/auth/login", json={
        "email": "emp_reset@example.com",
        "password": temp_password
    })
    assert emp_login.status_code == 200
    emp_login_data = emp_login.json()
    assert emp_login_data.get("requires_2fa") is False
    # Restricted first-login token should be returned because must_change_password = True
    assert "access_token" in emp_login_data


def test_non_admin_cannot_reset_password(test_client, test_db):
    """Test that non-admin users cannot reset passwords."""
    employee_user = User(
        email="emp_notadmin@example.com",
        full_name="Emp Not Admin",
        password_hash=get_password_hash("testpassword123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    target_user = User(
        email="target_emp@example.com",
        full_name="Target Emp",
        password_hash=get_password_hash("testpassword123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    test_db.add_all([employee_user, target_user])
    test_db.commit()
    test_db.refresh(target_user)

    # Login as employee
    login_response = test_client.post("/auth/login", json={
        "email": "emp_notadmin@example.com",
        "password": "testpassword123"
    })
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Attempt reset password as employee
    reset_response = test_client.post(f"/auth/admin/users/{target_user.id}/reset-password", headers=headers)
    assert reset_response.status_code in (401, 403)


def test_reset_password_user_not_found(test_client, test_db):
    """Test resetting password for a nonexistent user returns 404."""
    admin_user = User(
        email="admin_404@example.com",
        full_name="Admin 404",
        password_hash=get_password_hash("testpassword123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    test_db.add(admin_user)
    test_db.commit()

    login_response = test_client.post("/auth/login", json={
        "email": "admin_404@example.com",
        "password": "testpassword123"
    })
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    import uuid
    random_uuid = uuid.uuid4()
    reset_response = test_client.post(f"/auth/admin/users/{random_uuid}/reset-password", headers=headers)
    assert reset_response.status_code == 404
