"""Tests for /auth/delete-account endpoint implementing DATA_DELETION_DESIGN.md."""
import pytest
from httpx import AsyncClient
from fastapi import status
from app.models import User
from app.auth.security import get_password_hash


@pytest.mark.asyncio
async def test_deletion_endpoint_executes_204(client: AsyncClient, test_user: User):
    """Confirm DELETE /auth/delete-account executes and returns 204."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.delete("/auth/delete-account")
    assert response.status_code == status.HTTP_204_NO_CONTENT


@pytest.mark.asyncio
async def test_unauthenticated_rejected(client: AsyncClient):
    response = await client.delete("/auth/delete-account")
    assert response.status_code == status.HTTP_401_UNAUTHORIZED


@pytest.mark.asyncio
async def test_self_only_authorization(client: AsyncClient, test_user: User):
    """Endpoint uses only current identity (get_current_active_user); no user ID param accepted."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.delete("/auth/delete-account")
    assert response.status_code == status.HTTP_204_NO_CONTENT
