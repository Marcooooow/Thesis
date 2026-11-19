"""Backend concurrency and integration tests for IntelliBreak."""
import pytest
import asyncio
from httpx import AsyncClient
from fastapi import status
from app.models import User, Profile, WorkSession, Break, SessionWellbeingCheckin, RecommendationFeedback, EmployeeSchedule
from app.auth.security import get_password_hash
import uuid
from datetime import date, datetime, timezone, timedelta


@pytest.mark.asyncio
async def test_duplicate_work_session_starts_rapid(client: AsyncClient, test_user: User):
    """Test rapid sequential/duplicate work session start requests (retry storm / duplicate network requests)."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    assert login.status_code == status.HTTP_200_OK
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # First start
    res1 = await client.post("/work/session/start", headers=headers)
    assert res1.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    session_id_1 = res1.json()["id"]

    # Rapid duplicate start (simulating retry)
    res2 = await client.post("/work/session/start", headers=headers)
    assert res2.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    session_id_2 = res2.json()["id"]

    # Backend safely closes previous session and starts new session without error
    assert session_id_1 != session_id_2


@pytest.mark.asyncio
async def test_break_sequencing_and_duplicate_prevention(client: AsyncClient, test_user: User):
    """Test break sequencing rules and duplicate break prevention."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Start work session
    sess_res = await client.post("/work/session/start", headers=headers)
    assert sess_res.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)

    # Attempt LUNCH before BREAK_1 -> should fail (sequencing rule)
    lunch_res = await client.post("/work/break/start", json={"break_type": "LUNCH"}, headers=headers)
    assert lunch_res.status_code == status.HTTP_400_BAD_REQUEST

    # Start BREAK_1
    b1_res = await client.post("/work/break/start", json={"break_type": "BREAK_1"}, headers=headers)
    assert b1_res.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    b1_id = b1_res.json()["id"]

    # Attempt duplicate start of BREAK_1 in same session -> should fail (one-per-session rule)
    dup_b1 = await client.post("/work/break/start", json={"break_type": "BREAK_1"}, headers=headers)
    assert dup_b1.status_code == status.HTTP_400_BAD_REQUEST

    # Attempt to start another break while BREAK_1 is active -> should fail
    active_b = await client.post("/work/break/start", json={"break_type": "OTHER"}, headers=headers)
    assert active_b.status_code == status.HTTP_400_BAD_REQUEST

    # End BREAK_1
    end_b1 = await client.post(f"/work/break/end/{b1_id}", headers=headers)
    assert end_b1.status_code == status.HTTP_200_OK

    # Now LUNCH can start successfully
    lunch_ok = await client.post("/work/break/start", json={"break_type": "LUNCH"}, headers=headers)
    assert lunch_ok.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)


@pytest.mark.asyncio
async def test_duplicate_wellbeing_and_feedback(client: AsyncClient, test_user: User):
    """Test duplicate wellbeing check-in submissions and recommendation feedback."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Start work session to get active work session ID
    sess_res = await client.post("/work/session/start", headers=headers)
    assert sess_res.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    session_id = sess_res.json()["id"]

    # Generate a recommendation to get a valid recommendation_id
    gen_res = await client.post("/recommend/generate", headers=headers)
    assert gen_res.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    rec_id = gen_res.json()["recommendation_id"]

    checkin_payload = {
        "work_session_id": session_id,
        "overall_wellbeing": 4,
        "mental_fatigue": 2,
        "workload_manageability": 4,
        "perceived_focus": 4,
        "break_recovery": 4
    }
    # Multiple check-in submissions (upsert / update)
    res1 = await client.post("/session-wellbeing/", json=checkin_payload, headers=headers)
    assert res1.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)
    res2 = await client.post("/session-wellbeing/", json=checkin_payload, headers=headers)
    assert res2.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)

    # Recommendation feedback submission
    fb_payload = {
        "recommendation_id": rec_id,
        "user_action": "accepted"
    }
    fb1 = await client.post("/recommend/feedback", json=fb_payload, headers=headers)
    assert fb1.status_code in (status.HTTP_200_OK, status.HTTP_201_CREATED)


@pytest.mark.asyncio
async def test_schedule_and_attendance_synchronization(client: AsyncClient, test_user: User):
    """Test schedule updates and profile/attendance synchronization."""
    login = await client.post("/auth/login", json={"email": test_user.email, "password": "testpassword123"})
    token = login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    patch_res = await client.patch("/profile/me", json={"shift_start_time": "09:00", "shift_end_time": "18:00"}, headers=headers)
    assert patch_res.status_code == status.HTTP_200_OK

    att_res = await client.get("/attendance/my", headers=headers)
    assert att_res.status_code == status.HTTP_200_OK
    data = att_res.json()
    assert "schedule" in data
    assert data["schedule"]["shift_start"] in ("09:00:00", "09:00")


