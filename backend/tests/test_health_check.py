"""
Unit tests for liveness and readiness health check endpoints.
"""
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.mark.asyncio
async def test_liveness_endpoint(client: AsyncClient):
    response = await client.get("/health/live")
    assert response.status_code == status.HTTP_200_OK
    assert response.json()["status"] == "alive"

@pytest.mark.asyncio
async def test_readiness_endpoint(client: AsyncClient):
    response = await client.get("/health/ready")
    assert response.status_code in (status.HTTP_200_OK, status.HTTP_503_SERVICE_UNAVAILABLE)
    data = response.json()
    assert "status" in data

@pytest.mark.asyncio
async def test_legacy_health_endpoint(client: AsyncClient):
    response = await client.get("/health")
    assert response.status_code in (status.HTTP_200_OK, status.HTTP_503_SERVICE_UNAVAILABLE)
    data = response.json()
    assert "database" in data
