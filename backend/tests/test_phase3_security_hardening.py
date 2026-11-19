import uuid

from fastapi import HTTPException
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.auth.security import get_password_hash
from app.main import app
from app.models import (
    Organization,
    OrganizationMembership,
    Profile,
    SessionWellbeingCheckin,
    SystemActivityLog,
    Team,
    User,
    WorkSession,
)
from app.services.team_analytics_service import compute_team_analytics


def _make_user(db, email, role):
    user = User(
        email=email,
        password_hash=get_password_hash("SecureTestPass123!"),
        full_name=email.split("@")[0],
        role=role,
        approval_status="APPROVED",
        is_active=True,
        account_type="organization",
    )
    db.add(user)
    db.flush()
    return user


def _login(client, email):
    response = client.post("/auth/login", json={"email": email, "password": "SecureTestPass123!"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_admin_analytics_without_membership_fails_closed(test_db: Session):
    admin = _make_user(test_db, f"admin-{uuid.uuid4()}@test.local", "ADMIN")
    with pytest.raises(HTTPException) as exc:
        compute_team_analytics(test_db, admin)
    assert exc.value.status_code == 403


def test_admin_audit_logs_are_limited_to_approved_org(test_client: TestClient, test_db: Session):
    org1 = Organization(name=f"Audit scope A {uuid.uuid4()}")
    org2 = Organization(name=f"Audit scope B {uuid.uuid4()}")
    test_db.add_all([org1, org2])
    test_db.flush()
    admin = _make_user(test_db, f"audit-admin-{uuid.uuid4()}@test.local", "ADMIN")
    local_actor = _make_user(test_db, f"actor-a-{uuid.uuid4()}@test.local", "EMPLOYEE")
    other_actor = _make_user(test_db, f"actor-b-{uuid.uuid4()}@test.local", "EMPLOYEE")
    test_db.add_all([
        OrganizationMembership(user_id=admin.id, organization_id=org1.id, role="ADMIN", status="APPROVED"),
        OrganizationMembership(user_id=local_actor.id, organization_id=org1.id, role="EMPLOYEE", status="APPROVED"),
        OrganizationMembership(user_id=other_actor.id, organization_id=org2.id, role="EMPLOYEE", status="APPROVED"),
        SystemActivityLog(user_id=local_actor.id, action_type="LOCAL_SCOPE_EVENT", action_details={"summary": "local"}),
        SystemActivityLog(user_id=other_actor.id, action_type="OTHER_SCOPE_EVENT", action_details={"summary": "other"}),
        SystemActivityLog(user_id=None, action_type="SYSTEM_SCOPE_EVENT", action_details={"summary": "system"}),
    ])
    test_db.commit()
    response = test_client.get("/admin/audit-logs", headers=_login(test_client, admin.email))
    assert response.status_code == 200
    assert "LOCAL_SCOPE_EVENT" in {row["action_type"] for row in response.json()}
    assert "OTHER_SCOPE_EVENT" not in {row["action_type"] for row in response.json()}
    assert "SYSTEM_SCOPE_EVENT" not in {row["action_type"] for row in response.json()}


def test_admin_without_org_membership_cannot_read_audit_logs(test_client: TestClient, test_db: Session):
    admin = _make_user(test_db, f"orphan-admin-{uuid.uuid4()}@test.local", "ADMIN")
    test_db.commit()
    response = test_client.get("/admin/audit-logs", headers=_login(test_client, admin.email))
    assert response.status_code == 403


def test_admin_without_org_cannot_read_another_users_recommendations(test_client: TestClient, test_db: Session):
    admin = _make_user(test_db, f"orphan-rec-admin-{uuid.uuid4()}@test.local", "ADMIN")
    employee = _make_user(test_db, f"target-rec-employee-{uuid.uuid4()}@test.local", "EMPLOYEE")
    test_db.add(Profile(user_id=employee.id, is_test_data=False))
    test_db.commit()
    response = test_client.get(f"/admin/users/{employee.id}/recommendations", headers=_login(test_client, admin.email))
    assert response.status_code == 403


def test_admin_cannot_read_recommendations_from_unrelated_org(test_client: TestClient, test_db: Session):
    org_a, org_b = Organization(name=f"Org A {uuid.uuid4()}"), Organization(name=f"Org B {uuid.uuid4()}")
    test_db.add_all([org_a, org_b]); test_db.flush()
    admin = _make_user(test_db, f"org-admin-rec-{uuid.uuid4()}@test.local", "ADMIN")
    employee = _make_user(test_db, f"outside-rec-{uuid.uuid4()}@test.local", "EMPLOYEE")
    test_db.add_all([
        OrganizationMembership(user_id=admin.id, organization_id=org_a.id, role="ADMIN", status="APPROVED"),
        OrganizationMembership(user_id=employee.id, organization_id=org_b.id, role="EMPLOYEE", status="APPROVED"),
        Profile(user_id=employee.id, is_test_data=False),
    ]); test_db.commit()
    response = test_client.get(f"/admin/users/{employee.id}/recommendations", headers=_login(test_client, admin.email))
    assert response.status_code == 403


def test_admin_cannot_read_wellbeing_from_unrelated_org(test_client: TestClient, test_db: Session):
    org_a, org_b = Organization(name=f"Org A {uuid.uuid4()}"), Organization(name=f"Org B {uuid.uuid4()}")
    test_db.add_all([org_a, org_b]); test_db.flush()
    admin = _make_user(test_db, f"org-admin-wb-{uuid.uuid4()}@test.local", "ADMIN")
    employee = _make_user(test_db, f"outside-wb-{uuid.uuid4()}@test.local", "EMPLOYEE")
    test_db.add_all([
        OrganizationMembership(user_id=admin.id, organization_id=org_a.id, role="ADMIN", status="APPROVED"),
        OrganizationMembership(user_id=employee.id, organization_id=org_b.id, role="EMPLOYEE", status="APPROVED"),
        Profile(user_id=employee.id, is_test_data=False),
    ]); test_db.commit()
    response = test_client.get(f"/admin/users/{employee.id}/wellbeing", headers=_login(test_client, admin.email))
    assert response.status_code == 403


def test_employee_cannot_read_another_employees_session_breaks(test_client: TestClient, test_db: Session):
    owner, other = _make_user(test_db, f"session-owner-{uuid.uuid4()}@test.local", "EMPLOYEE"), _make_user(test_db, f"session-other-{uuid.uuid4()}@test.local", "EMPLOYEE")
    owner_profile, other_profile = Profile(user_id=owner.id), Profile(user_id=other.id)
    test_db.add_all([owner_profile, other_profile]); test_db.flush()
    session = WorkSession(profile_id=other_profile.id, started_at=__import__("datetime").datetime.now(__import__("datetime").timezone.utc))
    test_db.add(session); test_db.commit()
    response = test_client.get(f"/work/session/{session.id}/breaks", headers=_login(test_client, owner.email))
    assert response.status_code == 403


def test_employee_cannot_read_another_employees_wellbeing(test_client: TestClient, test_db: Session):
    owner, other = _make_user(test_db, f"wb-owner-{uuid.uuid4()}@test.local", "EMPLOYEE"), _make_user(test_db, f"wb-other-{uuid.uuid4()}@test.local", "EMPLOYEE")
    owner_profile, other_profile = Profile(user_id=owner.id), Profile(user_id=other.id)
    test_db.add_all([owner_profile, other_profile]); test_db.flush()
    session = WorkSession(profile_id=other_profile.id, started_at=__import__("datetime").datetime.now(__import__("datetime").timezone.utc))
    test_db.add(session); test_db.flush()
    checkin = SessionWellbeingCheckin(user_id=other.id, work_session_id=session.id, overall_wellbeing=3)
    test_db.add(checkin); test_db.commit()
    by_id = test_client.get(f"/session-wellbeing/{checkin.id}", headers=_login(test_client, owner.email))
    by_session = test_client.get(f"/session-wellbeing/?work_session_id={session.id}", headers=_login(test_client, owner.email))
    assert by_id.status_code == 403
    assert by_session.status_code == 200 and by_session.json() == []


def test_manager_cannot_report_unrelated_team(test_db: Session):
    org = Organization(name=f"Manager scope {uuid.uuid4()}"); test_db.add(org); test_db.flush()
    manager_a = _make_user(test_db, f"manager-a-{uuid.uuid4()}@test.local", "MANAGER")
    manager_b = _make_user(test_db, f"manager-b-{uuid.uuid4()}@test.local", "MANAGER")
    team = Team(name=f"Other team {uuid.uuid4()}", organization_id=org.id, manager_user_id=manager_b.id, is_active=True)
    test_db.add(team); test_db.commit()
    with pytest.raises(HTTPException) as exc:
        compute_team_analytics(test_db, manager_a, team_id=team.id)
    assert exc.value.status_code == 403


def test_employee_cannot_request_manager_report(test_client: TestClient, test_db: Session):
    employee = _make_user(test_db, f"employee-report-{uuid.uuid4()}@test.local", "EMPLOYEE")
    test_db.add(Profile(user_id=employee.id, is_test_data=False)); test_db.commit()
    response = test_client.get("/reports/export-excel?report_type=manager", headers=_login(test_client, employee.email))
    assert response.status_code == 403


def test_admin_analytics_includes_only_approved_org_profiles(test_db: Session):
    org1, org2 = Organization(name=f"Scoped Org A {uuid.uuid4()}"), Organization(name=f"Scoped Org B {uuid.uuid4()}")
    test_db.add_all([org1, org2]); test_db.flush()
    admin = _make_user(test_db, f"scoped-admin-{uuid.uuid4()}@test.local", "ADMIN")
    employee_a = _make_user(test_db, f"scoped-a-{uuid.uuid4()}@test.local", "EMPLOYEE")
    employee_b = _make_user(test_db, f"scoped-b-{uuid.uuid4()}@test.local", "EMPLOYEE")
    profile_a, profile_b = Profile(user_id=employee_a.id, is_test_data=False), Profile(user_id=employee_b.id, is_test_data=False)
    test_db.add_all([
        OrganizationMembership(user_id=admin.id, organization_id=org1.id, role="ADMIN", status="APPROVED"),
        OrganizationMembership(user_id=employee_a.id, organization_id=org1.id, role="EMPLOYEE", status="APPROVED"),
        OrganizationMembership(user_id=employee_b.id, organization_id=org2.id, role="EMPLOYEE", status="APPROVED"),
        profile_a, profile_b,
    ]); test_db.commit()
    result = compute_team_analytics(test_db, admin)
    assert profile_a.id in result["profile_ids"]
    assert profile_b.id not in result["profile_ids"]
