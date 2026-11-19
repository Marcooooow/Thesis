import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app.database import SessionLocal
from app import models
import uuid

client = TestClient(app)

@pytest.fixture
def user_token(test_db):
    unique_id = str(uuid.uuid4())[:8]
    email = f"user_{unique_id}@test.com"
    user = models.User(
        email=email,
        full_name="Test User",
        role="EMPLOYEE",
        account_type="solo",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass"),
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    return create_access_token(data={"sub": user.email})

def test_personal_weekly_work_hours(user_token):
    response = client.get(
        "/analytics/weekly/work-hours",
        headers={"Authorization": f"Bearer {user_token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 7
    for item in data:
        assert "day" in item
        assert "actualHours" in item
        assert "targetHours" in item

def test_personal_focus_rate(user_token):
    response = client.get(
        "/analytics/focus-rate",
        headers={"Authorization": f"Bearer {user_token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, dict)
    assert "rate" in data

def test_personal_today_summary(user_token):
    response = client.get(
        "/analytics/today/summary",
        headers={"Authorization": f"Bearer {user_token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, dict)
    assert "shiftDurationSeconds" in data
    assert "workedSeconds" in data
    assert "focusedSeconds" in data
    assert "breakSeconds" in data
    assert "untrackedSeconds" in data
    assert "focusRate" in data
    assert "workedHours" in data
    assert "targetDailyHours" in data
    assert "targetProgress" in data
    assert "isSessionActive" in data

def test_wellbeing_summary(user_token):
    response = client.get(
        "/analytics/wellbeing-summary?start_date=2026-10-01&end_date=2026-10-31",
        headers={"Authorization": f"Bearer {user_token}"},
    )
    print(f"WELLBEING SUMMARY STATUS: {response.status_code}")
    print(f"WELLBEING SUMMARY BODY: {response.json()}")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, dict)
    assert "checkinCount" in data
    assert "avgOverallWellbeing" in data
    assert "avgMentalFatigue" in data
    assert "avgWorkloadManageability" in data
    assert "avgPerceivedFocus" in data
    assert "avgBreakRecovery" in data

def test_export_pdf_employee_report(user_token):
    response = client.get(
        "/reports/export-pdf?report_type=employee",
        headers={"Authorization": f"Bearer {user_token}"},
    )
    print(f"EMPLOYEE PDF EXPORT STATUS: {response.status_code}")
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/pdf"
    # Verify PDF content length
    assert len(response.content) > 0
