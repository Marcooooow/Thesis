import pytest
from fastapi.testclient import TestClient
from datetime import date, time, timedelta, datetime, timezone
from app.main import app
from app.database import get_db
from app.models import User, Profile, Team, TeamMembership, LeaveType, Organization, WorkSession
from app.auth.security import get_password_hash
from sqlalchemy.orm import Session

@pytest.fixture
def client(db: Session):
    def override_get_db():
        try:
            yield db
        finally:
            pass
    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)

def get_auth_headers(client: TestClient, email: str, password: str = "password123") -> dict:
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, f"Login failed for {email}: {response.text}"
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

def test_absence_phase4_comprehensive_api(client: TestClient, db: Session):
    org = db.query(Organization).first()
    if not org:
        org = Organization(name="Org Phase4")
        db.add(org)
        db.commit()
        db.refresh(org)

    # 1. Setup Users
    admin_pw = get_password_hash("password123")
    admin_user = User(email="p4_admin@ex.com", password_hash=admin_pw, full_name="Admin", role="ADMIN", account_type="enterprise_admin", approval_status="APPROVED", is_active=True)
    mgr_user = User(email="p4_mgr@ex.com", password_hash=admin_pw, full_name="Manager", role="MANAGER", approval_status="APPROVED", is_active=True)
    emp_user = User(email="p4_emp@ex.com", password_hash=admin_pw, full_name="Employee", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    other_mgr = User(email="p4_othermgr@ex.com", password_hash=admin_pw, full_name="Other Mgr", role="MANAGER", approval_status="APPROVED", is_active=True)

    db.add_all([admin_user, mgr_user, emp_user, other_mgr])
    db.commit()

    admin_p = Profile(user_id=admin_user.id)
    mgr_p = Profile(user_id=mgr_user.id)
    emp_p = Profile(user_id=emp_user.id)
    other_p = Profile(user_id=other_mgr.id)
    db.add_all([admin_p, mgr_p, emp_p, other_p])
    db.commit()

    team = Team(name="Engineering Team", manager_user_id=mgr_user.id, organization_id=org.id)
    db.add(team)
    db.commit()

    membership = TeamMembership(team_id=team.id, profile_id=emp_p.id, left_at=None)
    db.add(membership)
    db.commit()

    admin_headers = get_auth_headers(client, "p4_admin@ex.com")
    mgr_headers = get_auth_headers(client, "p4_mgr@ex.com")
    emp_headers = get_auth_headers(client, "p4_emp@ex.com")
    other_mgr_headers = get_auth_headers(client, "p4_othermgr@ex.com")

    # 2. Admin Leave Types API
    res = client.post("/admin/leave-types", headers=admin_headers, json={
        "name": "Sick Leave API",
        "requires_documentation": True,
        "sort_order": 1
    })
    assert res.status_code == 201
    leave_type_id = res.json()["id"]

    res = client.get("/admin/leave-types", headers=admin_headers)
    assert res.status_code == 200
    assert len(res.json()) >= 1

    # 3. Schedule Management API
    today = date.today()
    res = client.post(f"/schedules/{emp_p.id}", headers=mgr_headers, json={
        "effective_from": today.isoformat(),
        "work_days": [today.strftime("%A").lower()],
        "shift_start": "08:00:00",
        "shift_end": "17:00:00",
        "timezone": "UTC"
    })
    assert res.status_code == 201

    # Test Cross-Team Access Restriction (403 for unauthorized manager)
    res = client.get(f"/schedules/{emp_p.id}/current", headers=other_mgr_headers)
    assert res.status_code == 403

    # Authorized manager view current schedule
    res = client.get(f"/schedules/{emp_p.id}/current", headers=mgr_headers)
    assert res.status_code == 200
    assert res.json()["timezone"] == "UTC"

    # 4. Leave Request Workflow API
    res = client.post("/leave/requests", headers=emp_headers, json={
        "leave_type_id": leave_type_id,
        "start_date": (today + timedelta(days=2)).isoformat(),
        "end_date": (today + timedelta(days=3)).isoformat(),
        "reason": "Doctor visit"
    })
    assert res.status_code == 201
    leave_req_id = res.json()["id"]

    res = client.get("/leave/requests/my", headers=emp_headers)
    assert res.status_code == 200
    assert len(res.json()) >= 1

    # Manager view team leave requests
    res = client.get("/manager/leave/requests", headers=mgr_headers)
    assert res.status_code == 200
    assert len(res.json()) >= 1

    # Self-Approval Prevention (403)
    # If employee tries to review their own leave request (or manager who is employee tries to approve)
    res = client.patch(f"/manager/leave/requests/{leave_req_id}/review", headers=emp_headers, json={
        "approve": True,
        "reviewer_note": "Self approving"
    })
    assert res.status_code == 403

    # Manager approves leave request
    res = client.patch(f"/manager/leave/requests/{leave_req_id}/review", headers=mgr_headers, json={
        "approve": True,
        "reviewer_note": "Approved by manager"
    })
    assert res.status_code == 200
    assert res.json()["status"] == "APPROVED"

    # 5. Absence Management API
    res = client.get("/manager/absences", headers=mgr_headers)
    assert res.status_code == 200

    # 6. Return-to-Work API & Privacy
    ws = WorkSession(
        profile_id=emp_p.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=8),
        ended_at=datetime.now(timezone.utc)
    )
    db.add(ws)
    db.commit()
    db.refresh(ws)

    res = client.get("/return-to-work/pending", headers=emp_headers)
    assert res.status_code == 200
    assert res.json()["has_pending"] is True

    # Employee submits RTW checkin
    res = client.post("/return-to-work/checkin", headers=emp_headers, json={
        "work_session_id": str(ws.id),
        "absence_reason_category": "Health",
        "overall_feeling": 4,
        "workload_concern": 2,
        "stress_concern": 1,
        "work_contributed_to_absence": False,
        "wants_manager_support": True,
        "additional_comments": "Private personal health details",
        "is_manager_visible": True
    })
    assert res.status_code == 201

    # Manager team RTW view — verifying strict privacy filtering (omitting feeling, comments, etc.)
    res = client.get("/manager/return-to-work/team", headers=mgr_headers)
    assert res.status_code == 200
    team_rtw = res.json()
    assert len(team_rtw) >= 1
    item = team_rtw[0]
    assert "wants_manager_support" in item
    assert "absence_reason_category" in item
    assert "overall_feeling" not in item
    assert "additional_comments" not in item

    # 7. Employee Self-Service Attendance Overview API
    res = client.get("/attendance/my", headers=emp_headers)
    assert res.status_code == 200
    att_data = res.json()
    assert "schedule" in att_data
    assert "absences" in att_data
    assert "leave_requests" in att_data
    assert "pending_rtw" in att_data
