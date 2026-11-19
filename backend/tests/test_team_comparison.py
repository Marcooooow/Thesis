import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import date, datetime, timezone, timedelta

client = TestClient(app)

def test_team_comparison_endpoint_and_privacy(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Team Comp {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_comp_{unique_id}@test.com", full_name="Admin Comp", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)
    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Create Team 1 with >= 3 employees (not suppressed)
    team1 = models.Team(name="Team Alpha", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team1)
    test_db.commit()
    test_db.refresh(team1)

    for i in range(3):
        emp = models.User(
            email=f"emp1_{i}_{unique_id}@test.com", full_name=f"Emp 1-{i}", role="EMPLOYEE",
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

        # Add session
        sess = models.WorkSession(profile_id=prof.id, started_at=datetime.now(timezone.utc) - timedelta(hours=4), ended_at=datetime.now(timezone.utc))
        test_db.add(sess)
        test_db.commit()

    # Create Team 2 with < 3 employees (suppressed N < 3)
    team2 = models.Team(name="Team Beta", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team2)
    test_db.commit()
    test_db.refresh(team2)

    for i in range(2):
        emp = models.User(
            email=f"emp2_{i}_{unique_id}@test.com", full_name=f"Emp 2-{i}", role="EMPLOYEE",
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

    res = client.get("/analytics/admin/team-comparison", headers=headers, params={"period": "this_week"})
    assert res.status_code == 200
    data = res.json()
    assert "teams" in data
    assert len(data["teams"]) == 2

    team_map = {t["team_name"]: t for t in data["teams"]}
    assert "Team Alpha" in team_map
    assert "Team Beta" in team_map

    # Team Alpha (3 employees >= 3) -> not privacy suppressed
    assert team_map["Team Alpha"]["active_employees"] == 3
    assert team_map["Team Alpha"]["privacy_suppressed"] is False
    assert "productivity" in team_map["Team Alpha"]
    assert "work_sustainability" in team_map["Team Alpha"]
    assert "work_life_balance" in team_map["Team Alpha"]

    # Team Beta (2 employees < 3) -> privacy suppressed
    assert team_map["Team Beta"]["active_employees"] == 2
    assert team_map["Team Beta"]["privacy_suppressed"] is True
    assert team_map["Team Beta"]["work_life_balance"]["avg_wlb_score"] is None

    # Test unauthorized access (employee role)
    emp_token = create_access_token(data={"sub": f"emp1_0_{unique_id}@test.com"})
    emp_headers = {"Authorization": f"Bearer {emp_token}"}
    res_unauth = client.get("/analytics/admin/team-comparison", headers=emp_headers)
    assert res_unauth.status_code == 403
