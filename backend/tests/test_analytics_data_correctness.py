import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import date, datetime, timezone, timedelta

client = TestClient(app)

def test_incomplete_break_handling(test_db):
    unique_id = str(uuid.uuid4())[:8]
    user = models.User(
        email=f"emp_{unique_id}@test.com", full_name="Emp Test", role="EMPLOYEE",
        account_type="solo", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = models.Profile(user_id=user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    now = datetime.now(timezone.utc)
    session = models.WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=2),
        ended_at=now
    )
    test_db.add(session)
    test_db.commit()
    test_db.refresh(session)

    # Completed break
    b1 = models.Break(
        work_session_id=session.id,
        break_type="SHORT_BREAK",
        started_at=now - timedelta(hours=1, minutes=30),
        ended_at=now - timedelta(hours=1, minutes=15)
    )
    # Incomplete break (ended_at is None)
    b2 = models.Break(
        work_session_id=session.id,
        break_type="LUNCH",
        started_at=now - timedelta(minutes=30),
        ended_at=None
    )
    test_db.add_all([b1, b2])
    test_db.commit()

    # Calculate break analysis via AnalyticsEngine
    from app.services.analytics_service import AnalyticsEngine
    analysis = AnalyticsEngine.calculate_break_analysis(
        test_db, profile.id, now - timedelta(days=1), now + timedelta(days=1)
    )

    # Total breaks count should include b1 and b2 (or handle b2 gracefully)
    assert analysis["totalBreaks"] >= 1
    # Average duration should not include massive orphaned time from b2 (should be around 15 mins = 900s)
    assert analysis["avgBreakDurationSeconds"] < 3600


def test_manager_privacy_threshold_wellbeing(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    mgr = models.User(
        email=f"mgr_{unique_id}@test.com", full_name="Mgr Test", role="MANAGER",
        account_type="team", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(mgr)
    test_db.commit()
    test_db.refresh(mgr)

    mgr_profile = models.Profile(user_id=mgr.id, target_daily_hours=8, is_test_data=False)
    test_db.add(mgr_profile)
    test_db.commit()

    team = models.Team(name=f"Team {unique_id}", manager_user_id=mgr.id, organization_id=org.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    # Add only 2 employees (below threshold of 3)
    for i in range(2):
        u = models.User(
            email=f"emp_{i}_{unique_id}@test.com", full_name=f"Emp {i}", role="EMPLOYEE",
            account_type="team", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(u)
        test_db.commit()
        test_db.refresh(u)
        p = models.Profile(user_id=u.id, target_daily_hours=8, is_test_data=False)
        test_db.add(p)
        test_db.commit()
        test_db.refresh(p)
        m = models.TeamMembership(team_id=team.id, profile_id=p.id, role="EMPLOYEE")
        test_db.add(m)
        test_db.commit()

    token = create_access_token(data={"sub": mgr.email})
    response = client.get(
        "/manager/analytics/team-summary",
        headers={"Authorization": f"Bearer {token}"},
        params={"team_id": str(team.id)}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["aggregate_wellbeing"] is None
    assert "require at least 3" in data["note"]


def test_wellbeing_monitoring_and_analytics_synchronization(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"OrgSync {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    mgr = models.User(
        email=f"mgr_sync_{unique_id}@test.com", full_name="Mgr Sync", role="MANAGER",
        account_type="team", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(mgr)
    test_db.commit()
    test_db.refresh(mgr)

    team = models.Team(name=f"Team Sync {unique_id}", manager_user_id=mgr.id, organization_id=org.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    test_db.refresh(team)

    # Add 3 employees with sessions
    for i in range(3):
        u = models.User(
            email=f"emp_sync_{i}_{unique_id}@test.com", full_name=f"Emp Sync {i}", role="EMPLOYEE",
            account_type="team", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(u)
        test_db.commit()
        test_db.refresh(u)
        p = models.Profile(user_id=u.id, target_daily_hours=8, is_test_data=False)
        test_db.add(p)
        test_db.commit()
        test_db.refresh(p)
        m = models.TeamMembership(team_id=team.id, profile_id=p.id, role="EMPLOYEE")
        test_db.add(m)
        test_db.commit()

        # Add 3 sessions in current week
        now = datetime.now(timezone.utc)
        monday = now - timedelta(days=now.weekday())
        for j in range(3):
            ws = models.WorkSession(
                profile_id=p.id,
                started_at=monday + timedelta(days=j, hours=9),
                ended_at=monday + timedelta(days=j, hours=17)
            )
            test_db.add(ws)
        test_db.commit()

    token = create_access_token(data={"sub": mgr.email})
    headers = {"Authorization": f"Bearer {token}"}

    res_wb = client.get("/manager/wellbeing/weekly", headers=headers, params={"team_id": str(team.id)})
    res_an = client.get("/manager/analytics/team-summary", headers=headers, params={"team_id": str(team.id)})

    assert res_wb.status_code == 200
    assert res_an.status_code == 200

    wb_data = res_wb.json()
    an_data = res_an.json()

    assert an_data["aggregate_wellbeing"]["reporting_period"]["start_date"] == wb_data["week_start"]
    assert an_data["aggregate_wellbeing"]["reporting_period"]["end_date"] == wb_data["week_end"]
    assert an_data["aggregate_wellbeing"]["total_monitored"] == wb_data["team_summary"]["total_employees"]
    assert an_data["aggregate_wellbeing"]["by_tier"] == wb_data["team_summary"]["by_tier"]

