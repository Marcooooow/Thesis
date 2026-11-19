"""
Tests for token refresh endpoint (/auth/refresh).
Covers:
1. Successful access token refresh with valid refresh token.
2. Expired or invalid refresh token returns 401 Unauthorized (not 500).
"""

import pytest
from datetime import datetime, timedelta, timezone
from app.models import User, Profile
from app.auth.security import get_password_hash, create_refresh_token, hash_refresh_token


@pytest.mark.asyncio
async def test_auth_refresh_success(client, test_db):
    """Test successful token refresh with a valid refresh token."""
    user = User(
        email="refresh_test@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Refresh Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()

    profile = Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    refresh_token = create_refresh_token(data={"sub": user.email}, expires_delta=timedelta(days=7))
    user.refresh_token_hash = hash_refresh_token(refresh_token)
    user.refresh_token_expires_at = datetime.now(timezone.utc) + timedelta(days=7)
    test_db.commit()

    response = await client.post("/auth/refresh", json={"challenge_token": refresh_token})
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["requires_2fa"] is False


@pytest.mark.asyncio
async def test_auth_refresh_invalid_token(client):
    """Test that invalid refresh token returns 401 Unauthorized (not 500)."""
    response = await client.post("/auth/refresh", json={"challenge_token": "invalid_token_string"})
    assert response.status_code == 401
    data = response.json()
    assert "detail" in data
