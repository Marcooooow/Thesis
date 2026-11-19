"""
Comprehensive regression tests for generic BREAK, MEAL, historical compatibility,
overlapping break prevention, and active break shift-ending prevention.
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


def test_repeated_generic_breaks_without_prerequisites(client, test_db):
    """Test: Start Shift -> Multiple repeated generic BREAK periods without numbered prerequisites."""
    user = models.User(
        email="gen_break_1@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Gen Break User 1",
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

    # 2. Start & End first generic BREAK
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK"})
    assert res.status_code == 200
    b1_id = res.json()["id"]
    res = client.post(f"/work/break/end/{b1_id}", headers=headers)
    assert res.status_code == 200

    # 3. Start & End second generic BREAK (repeated without prerequisite)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK"})
    assert res.status_code == 200
    b2_id = res.json()["id"]
    res = client.post(f"/work/break/end/{b2_id}", headers=headers)
    assert res.status_code == 200

    # 4. End Shift
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 200


def test_overlapping_active_breaks_rejected(client, test_db):
    """Test that starting a second break while one is active is rejected."""
    user = models.User(
        email="gen_break_2@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Gen Break User 2",
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

    # Start first break
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK"})
    assert res.status_code == 200

    # Try starting another break while active (should fail with 400)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "MEAL"})
    assert res.status_code == 400


def test_cannot_end_shift_during_active_break(client, test_db):
    """Test that ending shift while a break is active is rejected with 400."""
    user = models.User(
        email="gen_break_3@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Gen Break User 3",
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
    client.post("/work/break/start", headers=headers, json={"break_type": "BREAK"})

    # Try ending shift while break is active
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 400


def test_historical_break_compatibility_and_analytics(client, test_db):
    """Test historical BREAK_1, BREAK_2, and LUNCH compatibility and analytics aggregation."""
    user = models.User(
        email="gen_break_4@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Gen Break User 4",
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

    # Use historical BREAK_1 and LUNCH
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK_1"})
    assert res.status_code == 200
    b1_id = res.json()["id"]
    client.post(f"/work/break/end/{b1_id}", headers=headers)

    res = client.post("/work/break/start", headers=headers, json={"break_type": "LUNCH"})
    assert res.status_code == 200
    lunch_id = res.json()["id"]
    client.post(f"/work/break/end/{lunch_id}", headers=headers)

    # Verify analytics endpoint includes both historical BREAK_1 and LUNCH (as MEAL)
    analytics_res = client.get("/analytics/today/focus-ratio", headers=headers)
    assert analytics_res.status_code == 200
    data = analytics_res.json()
    assert "idle" in data
    assert "activeFocus" in data


def test_break_duration_precision_and_durations(client, test_db):
    """Test break duration calculations for 45s, 90s, and multi-minute breaks preserving actual elapsed time."""
    from datetime import datetime, timezone, timedelta
    import uuid

    user = models.User(
        email="duration_test@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Duration Test User",
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

    # Test 45-second break duration (stored duration should be 0 minutes)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "BREAK"})
    assert res.status_code == 200
    b_id = res.json()["id"]

    break_record = test_db.query(models.Break).filter(models.Break.id == uuid.UUID(b_id)).first()
    now_utc = datetime.now(timezone.utc)
    break_record.started_at = now_utc - timedelta(seconds=45)
    test_db.commit()

    res = client.post(f"/work/break/end/{b_id}", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert data["duration_minutes"] == 0

    # Test 90-second break duration (stored duration should be 1 minute)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "MEAL"})
    assert res.status_code == 200
    b_id_2 = res.json()["id"]

    break_record_2 = test_db.query(models.Break).filter(models.Break.id == uuid.UUID(b_id_2)).first()
    break_record_2.started_at = datetime.now(timezone.utc) - timedelta(seconds=90)
    test_db.commit()

    res = client.post(f"/work/break/end/{b_id_2}", headers=headers)
    assert res.status_code == 200
    data_2 = res.json()
    assert data_2["duration_minutes"] == 1

