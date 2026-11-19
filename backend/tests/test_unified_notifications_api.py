"""
Unit tests for Unified Notification Center API endpoints (marking all read, fetching, and marking individual notifications).
"""
import pytest
from httpx import AsyncClient
from fastapi import status
from sqlalchemy.orm import Session
from app.models import User, Notification
from app.services.notification_dispatch_service import NotificationDispatchService

@pytest.mark.asyncio
async def test_notification_api_endpoints(client: AsyncClient, test_user: User, db: Session):
    """Test fetching notifications, marking single read, and marking all read."""
    # Login as test_user
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Dispatch test notifications using test db session
    NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=test_user.id,
        title="Notification 1",
        message="First message",
        notification_type="WORK_REMINDER",
        priority="STANDARD"
    )
    NotificationDispatchService.dispatch(
        db=db,
        recipient_user_id=test_user.id,
        title="Notification 2",
        message="Second message",
        notification_type="SYSTEM_ALERT",
        priority="STANDARD"
    )
    db.commit()

    # GET /notifications
    res = await client.get("/notifications", headers=headers)
    assert res.status_code == status.HTTP_200_OK
    data = res.json()
    assert data["unread_count"] >= 2
    assert len(data["notifications"]) >= 2
    notif_id = data["notifications"][0]["id"]

    # PATCH /notifications/{id}/read
    read_res = await client.patch(f"/notifications/{notif_id}/read", headers=headers)
    assert read_res.status_code == status.HTTP_200_OK
    assert read_res.json()["is_read"] == True

    # POST /notifications/read-all
    read_all_res = await client.post("/notifications/read-all", headers=headers)
    assert read_all_res.status_code == status.HTTP_200_OK
    assert read_all_res.json()["marked_count"] >= 1

    # Verify unread_count is now 0
    res_after = await client.get("/notifications", headers=headers)
    assert res_after.status_code == status.HTTP_200_OK
    assert res_after.json()["unread_count"] == 0
