"""Tests for overnight shift schedule support in profile update."""
import pytest
from httpx import AsyncClient
from fastapi import status
from app.models import User


@pytest.mark.asyncio
async def test_normal_daytime_schedule_08_to_17(client: AsyncClient, test_user: User):
    """8:00 AM → 5:00 PM (normal same-day schedule) should succeed."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "08:00",
            "shift_end_time": "17:00",
            "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
        }
    )
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["shift_start_time"] == "08:00"
    assert data["shift_end_time"] == "17:00"


@pytest.mark.asyncio
async def test_afternoon_schedule_13_to_22(client: AsyncClient, test_user: User):
    """1:00 PM → 10:00 PM (normal same-day schedule) should succeed."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "13:00",
            "shift_end_time": "22:00",
            "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
        }
    )
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["shift_start_time"] == "13:00"
    assert data["shift_end_time"] == "22:00"


@pytest.mark.asyncio
async def test_overnight_schedule_22_to_06(client: AsyncClient, test_user: User):
    """10:00 PM → 6:00 AM (overnight schedule) should succeed."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "22:00",
            "shift_end_time": "06:00",
            "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
        }
    )
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["shift_start_time"] == "22:00"
    assert data["shift_end_time"] == "06:00"


@pytest.mark.asyncio
async def test_overnight_schedule_23_to_07(client: AsyncClient, test_user: User):
    """11:00 PM → 7:00 AM (overnight schedule) should succeed."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "23:00",
            "shift_end_time": "07:00",
            "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
        }
    )
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["shift_start_time"] == "23:00"
    assert data["shift_end_time"] == "07:00"


@pytest.mark.asyncio
async def test_equal_times_22_to_22_rejected(client: AsyncClient, test_user: User):
    """10:00 PM → 10:00 PM (equal start and end) should be rejected with 422."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    client.headers.update({"Authorization": f"Bearer {token}"})

    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "22:00",
            "shift_end_time": "22:00",
            "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"]
        }
    )
    assert response.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
    data = response.json()
    error_msg = str(data["detail"]).lower()
    assert "equal" in error_msg or "cannot" in error_msg


@pytest.mark.asyncio
async def test_unauthenticated_rejected(client: AsyncClient):
    """Unauthenticated requests should be rejected."""
    response = await client.patch(
        "/profile/me",
        json={
            "shift_start_time": "08:00",
            "shift_end_time": "17:00"
        }
    )
    assert response.status_code == status.HTTP_401_UNAUTHORIZED
