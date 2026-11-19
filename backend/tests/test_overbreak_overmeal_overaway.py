"""
Tests for Overbreak, Overmeal, and Overaway Management workflows.
"""
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db
from app import models
from app.auth.security import get_password_hash, create_access_token


@pytest.fixture
def client(test_db):
    def override_get_db():
        try:
            yield test_db
        finally:
            pass
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_overbreak_extension_and_return(client, test_db):
    """Test Overbreak detection, recording an extension with a reason, and returning to work."""
    user = models.User(
        email="overbreak_user@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Overbreak User",
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

    # 2. Start Short Break / Break
    res = client.post("/work/break/start", headers=headers, json={"break_type": "SHORT_BREAK"})
    assert res.status_code == 200
    break_id = res.json()["id"]

    # 3. Record Extension (Overbreak extension with reason)
    res = client.post(
        f"/work/break/extend/{break_id}",
        headers=headers,
        json={"extension_minutes": 10, "reason": "Wrapping up urgent stretch routine"}
    )
    assert res.status_code == 200
    assert res.json()["duration_minutes"] >= 0

    # 4. Return to Work / End Break
    res = client.post(f"/work/break/end/{break_id}", headers=headers)
    assert res.status_code == 200
    assert res.json()["ended_at"] is not None

    # 5. End Shift
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 200


def test_overmeal_and_overaway_handling(client, test_db):
    """Test Overmeal and Overaway workflows with 'Still Away' / extension options."""
    user = models.User(
        email="overmeal_user@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Overmeal User",
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

    # 1. Start Meal break (Overmeal)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "MEAL"})
    assert res.status_code == 200
    meal_id = res.json()["id"]

    # Extend meal
    res = client.post(
        f"/work/break/extend/{meal_id}",
        headers=headers,
        json={"extension_minutes": 15, "reason": "Line at cafeteria"}
    )
    assert res.status_code == 200

    # End meal
    res = client.post(f"/work/break/end/{meal_id}", headers=headers)
    assert res.status_code == 200

    # 2. Start Away period (OTHER / Meeting)
    res = client.post("/work/break/start", headers=headers, json={"break_type": "OTHER", "notes": "Client meeting running late"})
    assert res.status_code == 200
    away_id = res.json()["id"]

    # Still away / extend away period
    res = client.post(
        f"/work/break/extend/{away_id}",
        headers=headers,
        json={"extension_minutes": 30, "reason": "Extended Q&A session in client review"}
    )
    assert res.status_code == 200

    # Return to work
    res = client.post(f"/work/break/end/{away_id}", headers=headers)
    assert res.status_code == 200

    # End shift
    res = client.post("/work/session/end", headers=headers)
    assert res.status_code == 200
