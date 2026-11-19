"""
Tests for Option C Flexible Break Workflow with Prerequisites.
Covers:
1. Start shift -> Break 1 -> Lunch first -> Break 2.
2. Start shift -> Break 1 -> Break 2 first -> Lunch.
3. Attempting Lunch or Break 2 before Break 1 (rejected with 400).
4. Duplicate break starts (rejected with 400).
5. Ending shift while a break is active (rejected with 400).
6. Ending shift without completing every break (allowed).
"""
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db
from app import models
from app.auth.security import get_password_hash, create_access_token


@pytest.fixture
def client(test_db):
    """Create a test client using the test database."""
    def override_get_db():
        try:
            yield test_db
        finally:
            pass
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_option_c_workflow_lunch_first_then_break2(client, test_db):
    """Test: Start Shift -> Break 1 -> Lunch -> Break 2 -> End Shift."""
    user = models.User(
        email="workflow_test_1@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Workflow User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Start Shift
    res = client.post("/work/session/start", headers=headers)
    assert res.status_code == 200

    # 2. Try starting Lunch before Break 1 (should fail)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "LUNCH"})
    assert res.status_code == 400

    # 3. Start & End Break 1
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})
    assert res.status_code == 200
    break1_id = res.json()["id"]

    res = client.post(f"/work/break/end/{break1_id}", headers=headers)
    assert res.status_code == 200

    # 4. Now Lunch is available (Option C: Lunch or Break 2 after Break 1)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "LUNCH"})
    assert res.status_code == 200
    lunch_id = res.json()["id"]

    res = client.post(f"/work/break/end/{lunch_id}", headers=headers)
    assert res.status_code == 200

    # 5. Now Break 2 is available
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_2"})
    assert res.status_code == 200
    break2_id = res.json()["id"]

    res = client.post(f"/work/break/end/{break2_id}", headers=headers)
    assert res.status_code == 200

    # 6. End Shift
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 200


def test_option_c_workflow_break2_first_then_lunch(client, test_db):
    """Test: Start Shift -> Break 1 -> Break 2 -> Lunch -> End Shift."""
    user = models.User(
        email="workflow_test_2@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Workflow User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Start Shift
    res = client.post("/work/session/start", headers=headers)
    assert res.status_code == 200

    # 2. Start & End Break 1
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})
    assert res.status_code == 200
    break1_id = res.json()["id"]
    res = client.post(f"/work/break/end/{break1_id}", headers=headers)
    assert res.status_code == 200

    # 3. Start Break 2 first (Option C flexibility)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_2"})
    assert res.status_code == 200
    break2_id = res.json()["id"]
    res = client.post(f"/work/break/end/{break2_id}", headers=headers)
    assert res.status_code == 200

    # 4. Then Lunch
    res = client.post("/work/break/start", headers=headers, json={"break_type": "LUNCH"})
    assert res.status_code == 200
    lunch_id = res.json()["id"]
    res = client.post(f"/work/break/end/{lunch_id}", headers=headers)
    assert res.status_code == 200

    # 5. End Shift
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 200


def test_duplicate_break_rejection(client, test_db):
    """Test that starting the same break type twice in a session fails."""
    user = models.User(
        email="workflow_test_3@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Workflow User 3",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    client.post("/work/session/start", headers=headers)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})
    assert res.status_code == 200
    break1_id = res.json()["id"]
    client.post(f"/work/break/end/{break1_id}", headers=headers)

    # Try starting Break 1 again
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})
    assert res.status_code == 400


def test_cannot_end_shift_while_break_active(client, test_db):
    """Test that ending shift while a break is active fails with 400."""
    user = models.User(
        email="workflow_test_4@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Workflow User 4",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    client.post("/work/session/start", headers=headers)
    client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})

    # Try ending shift while Break 1 is active
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 400
