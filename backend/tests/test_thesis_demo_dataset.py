import pytest
from datetime import datetime
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app
from app.models import (
    User, Profile, Organization, OrganizationMembership,
    Team, TeamMembership, WorkSession, Break, Task,
    SessionWellbeingCheckin, RecommendationFeedback
)
from app.auth.security import create_access_token, get_password_hash
from seed_thesis_demo_dataset import seed_thesis_dataset, THESIS_ORG_NAME, TEMP_PASSWORD

client = TestClient(app)

@pytest.fixture(autouse=True)
def run_thesis_seeder(test_db: Session):
    # Run seeder twice to test idempotency
    seed_thesis_dataset(test_db)
    seed_thesis_dataset(test_db)

def test_thesis_organization_exists(test_db: Session):
    orgs = test_db.query(Organization).filter(Organization.name == THESIS_ORG_NAME).all()
    assert len(orgs) == 1, "Exactly one thesis demo organization must exist"

def test_thesis_admin_and_managers(test_db: Session):
    org = test_db.query(Organization).filter(Organization.name == THESIS_ORG_NAME).first()

    admin = test_db.query(User).filter(User.email == "thesis.admin@intellibreak.local").first()
    assert admin is not None
    assert admin.role == "ADMIN"
    admin_mem = test_db.query(OrganizationMembership).filter_by(user_id=admin.id, organization_id=org.id, role="ADMIN").first()
    assert admin_mem is not None

    managers = test_db.query(User).filter(User.email.in_(["thesis.manager01@intellibreak.local", "thesis.manager02@intellibreak.local"])).all()
    assert len(managers) == 2
    for m in managers:
        assert m.role == "MANAGER"
        m_mem = test_db.query(OrganizationMembership).filter_by(user_id=m.id, organization_id=org.id, role="MANAGER").first()
        assert m_mem is not None

def test_thesis_teams_and_assignments(test_db: Session):
    org = test_db.query(Organization).filter(Organization.name == THESIS_ORG_NAME).first()
    teams = test_db.query(Team).filter(Team.organization_id == org.id).all()
    assert len(teams) == 2

    for team in teams:
        assert team.manager_user_id is not None
        memberships = test_db.query(TeamMembership).filter_by(team_id=team.id).all()
        assert len(memberships) == 10, f"Team {team.name} must have exactly 10 employees"

def test_thesis_employee_profiles_and_test_data(test_db: Session):
    org = test_db.query(Organization).filter(Organization.name == THESIS_ORG_NAME).first()
    employees = test_db.query(User).filter(User.email.like("thesis.employee%@intellibreak.local")).all()
    assert len(employees) == 20

    for emp in employees:
        assert emp.role == "EMPLOYEE"
        profile = test_db.query(Profile).filter_by(user_id=emp.id).first()
        assert profile is not None
        assert profile.is_test_data is True, "All thesis profiles must be marked as test data"

def test_thesis_historical_activity(test_db: Session):
    org = test_db.query(Organization).filter(Organization.name == THESIS_ORG_NAME).first()
    emp_ids = [u.id for u in test_db.query(User).filter(User.email.like("thesis.employee%@intellibreak.local")).all()]
    profile_ids = [p.id for p in test_db.query(Profile).filter(Profile.user_id.in_(emp_ids)).all()]

    sessions_count = test_db.query(WorkSession).filter(WorkSession.profile_id.in_(profile_ids)).count()
    assert sessions_count > 0, "Historical work sessions must be generated"

    tasks_count = test_db.query(Task).filter(Task.profile_id.in_(profile_ids)).count()
    assert tasks_count > 0, "Historical tasks must be generated"

    feedback_count = test_db.query(RecommendationFeedback).filter(RecommendationFeedback.user_id.in_(emp_ids)).count()
    assert feedback_count > 0, "Recommendation feedback must be generated"

def test_thesis_authentication(test_db: Session):
    # Test admin login
    resp = client.post("/auth/login", json={"email": "thesis.admin@intellibreak.local", "password": TEMP_PASSWORD})
    assert resp.status_code == 200
    assert "access_token" in resp.json()

    # Test manager login
    resp = client.post("/auth/login", json={"email": "thesis.manager01@intellibreak.local", "password": TEMP_PASSWORD})
    assert resp.status_code == 200
    assert "access_token" in resp.json()

    # Test employee login
    resp = client.post("/auth/login", json={"email": "thesis.employee01@intellibreak.local", "password": TEMP_PASSWORD})
    assert resp.status_code == 200
    assert "access_token" in resp.json()

def test_existing_demo_accounts_untouched(test_db: Session):
    demo_user = test_db.query(User).filter(User.email == "demo_0@intellibreak.local").first()
    if demo_user:
        assert demo_user.role in ["EMPLOYEE", "MANAGER"]

def test_stress_factors_model_roundtrip(test_db: Session):
    """Regression test verifying stress_factors can be inserted and retrieved using the SessionWellbeingCheckin model."""
    emp = test_db.query(User).filter(User.email == "thesis.employee01@intellibreak.local").first()
    assert emp is not None
    profile = test_db.query(Profile).filter_by(user_id=emp.id).first()
    assert profile is not None

    ws = WorkSession(
        profile_id=profile.id,
        started_at=datetime.utcnow(),
        ended_at=datetime.utcnow()
    )
    test_db.add(ws)
    test_db.commit()
    test_db.refresh(ws)

    # Test insertion and retrieval with list of stress factors
    checkin = SessionWellbeingCheckin(
        user_id=emp.id,
        work_session_id=ws.id,
        overall_wellbeing=4,
        mental_fatigue=2,
        workload_manageability=4,
        perceived_focus=4,
        break_recovery=4,
        stress_factors=["Tight deadlines", "Complex problem"]
    )
    test_db.add(checkin)
    test_db.commit()
    test_db.refresh(checkin)

    retrieved = test_db.query(SessionWellbeingCheckin).filter(SessionWellbeingCheckin.id == checkin.id).first()
    assert retrieved is not None
    assert retrieved.stress_factors == ["Tight deadlines", "Complex problem"]

    # Clean up test checkin and work session
    test_db.delete(checkin)
    test_db.delete(ws)
    test_db.commit()


def test_thesis_manager_cross_team_isolation(test_db: Session):
    mgr1 = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    mgr2 = test_db.query(User).filter(User.email == "thesis.manager02@intellibreak.local").first()
    token1 = create_access_token(data={"sub": mgr1.email})
    token2 = create_access_token(data={"sub": mgr2.email})

    resp1 = client.get("/manager/analytics/team-summary", headers={"Authorization": f"Bearer {token1}"})
    assert resp1.status_code == 200
    data1 = resp1.json()
    assert data1["total_employees"] == 10
    assert data1["workload_summary"]["total_work_hours"] > 0

    resp2 = client.get("/manager/analytics/team-summary", headers={"Authorization": f"Bearer {token2}"})
    assert resp2.status_code == 200
    data2 = resp2.json()
    assert data2["total_employees"] == 10


def test_thesis_historical_week_wellbeing_and_current_week(test_db: Session):
    mgr1 = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    token1 = create_access_token(data={"sub": mgr1.email})

    resp_hist = client.get("/manager/wellbeing/weekly?week_start=2026-10-26", headers={"Authorization": f"Bearer {token1}"})
    assert resp_hist.status_code == 200
    hist_data = resp_hist.json()
    assert hist_data["team_summary"]["total_employees"] == 10

    resp_curr = client.get("/manager/wellbeing/weekly?week_start=2026-11-02", headers={"Authorization": f"Bearer {token1}"})
    assert resp_curr.status_code == 200
    curr_data = resp_curr.json()
    assert curr_data["team_summary"]["total_employees"] == 10


def test_normal_org_excludes_test_data(test_db: Session):
    normal_user = User(
        email="normal.user@test.com",
        password_hash=get_password_hash("password123"),
        full_name="Normal User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(normal_user)
    test_db.commit()

    from app.auth.security import should_include_test_data
    assert should_include_test_data(test_db, normal_user) is False


def test_thesis_report_exports(test_db: Session):
    mgr1 = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    token1 = create_access_token(data={"sub": mgr1.email})

    # Call Manager Analytics team summary
    resp_sum = client.get("/manager/analytics/team-summary", headers={"Authorization": f"Bearer {token1}"})
    assert resp_sum.status_code == 200
    sum_data = resp_sum.json()
    assert sum_data["total_employees"] == 10
    assert sum_data["workload_summary"]["total_work_hours"] > 0
    assert sum_data["recommendation_effectiveness"]["total_feedback"] > 0
    assert sum_data["recommendation_effectiveness"]["accepted"] >= 0
    assert sum_data["recommendation_effectiveness"]["dismissed"] >= 0

    # Test PDF export
    resp_pdf = client.get("/reports/export-pdf", headers={"Authorization": f"Bearer {token1}"})
    assert resp_pdf.status_code == 200
    assert resp_pdf.headers["content-type"] == "application/pdf"
    assert len(resp_pdf.content) > 1000

    # Test Excel export
    resp_excel = client.get("/reports/export-excel", headers={"Authorization": f"Bearer {token1}"})
    assert resp_excel.status_code == 200
    assert "spreadsheetml" in resp_excel.headers["content-type"]
    assert len(resp_excel.content) > 1000

    # Test CSV export
    resp_csv = client.get("/reports/export-csv", headers={"Authorization": f"Bearer {token1}"})
    assert resp_csv.status_code == 200
    assert resp_csv.headers["content-type"] == "application/zip"
    assert len(resp_csv.content) > 1000


def test_manager_01_and_02_independent_verification(test_db: Session):
    mgr1 = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    mgr2 = test_db.query(User).filter(User.email == "thesis.manager02@intellibreak.local").first()
    token1 = create_access_token(data={"sub": mgr1.email})
    token2 = create_access_token(data={"sub": mgr2.email})

    # Test explicit 7-day weekly window (Oct 26 - Nov 1, 2026)
    r1_7d = client.get("/manager/analytics/team-summary?start_date=2026-10-26&end_date=2026-11-01", headers={"Authorization": f"Bearer {token1}"}).json()
    r2_7d = client.get("/manager/analytics/team-summary?start_date=2026-10-26&end_date=2026-11-01", headers={"Authorization": f"Bearer {token2}"}).json()

    w1 = client.get("/manager/wellbeing/weekly?week_start=2026-10-26", headers={"Authorization": f"Bearer {token1}"}).json()
    w2 = client.get("/manager/wellbeing/weekly?week_start=2026-10-26", headers={"Authorization": f"Bearer {token2}"}).json()

    print("\n=== INDEPENDENT MANAGER 7-DAY VERIFICATION (Oct 26 - Nov 1, 2026) ===")
    print(f"Manager 1 (Alpha Engineering): Employees={r1_7d['total_employees']}, Work Hours={r1_7d['workload_summary']['total_work_hours']}, Wellbeing Tiers={w1['team_summary']['by_tier']}")
    print(f"Manager 2 (Beta Product): Employees={r2_7d['total_employees']}, Work Hours={r2_7d['workload_summary']['total_work_hours']}, Wellbeing Tiers={w2['team_summary']['by_tier']}")

    assert r1_7d["total_employees"] == 10
    assert r2_7d["total_employees"] == 10
    assert r1_7d["workload_summary"]["total_work_hours"] > 0
    assert r2_7d["workload_summary"]["total_work_hours"] > 0
    assert w1["team_summary"]["total_employees"] == 10
    assert w2["team_summary"]["total_employees"] == 10






