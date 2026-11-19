import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import date, datetime, timezone, timedelta

client = TestClient(app)

def test_manager_analytics_rbac_and_aggregation(test_db):
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
        "/manager/analytics/team-summary",
        headers={"Authorization": f"Bearer {mgr_token}"},
        params={"team_id": str(team.id)}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["total_employees"] == 3
    assert data["aggregate_wellbeing"] is not None
    assert "by_tier" in data["aggregate_wellbeing"]
    assert "workload_summary" in data
    assert "recommendation_effectiveness" in data


def test_manager_analytics_date_boundaries_and_unbounded(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"OrgBound {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    mgr_user = models.User(
        email=f"mgr_bound_{unique_id}@test.com", full_name="Manager Bound", role="MANAGER",
        account_type="team", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(mgr_user)
    test_db.commit()
    test_db.refresh(mgr_user)

    team = models.Team(name=f"Team Bound {unique_id}", manager_user_id=mgr_user.id, organization_id=org.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    emp_users = []
    emp_profiles = []
    for i in range(3):
        emp_user = models.User(
            email=f"emp_bound_{i}_{unique_id}@test.com", full_name=f"Employee {i}", role="EMPLOYEE",
            account_type="team", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(emp_user)
        test_db.commit()
        test_db.refresh(emp_user)
        emp_users.append(emp_user)

        emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False)
        test_db.add(emp_profile)
        test_db.commit()
        test_db.refresh(emp_profile)
        emp_profiles.append(emp_profile)

        membership = models.TeamMembership(team_id=team.id, profile_id=emp_profile.id, role="EMPLOYEE")
        test_db.add(membership)
        test_db.commit()

    profile_id = emp_profiles[0].id
    timestamps = [
        datetime(2018, 1, 1, 10, 0, tzinfo=timezone.utc), # 0: old record
        datetime(2026, 6, 9, 23, 59, 59, tzinfo=timezone.utc), # 1: before start
        datetime(2026, 6, 10, 0, 0, 0, tzinfo=timezone.utc), # 2: at start
        datetime(2026, 6, 15, 12, 0, 0, tzinfo=timezone.utc), # 3: during
        datetime(2026, 6, 20, 23, 59, 59, tzinfo=timezone.utc), # 4: on end
        datetime(2026, 6, 21, 0, 0, 1, tzinfo=timezone.utc), # 5: after end
    ]

    for idx, ts in enumerate(timestamps):
        session = models.WorkSession(
            profile_id=profile_id,
            started_at=ts,
            ended_at=ts + timedelta(hours=1),
        )
        test_db.add(session)
    test_db.commit()

    mgr_token = create_access_token(data={"sub": mgr_user.email})
    headers = {"Authorization": f"Bearer {mgr_token}"}
    team_id_str = str(team.id)

    # Test selected window: 2026-06-10 to 2026-06-20
    res = client.get(
        "/manager/analytics/team-summary",
        headers=headers,
        params={"team_id": team_id_str, "start_date": "2026-06-10", "end_date": "2026-06-20"}
    )
    assert res.status_code == 200
    data = res.json()
    # Expect sessions at start (2), during (3), on end (4) -> total 3 sessions (3 hours total work)
    # Excludes before start (1), after end (5), and old historical (0)
    assert data["workload_summary"]["total_work_hours"] == 3.0

    # Test unbounded All Time (no start_date)
    res_all = client.get(
        "/manager/analytics/team-summary",
        headers=headers,
        params={"team_id": team_id_str, "end_date": "2026-06-20"}
    )
    assert res_all.status_code == 200
    data_all = res_all.json()
    # Should include old historical record (0) + 1, 2, 3, 4 (total 5 sessions = 5 hours)
    assert data_all["workload_summary"]["total_work_hours"] == 5.0


def test_employee_forbidden_manager_analytics(test_db):
    unique_id = str(uuid.uuid4())[:8]
    emp_user = models.User(
        email=f"emp_{unique_id}@test.com", full_name="Employee", role="EMPLOYEE",
        account_type="solo", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)
    emp_token = create_access_token(data={"sub": emp_user.email})

    response = client.get(
        "/manager/analytics/team-summary",
        headers={"Authorization": f"Bearer {emp_token}"}
    )
    assert response.status_code == 403


def test_team_activity_summary_endpoint(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Activity {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    mgr_user = models.User(
        email=f"mgr_act_{unique_id}@test.com", full_name="Manager Activity", role="MANAGER",
        account_type="team", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(mgr_user)
    test_db.commit()
    test_db.refresh(mgr_user)

    mgr_profile = models.Profile(user_id=mgr_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(mgr_profile)
    test_db.commit()

    team = models.Team(name=f"Team Activity {unique_id}", manager_user_id=mgr_user.id, organization_id=org.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    emp_user = models.User(
        email=f"emp_act_{unique_id}@test.com", full_name="Employee Activity", role="EMPLOYEE",
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

    session = models.WorkSession(
        profile_id=emp_profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=2),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=1),
    )
    test_db.add(session)
    test_db.commit()

    mgr_token = create_access_token(data={"sub": mgr_user.email})
    response = client.get(
        f"/teams/{team.id}/activity-summary",
        headers={"Authorization": f"Bearer {mgr_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1
    found = False
    for item in data:
        if item.get("employee_id") == str(emp_user.id) or item.get("id") == str(emp_user.id):
            found = True
            assert len(item.get("work_sessions", [])) >= 1
    assert found

