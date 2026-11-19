"""Focused settings backend tests."""

from fastapi.testclient import TestClient


def get_auth_headers(client: TestClient, email: str, password: str):
    """Get authentication headers for a user."""
    login_data = {"email": email, "password": password}
    response = client.post("/auth/login", json=login_data)
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_get_existing(test_client, test_db, test_user):
    from app.models import User, UserSettings
    # test_user fixture already created a user
    test_db.add(UserSettings(user_id=test_user.id))
    test_db.commit()
    auth_headers = get_auth_headers(test_client, test_user.email, "testpassword123")
    resp = test_client.get("/settings", headers=auth_headers)
    assert resp.status_code == 200


def test_get_init_defaults(test_client, test_db, test_user):
    from app.models import User, UserSettings
    # test_user fixture already created a user with email "testuser@example.com"
    # Remove any existing settings for this user
    test_db.query(UserSettings).filter(UserSettings.user_id == test_user.id).delete()
    test_db.commit()
    auth_headers = get_auth_headers(test_client, test_user.email, "testpassword123")
    resp = test_client.get("/settings", headers=auth_headers)
    assert resp.status_code == 200
    settings = test_db.query(UserSettings).filter(UserSettings.user_id == test_user.id).first()
    assert settings is not None