import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db
from app import models
from app.auth.security import get_password_hash, create_access_token


@pytest.fixture
def client(test_db):
    """Create a test client using the test database."""
    # Override the get_db dependency to use the test database
    def override_get_db():
        try:
            yield test_db
        finally:
            pass
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_heartbeat_endpoint(client, test_db):
    """Test the heartbeat endpoint."""
    # Create a test user
    user = models.User(
        email="testuser@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)
    access_token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {access_token}"}

    response = client.post("/presence/heartbeat", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == str(user.id)
    assert data["is_online"] == True
    assert "last_heartbeat" in data
    assert data["updated_at"] is not None


def test_get_own_presence_status(client, test_db):
    """Test getting own presence status."""
    # Create a test user
    user = models.User(
        email="testuser2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)
    access_token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {access_token}"}

    # First, send a heartbeat to ensure we have a presence record
    client.post("/presence/heartbeat", headers=headers)

    response = client.get(f"/presence/status/{user.id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == str(user.id)
    assert data["is_online"] == True
    assert data["last_heartbeat"] is not None
    assert data["updated_at"] is not None


def test_get_presence_status_offline_after_expiry(client, test_db):
    """Test that presence status becomes offline after heartbeat expiry."""
    # Create a test user with no heartbeat
    user = models.User(
        email="testuser3@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User 3",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)
    access_token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {access_token}"}

    # Since the user has no presence record, the endpoint should return offline.
    response = client.get(f"/presence/status/{user.id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == str(user.id)
    assert data["is_online"] == False
    assert data["last_heartbeat"] is None
    assert data["updated_at"] is None


def test_get_other_user_presence_status_as_admin(client, test_db):
    """Test that an admin can get the presence status of another user."""
    # Create a normal user
    normal_user = models.User(
        email="normaluser@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Normal User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    # Create an admin user
    admin_user = models.User(
        email="adminuser@example.com",
        password_hash=get_password_hash("adminpassword123"),
        full_name="Admin User",
        account_type="solo",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(normal_user)
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(normal_user)
    test_db.refresh(admin_user)

    admin_access_token = create_access_token(data={"sub": admin_user.email})
    admin_headers = {"Authorization": f"Bearer {admin_access_token}"}

    # Now, as admin, get the presence status of the normal user (who has no heartbeat)
    response = client.get(f"/presence/status/{normal_user.id}", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == str(normal_user.id)
    assert data["is_online"] == False
    assert data["last_heartbeat"] is None
    assert data["updated_at"] is None


def test_get_multiple_users_presence_status(client, test_db):
    """Test getting presence status for multiple users."""
    # Create two test users
    user1 = models.User(
        email="user1@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    user2 = models.User(
        email="user2@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user1)
    test_db.add(user2)
    test_db.commit()
    test_db.refresh(user1)
    test_db.refresh(user2)

    access_token = create_access_token(data={"sub": user1.email})
    headers = {"Authorization": f"Bearer {access_token}"}

    # Get presence status for both users (both have no heartbeat, so both should be offline)
    response = client.get(
        f"/presence/status?user_ids={user1.id}&user_ids={user2.id}",
        headers=headers
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    # Check that both are offline
    for user_data in data:
        assert user_data["is_online"] is False
        assert user_data["last_heartbeat"] is None
        assert user_data["updated_at"] is None


def test_clear_presence_endpoint(client, test_db):
    """Test the clear presence endpoint."""
    # Create a test user
    user = models.User(
        email="clearuser@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Clear User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)
    access_token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {access_token}"}

    # First, create a presence record by sending a heartbeat
    response = client.post("/presence/heartbeat", headers=headers)
    assert response.status_code == 200

    # Now, clear the presence
    response = client.delete(f"/presence/clear/{user.id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["user_id"] == str(user.id)
    assert data["is_online"] == False
    assert data["updated_at"] is not None

    # Verify that the user is now offline
    response = client.get(f"/presence/status/{user.id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["is_online"] == False