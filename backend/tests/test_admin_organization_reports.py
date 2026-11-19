import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
import zipfile
import io
from datetime import datetime, timezone, timedelta, date

client = TestClient(app)

def test_admin_organization_reports_comprehensive(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Admin Report Org {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_rpt_{unique_id}@test.com", full_name="Admin Reporter", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)
    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Team 1: 3 employees (N >= 3, not suppressed)
    team1 = models.Team(name="Report Team Alpha", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team1)
    test_db.commit()
    test_db.refresh(team1)

    now_utc = datetime.now(timezone.utc)
    for i in range(3):
        emp = models.User(
            email=f"emp_rpt_{i}_{unique_id}@test.com", full_name=f"Emp Rpt {i}", role="EMPLOYEE",
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
        test_db.add(models.TeamMembership(team_id=team1.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

        # Work Session
        sess = models.WorkSession(
            profile_id=prof.id,
            started_at=now_utc - timedelta(hours=5),
            ended_at=now_utc - timedelta(hours=1)
        )
        test_db.add(sess)
        test_db.commit()

        # WLB Survey
        survey = models.WorkLifeBalanceSurvey(
            profile_id=prof.id,
            organization_id=org.id,
            week_start_date=now_utc.date() - timedelta(days=now_utc.weekday()),
            rating_disconnect=4,
            rating_personal_time=4,
            rating_responsibilities_balance=4,
            rating_schedule_satisfaction=4,
            rating_recovery=4,
            score=80.0,
            submitted_at=now_utc
        )
        test_db.add(survey)

        # Recommendation Feedback
        fb = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=uuid.uuid4(),
            model_version="cold-start-baseline",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.9,
            context_features={},
            timestamp=now_utc,
            user_action="accepted"
        )
        test_db.add(fb)
        test_db.commit()

    # Team 2: 2 employees (N < 3, privacy suppressed)
    team2 = models.Team(name="Report Team Beta", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team2)
    test_db.commit()
    test_db.refresh(team2)

    for i in range(2):
        emp = models.User(
            email=f"emp_rpt_beta_{i}_{unique_id}@test.com", full_name=f"Emp Beta {i}", role="EMPLOYEE",
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
        test_db.add(models.TeamMembership(team_id=team2.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    # 1. Test Preview Endpoint (JSON Structure & All 9 Sections)
    res_preview = client.get("/analytics/admin/reports/preview", headers=headers, params={"period": "this_week"})
    assert res_preview.status_code == 200
    preview_data = res_preview.json()
    assert "executive_summary" in preview_data
    assert "productivity" in preview_data
    assert "work_sustainability" in preview_data
    assert "work_life_balance" in preview_data
    assert "organizational_wellbeing" in preview_data
    assert "team_comparison" in preview_data
    assert "recommendation_effectiveness" in preview_data
    assert "organizational_insights" in preview_data
    assert "metric_definitions" in preview_data

    # Verify Team Suppression (Team Beta N=2 < 3)
    teams_meta = preview_data["team_comparison"]
    beta_team = next(t for t in teams_meta if t["team_name"] == "Report Team Beta")
    assert beta_team["privacy_suppressed"] is True
    assert beta_team["productivity"]["total_work_hours"] is None

    alpha_team = next(t for t in teams_meta if t["team_name"] == "Report Team Alpha")
    assert alpha_team["privacy_suppressed"] is False
    assert alpha_team["productivity"]["total_work_hours"] > 0

    # 2. Test PDF Report Export
    res_pdf = client.get("/analytics/admin/reports/export/pdf", headers=headers, params={"period": "this_week"})
    assert res_pdf.status_code == 200
    assert res_pdf.headers["content-type"] == "application/pdf"
    assert "attachment; filename=" in res_pdf.headers["content-disposition"]
    assert res_pdf.content.startswith(b"%PDF-")

    # 3. Test XLSX Report Export
    res_xlsx = client.get("/analytics/admin/reports/export/xlsx", headers=headers, params={"period": "this_week"})
    assert res_xlsx.status_code == 200
    assert "spreadsheetml.sheet" in res_xlsx.headers["content-type"]
    assert "attachment; filename=" in res_xlsx.headers["content-disposition"]
    assert len(res_xlsx.content) > 1000

    # 4. Test CSV Report Export (ZIP Archive)
    res_csv = client.get("/analytics/admin/reports/export/csv", headers=headers, params={"period": "this_week"})
    assert res_csv.status_code == 200
    assert res_csv.headers["content-type"] == "application/zip"
    assert "attachment; filename=" in res_csv.headers["content-disposition"]

    # Inspect ZIP contents
    zip_bytes = res_csv.content
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        namelist = zf.namelist()
        assert "executive_summary.csv" in namelist
        assert "productivity.csv" in namelist
        assert "work_sustainability.csv" in namelist
        assert "work_life_balance.csv" in namelist
        assert "organizational_wellbeing.csv" in namelist
        assert "team_comparison.csv" in namelist
        assert "recommendation_effectiveness.csv" in namelist
        assert "organizational_insights.csv" in namelist
        assert "metric_definitions.csv" in namelist

        # Read team_comparison.csv content
        team_csv_text = zf.read("team_comparison.csv").decode("utf-8")
        assert "Report Team Beta" in team_csv_text
        assert "Suppressed" in team_csv_text

    # 5. Test Unauthorized Access (Employee role)
    emp_token = create_access_token(data={"sub": f"emp_rpt_0_{unique_id}@test.com"})
    emp_headers = {"Authorization": f"Bearer {emp_token}"}
    res_unauth = client.get("/analytics/admin/reports/preview", headers=emp_headers)
    assert res_unauth.status_code == 403

    # 6. Test Empty Organization Handling
    empty_org = models.Organization(name=f"Empty Rpt Org {unique_id}")
    test_db.add(empty_org)
    test_db.commit()
    empty_admin = models.User(
        email=f"empty_admin_rpt_{unique_id}@test.com", full_name="Empty Admin", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(empty_admin)
    test_db.commit()
    test_db.add(models.OrganizationMembership(user_id=empty_admin.id, organization_id=empty_org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    empty_token = create_access_token(data={"sub": empty_admin.email})
    empty_headers = {"Authorization": f"Bearer {empty_token}"}
    res_empty = client.get("/analytics/admin/reports/preview", headers=empty_headers, params={"period": "this_week"})
    assert res_empty.status_code == 200
    empty_data = res_empty.json()
    assert empty_data["data_quality_indicator"] == "insufficient_data"
    assert empty_data["executive_summary"]["total_active_employees"] == 0

    # 7. Test Admin Wellbeing Endpoints
    res_wb_today = client.get("/analytics/admin/wellbeing/today", headers=headers, params={"period": "this_week"})
    assert res_wb_today.status_code == 200
    wb_today_data = res_wb_today.json()
    assert "overallWellbeing" in wb_today_data
    assert "mentalFatigue" in wb_today_data
    assert "checkinCount" in wb_today_data

    res_wb_weekly = client.get("/analytics/admin/wellbeing/weekly", headers=headers, params={"period": "this_week"})
    assert res_wb_weekly.status_code == 200
    wb_weekly_data = res_wb_weekly.json()
    assert "overallWellbeing" in wb_weekly_data
    assert "checkinCount" in wb_weekly_data

