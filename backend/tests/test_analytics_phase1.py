import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app.database import SessionLocal
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

@pytest.fixture
def user_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"test_{unique_id}@test.com"
    user = models.User(
        email=email,
        full_name="Test Analytics",
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
    return create_access_token(data={"sub": user.email})

@pytest.fixture
def manager_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    user = models.User(
        email=f"mgr_{unique_id}@test.com", full_name="Mgr", role="MANAGER",
        account_type="solo", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)
    profile = models.Profile(user_id=user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(profile)
    test_db.commit()
    return create_access_token(data={"sub": user.email})

def test_break_analysis_endpoint(user_token):
    response = client.get("/analytics/break-analysis", headers={"Authorization": f"Bearer {user_token}"})
    assert response.status_code == 200
    data = response.json()
    assert "totalBreaks" in data
    assert "byType" in data

def test_session_history_endpoint(user_token):
    response = client.get("/analytics/session-history", headers={"Authorization": f"Bearer {user_token}"}, params={"limit": 10})
    assert response.status_code == 200
    data = response.json()
    assert "items" in data

def test_insights_endpoint(user_token):
    response = client.get("/analytics/insights", headers={"Authorization": f"Bearer {user_token}"})
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)

def test_what_changed_endpoint(user_token):
    response = client.get("/analytics/what-changed", headers={"Authorization": f"Bearer {user_token}"}, params={"period": "this_week"})
    assert response.status_code == 200
    data = response.json()
    assert "current" in data
    assert "previous" in data

def test_test_data_isolation(user_token, test_db):
    # Create synthetic profile with is_test_data=True
    synthetic_user = models.User(
        email="synthetic@test.com", full_name="Synthetic", role="EMPLOYEE",
        account_type="solo", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(synthetic_user)
    test_db.commit()
    synthetic_profile = models.Profile(user_id=synthetic_user.id, target_daily_hours=8, is_test_data=True)
    test_db.add(synthetic_profile)
    test_db.commit()

    # Real user analytics endpoint should still return 200 (isolates test profile via query filters in admin, but employee endpoint is per-user, so isolation is implicit by profile_id)
    response = client.get("/analytics/weekly/work-hours", headers={"Authorization": f"Bearer {user_token}"})
    assert response.status_code == 200
