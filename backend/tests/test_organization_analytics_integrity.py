import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

def test_organization_analytics_edge_cases_and_integrity(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Integrity Org {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_int_{unique_id}@test.com", full_name="Integrity Admin", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)
    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    # 1. Test Empty Organization Handling (No WLB surveys, no wellbeing checkins, no work sessions, no breaks)
    res_preview = client.get("/analytics/admin/reports/preview", headers=headers, params={"period": "this_week"})
    assert res_preview.status_code == 200
    data = res_preview.json()

    # Verify data quality indicator is insufficient_data
    assert data["data_quality_indicator"] == "insufficient_data"

    # Verify Executive Summary fields are zero/null safe without throwing errors
    exec_sum = data["executive_summary"]
    assert exec_sum["total_active_employees"] == 0
    assert exec_sum["total_work_hours"] == 0.0
    assert exec_sum["focus_rate"] == 0.0

    # Verify Organizational Wellbeing fields are present and safe
    wb = data["organizational_wellbeing"]
    assert wb["checkin_count"] == 0
    assert wb["overall_wellbeing"] == 0.0
    assert "risk_distribution" in wb

    # Verify Work-Life Balance fields are safe
    wlb = data["work_life_balance"]
    assert wlb["survey_respondents"] == 0
    assert wlb["avg_wlb_score"] == 0.0

    # Verify Recommendation Effectiveness
    rec = data["recommendation_effectiveness"]
    assert rec["generated_count"] == 0
    assert rec["acceptance_rate"] == 0.0

    # Verify Organizational Insights handles zero data correctly
    insights = data["organizational_insights"]
    assert insights["total_insights"] > 0
    assert insights["data_quality_indicator"] == "insufficient_data"

    # 2. Test Tenant Isolation and N >= 3 Team Privacy Suppression
    team = models.Team(name="Small Team", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    # Add 2 employees (N < 3 -> should be suppressed)
    for i in range(2):
        emp = models.User(
            email=f"emp_small_{i}_{unique_id}@test.com", full_name=f"Emp Small {i}", role="EMPLOYEE",
            account_type="organization", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(emp)
        test_db.commit()
        test_db.refresh(emp)
        prof = models.Profile(user_id=emp.id, target_daily_hours=8, is_test_data=False)
        test_db.add(prof)
        test_db.commit()
        test_db.refresh(prof)
        test_db.add(models.OrganizationMembership(user_id=emp.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
        test_db.add(models.TeamMembership(team_id=team.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

    res_preview_suppressed = client.get("/analytics/admin/reports/preview", headers=headers, params={"period": "this_week"})
    assert res_preview_suppressed.status_code == 200
    supp_data = res_preview_suppressed.json()
    teams_list = supp_data["team_comparison"]
    assert len(teams_list) == 1
    assert teams_list[0]["privacy_suppressed"] is True
    assert teams_list[0]["productivity"]["total_work_hours"] is None
