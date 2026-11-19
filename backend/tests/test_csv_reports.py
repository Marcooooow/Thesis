import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
import zipfile
import io
from datetime import date, datetime, timezone, timedelta

client = TestClient(app)

def test_csv_report_export_manager(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    mgr_user = models.User(
        email=f"mgr_{unique_id}@test.com", full_name="Manager Test", role="MANAGER",
        account_type="team", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(mgr_user)
    test_db.commit()
    test_db.refresh(mgr_user)

    mgr_profile = models.Profile(user_id=mgr_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(mgr_profile)
    test_db.commit()

    team = models.Team(name=f"Team {unique_id}", manager_user_id=mgr_user.id, organization_id=org.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    for i in range(3):
        emp_user = models.User(
            email=f"emp_{i}_{unique_id}@test.com", full_name=f"Employee {i}", role="EMPLOYEE",
            account_type="team", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(emp_user)
        test_db.commit()
        test_db.refresh(emp_user)

        emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False)
        test_db.add(emp_profile)
        test_db.commit()
        test_db.refresh(emp_profile)

        membership = models.TeamMembership(team_id=team.id, profile_id=emp_profile.id, role="EMPLOYEE")
        test_db.add(membership)
        test_db.commit()

    mgr_token = create_access_token(data={"sub": mgr_user.email})

    response = client.get(
        "/reports/export-csv",
        headers={"Authorization": f"Bearer {mgr_token}"},
        params={"team_id": str(team.id)}
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"
    assert "attachment; filename=" in response.headers["content-disposition"]

    # Verify ZIP contents
    with zipfile.ZipFile(io.BytesIO(response.content)) as z:
        namelist = z.namelist()
        assert "executive_summary.csv" in namelist
        assert "productivity.csv" in namelist
        assert "work_sessions.csv" in namelist
        assert "break_analysis.csv" in namelist
        assert "wellbeing.csv" in namelist
        assert "recommendations.csv" in namelist


def test_csv_report_export_employee(test_db):
    unique_id = str(uuid.uuid4())[:8]
    emp_user = models.User(
        email=f"emp_{unique_id}@test.com", full_name="Employee Solo", role="EMPLOYEE",
        account_type="solo", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)

    emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(emp_profile)
    test_db.commit()

    emp_token = create_access_token(data={"sub": emp_user.email})

    response = client.get(
        "/reports/export-csv",
        headers={"Authorization": f"Bearer {emp_token}"}
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"
    with zipfile.ZipFile(io.BytesIO(response.content)) as z:
        assert "executive_summary.csv" in z.namelist()
