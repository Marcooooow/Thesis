"""
Tests for /auth/admin/users endpoint.
"""
import pytest
from app.models import User, Profile
from app.auth.security import get_password_hash


def test_admin_get_users_endpoint(test_client, test_db):
    """Test that admin can successfully fetch all users, including users with and without profiles/job_roles."""
    # Create admin user
    admin_user = User(
        email="admin_test@example.com",
        full_name="Admin Test",
        password_hash=get_password_hash("testpassword123"),
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)

    # Create regular user WITH profile and job_role
    user_with_profile = User(
        email="user_prof@example.com",
        full_name="User With Profile",
        password_hash=get_password_hash("testpassword123"),
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    test_db.add(user_with_profile)
    test_db.commit()
    test_db.refresh(user_with_profile)

    profile = Profile(
        user_id=user_with_profile.id,
        job_role="Software Engineer"
    )
    test_db.add(profile)

    # Create regular user WITHOUT profile (missing profile case)
    user_without_profile = User(
        email="user_noprof@example.com",
        full_name="User Without Profile",
        password_hash=get_password_hash("testpassword123"),
        role="MANAGER",
        approval_status="PENDING",
        is_active=True,
        account_type="organization",
        organization_name="Acme Corp"
    )
    test_db.add(user_without_profile)
    test_db.commit()

    # Authenticate as admin
    login_response = test_client.post("/auth/login", json={
        "email": "admin_test@example.com",
        "password": "testpassword123"
    })
    assert login_response.status_code == 200
    token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Request /auth/admin/users
    response = test_client.get("/auth/admin/users", headers=headers)
    assert response.status_code == 200

    data = response.json()
    assert isinstance(data, dict)
    assert "users" in data
    assert "total" in data
    users = data["users"]
    assert len(users) >= 3

    # Verify user with profile has job_role
    prof_record = next((u for u in users if u["email"] == "user_prof@example.com"), None)
    assert prof_record is not None
    assert prof_record["job_role"] == "Software Engineer"
    assert prof_record["approval_status"] == "APPROVED"

    # Verify user without profile has job_role = None
    noprof_record = next((u for u in users if u["email"] == "user_noprof@example.com"), None)
    assert noprof_record is not None
    assert noprof_record["job_role"] is None
    assert noprof_record["organization_name"] == "Acme Corp"
    assert noprof_record["approval_status"] == "PENDING"

    # Test search filter
    search_response = test_client.get("/auth/admin/users?search=Without", headers=headers)
    assert search_response.status_code == 200
    search_data = search_response.json()
    assert len(search_data["users"]) == 1
    assert search_data["users"][0]["email"] == "user_noprof@example.com"

    # Test role filter
    role_response = test_client.get("/auth/admin/users?role=MANAGER", headers=headers)
    assert role_response.status_code == 200
    role_data = role_response.json()
    assert any(u["email"] == "user_noprof@example.com" for u in role_data["users"])

    # Test approval status filter
    status_response = test_client.get("/auth/admin/users?status=PENDING", headers=headers)
    assert status_response.status_code == 200
    status_data = status_response.json()
    assert any(u["email"] == "user_noprof@example.com" for u in status_data["users"])

    # Test pagination metadata and limit
    page_response = test_client.get("/auth/admin/users?page=1&limit=2", headers=headers)
    assert page_response.status_code == 200
    page_data = page_response.json()
    assert "total" in page_data
    assert "total_pages" in page_data
    assert page_data["limit"] == 2
    assert len(page_data["users"]) <= 2

