import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta, date

client = TestClient(app)

def test_organizational_insights_comprehensive(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Insights {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_insights_{unique_id}@test.com", full_name="Admin Insights", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)
    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Create Team with 3 employees (N >= 3)
    team1 = models.Team(name="Insights Team Alpha", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team1)
    test_db.commit()
    test_db.refresh(team1)

    profile_ids = []
    for i in range(3):
        emp = models.User(
            email=f"emp_insights_{i}_{unique_id}@test.com", full_name=f"Emp Insights {i}", role="EMPLOYEE",
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
        profile_ids.append(prof.id)
        test_db.add(models.OrganizationMembership(user_id=emp.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
        test_db.add(models.TeamMembership(team_id=team1.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

        # Add work session & tasks
        now_utc = datetime.now(timezone.utc)
        sess = models.WorkSession(
            profile_id=prof.id,
            started_at=now_utc - timedelta(hours=6),
            ended_at=now_utc - timedelta(hours=1)
        )
        test_db.add(sess)
        test_db.commit()

        # Add WLB survey
        survey = models.WorkLifeBalanceSurvey(
            profile_id=prof.id,
            organization_id=org.id,
            week_start_date=now_utc.date() - timedelta(days=now_utc.weekday()),
            rating_disconnect=4,
            rating_personal_time=4,
            rating_responsibilities_balance=4,
            rating_schedule_satisfaction=4,
            rating_recovery=4,
            score=75.0,
            submitted_at=now_utc
        )
        test_db.add(survey)

        # Add recommendation feedback
        fb = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=uuid.uuid4(),
            model_version="cold-start-baseline",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.9,
            context_features={},
            timestamp=now_utc,
            user_action="accepted",
            break_started_at=now_utc + timedelta(minutes=10)
        )
        test_db.add(fb)
        test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    # 1. Test endpoint access and general structure
    res = client.get("/analytics/admin/organizational-insights", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    data = res.json()
    assert "insights" in data
    assert "severity_counts" in data
    assert "total_insights" in data
    assert data["data_quality_indicator"] == "sufficient_data"

    # 2. Test category filtering
    res_cat = client.get("/analytics/admin/organizational-insights", headers=headers, params={"category": "productivity"})
    assert res_cat.status_code == 200
    cat_data = res_cat.json()
    for ins in cat_data["insights"]:
        assert ins["category"] == "productivity"

    # 3. Test unauthorized access (employee role)
    emp_token = create_access_token(data={"sub": f"emp_insights_0_{unique_id}@test.com"})
    emp_headers = {"Authorization": f"Bearer {emp_token}"}
    res_unauth = client.get("/analytics/admin/organizational-insights", headers=emp_headers)
    assert res_unauth.status_code == 403

    # 4. Test empty organization data (new org with no members/sessions)
    empty_org_id = models.Organization(name=f"Empty Org {unique_id}")
    test_db.add(empty_org_id)
    test_db.commit()
    empty_admin = models.User(
        email=f"empty_admin_{unique_id}@test.com", full_name="Empty Admin", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(empty_admin)
    test_db.commit()
    test_db.add(models.OrganizationMembership(user_id=empty_admin.id, organization_id=empty_org_id.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    empty_token = create_access_token(data={"sub": empty_admin.email})
    empty_headers = {"Authorization": f"Bearer {empty_token}"}
    res_empty = client.get("/analytics/admin/organizational-insights", headers=empty_headers, params={"period": "this_week"})
    assert res_empty.status_code == 200
    empty_data = res_empty.json()
    assert empty_data["data_quality_indicator"] == "insufficient_data"
    assert empty_data["total_insights"] == 1
    assert empty_data["insights"][0]["category"] == "productivity"
    assert empty_data["insights"][0]["severity"] == "informational"
