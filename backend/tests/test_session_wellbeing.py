import pytest
from fastapi.testclient import TestClient
import uuid
from datetime import datetime

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


def test_create_session_wellbeing_checkin(client, test_db):
    user = models.User(
        email="wellbeing_test_1@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Wellbeing User 1",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(id=uuid.uuid4(), user_id=user.id)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    test_work_session = models.WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.utcnow(),
        ended_at=datetime.utcnow(),
    )
    test_db.add(test_work_session)
    test_db.commit()
    test_db.refresh(test_work_session)

    response = client.post(
        "/session-wellbeing/",
        headers=headers,
        json={
            "work_session_id": str(test_work_session.id),
            "overall_wellbeing": 3,
            "mental_fatigue": 2,
            "workload_manageability": 3,
            "perceived_focus": 3,
            "break_recovery": 3,
            "stress_factors": ["Heavy workload", "Too many interruptions"],
            "notes": "This is a test note.",
        },
    )

    assert response.status_code in (200, 201), f"Expected 200 or 201, got {response.status_code}. Response: {response.json()}"

    data = response.json()
    assert data["work_session_id"] == str(test_work_session.id)
    assert data["overall_wellbeing"] == 3
    assert data["mental_fatigue"] == 2
    assert data["workload_manageability"] == 3
    assert data["perceived_focus"] == 3
    assert data["break_recovery"] == 3
    assert data["stress_factors"] == ["Heavy workload", "Too many interruptions"]
    assert data["notes"] == "This is a test note."


def test_get_session_wellbeing_checkin(client, test_db):
    user = models.User(
        email="wellbeing_test_2@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Wellbeing User 2",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(id=uuid.uuid4(), user_id=user.id)
    test_db.add(profile)
    test_db.commit()

    token = create_access_token(data={"sub": user.email})
    headers = {"Authorization": f"Bearer {token}"}

    test_work_session = models.WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.utcnow(),
        ended_at=datetime.utcnow(),
    )
    test_db.add(test_work_session)
    test_db.commit()
    test_db.refresh(test_work_session)

    checkin = models.SessionWellbeingCheckin(
        id=uuid.uuid4(),
        user_id=user.id,
        work_session_id=test_work_session.id,
        overall_wellbeing=4,
        mental_fatigue=2,
        workload_manageability=4,
        perceived_focus=4,
        break_recovery=4,
        stress_factors=["Lack of focus"],
        notes="Another test note.",
    )
    test_db.add(checkin)
    test_db.commit()
    test_db.refresh(checkin)

    response = client.get(f"/session-wellbeing/?work_session_id={test_work_session.id}", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 1
    assert data[0]["id"] == str(checkin.id)
    assert data[0]["overall_wellbeing"] == 4
    assert data[0]["notes"] == "Another test note."
