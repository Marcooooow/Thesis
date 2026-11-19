import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

@pytest.fixture
def session_user_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"session_test_{unique_id}@test.com"
    user = models.User(
        email=email,
        full_name="Session Test User",
        role="EMPLOYEE",
        account_type="solo",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass"),
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    # Create completed work sessions
    now = datetime.now(timezone.utc)
    for i in range(5):
        ws = models.WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(days=i+1, hours=2),
            ended_at=now - timedelta(days=i+1)
        )
        test_db.add(ws)
        test_db.commit()
        test_db.refresh(ws)

        # Add a break
        brk = models.Break(
            work_session_id=ws.id,
            break_type="LUNCH",
            started_at=ws.started_at + timedelta(minutes=30),
            ended_at=ws.started_at + timedelta(minutes=60)
        )
        test_db.add(brk)

        # Add a task
        tsk = models.Task(
            profile_id=profile.id,
            work_session_id=ws.id,
            title=f"Task {i}",
            status="DONE",
            started_at=ws.started_at,
            ended_at=ws.ended_at,
            actual_minutes=60
        )
        test_db.add(tsk)
        test_db.commit()

    return create_access_token(data={"sub": user.email})

def test_sessions_history_pagination_and_filtering(session_user_token):
    # Test default history fetch
    response = client.get("/work/sessions/history", headers={"Authorization": f"Bearer {session_user_token}"})
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 5
    # Verify eager loading of breaks and tasks
    assert len(data[0]["breaks"]) == 1
    assert len(data[0]["tasks"]) == 1

    # Test limit and offset
    response_limit = client.get(
        "/work/sessions/history",
        headers={"Authorization": f"Bearer {session_user_token}"},
        params={"limit": 2, "offset": 1}
    )
    assert response_limit.status_code == 200
    limited_data = response_limit.json()
    assert len(limited_data) == 2

    # Test status filter = completed
    response_status = client.get(
        "/work/sessions/history",
        headers={"Authorization": f"Bearer {session_user_token}"},
        params={"status": "completed"}
    )
    assert response_status.status_code == 200
    assert len(response_status.json()) == 5
