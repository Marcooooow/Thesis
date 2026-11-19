import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from datetime import datetime, timezone
import uuid

from app.models import User, SystemActivityLog, Organization, OrganizationMembership
from app.auth.security import get_password_hash, log_system_activity


def test_audit_log_creation_and_retrieval(test_client: TestClient, db: Session):
    # 1. Create an admin user
    admin_user = User(
        email="audit_admin@intellibreak.com",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Audit Admin",
        role="ADMIN",
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    organization = Organization(name="Audit Retrieval Org")
    db.add(organization)
    db.commit()
    db.add(OrganizationMembership(user_id=admin_user.id, organization_id=organization.id, role="ADMIN", status="APPROVED"))
    db.commit()

    # 2. Log a structured system activity manually using log_system_activity
    log_entry = log_system_activity(
        db=db,
        user_id=admin_user.id,
        action_type="USER_APPROVED",
        category="ACCOUNT",
        target_type="user",
        target_id=str(uuid.uuid4()),
        target_display_label="employee@intellibreak.com",
        outcome="SUCCESS",
        summary="Approved user employee@intellibreak.com",
        action_details={"role": "EMPLOYEE", "department": "Engineering"},
        ip_address="127.0.0.1",
        user_agent="TestAgent"
    )

    assert log_entry.id is not None
    assert log_entry.action_type == "USER_APPROVED"
    assert log_entry.action_details["category"] == "ACCOUNT"
    assert log_entry.action_details["outcome"] == "SUCCESS"
    assert log_entry.action_details["summary"] == "Approved user employee@intellibreak.com"

    # 3. Authenticate and retrieve audit logs via API
    response = test_client.post(
        "/auth/login",
        json={"email": "audit_admin@intellibreak.com", "password": "AdminPass123!"},
    )
    assert response.status_code == 200
    token = response.json()["access_token"]

    headers = {"Authorization": f"Bearer {token}"}

    # Get all logs
    res = test_client.get("/admin/audit-logs", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert len(data) >= 1

    logged_item = next((item for item in data if item["action_type"] == "USER_APPROVED"), None)
    assert logged_item is not None
    assert logged_item["category"] == "ACCOUNT"
    assert logged_item["outcome"] == "SUCCESS"
    assert logged_item["target_display_label"] == "employee@intellibreak.com"
    assert logged_item["action_details"]["department"] == "Engineering"

    # Test filtering by category
    res_cat = test_client.get("/admin/audit-logs?category=ACCOUNT", headers=headers)
    assert res_cat.status_code == 200
    assert any(item["action_type"] == "USER_APPROVED" for item in res_cat.json())

    # Test filtering by outcome
    res_out = test_client.get("/admin/audit-logs?outcome=SUCCESS", headers=headers)
    assert res_out.status_code == 200
    assert any(item["action_type"] == "USER_APPROVED" for item in res_out.json())

    # Test search query
    res_search = test_client.get("/admin/audit-logs?search=employee@intellibreak.com", headers=headers)
    assert res_search.status_code == 200
    assert any(item["action_type"] == "USER_APPROVED" for item in res_search.json())


def test_legacy_audit_log_compatibility(test_client: TestClient, db: Session):
    # Create admin user
    admin_user = User(
        email="legacy_admin@intellibreak.com",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Legacy Admin",
        role="ADMIN",
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    organization = Organization(name="Legacy Audit Org")
    db.add(organization)
    db.commit()
    db.add(OrganizationMembership(user_id=admin_user.id, organization_id=organization.id, role="ADMIN", status="APPROVED"))
    db.commit()

    # Insert a legacy log with null/empty action_details directly
    legacy_log = SystemActivityLog(
        user_id=admin_user.id,
        action_type="LEGACY_ACTION",
        action_details=None,
        ip_address=None,
        user_agent=None
    )
    db.add(legacy_log)
    db.commit()

    response = test_client.post(
        "/auth/login",
        json={"email": "legacy_admin@intellibreak.com", "password": "AdminPass123!"},
    )
    token = response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    res = test_client.get("/admin/audit-logs?action_type=LEGACY_ACTION", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert len(data) == 1
    item = data[0]
    assert item["action_type"] == "LEGACY_ACTION"
    assert item["category"] == "SYSTEM"  # fallback default
    assert item["outcome"] == "UNKNOWN"  # fallback default for legacy events without recorded outcome
    assert item["summary"] == "Legacy Action"  # fallback default title


def test_auth_audit_events(test_client: TestClient, db: Session):
    # 1. Create test user
    user = User(
        email="auth_audit_user@intellibreak.com",
        password_hash=get_password_hash("ValidPass123!"),
        full_name="Auth Audit User",
        role="EMPLOYEE",
        approval_status="APPROVED",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    # 2. Trigger failed login
    fail_res = test_client.post(
        "/auth/login",
        json={"email": "auth_audit_user@intellibreak.com", "password": "WrongPassword!"}
    )
    assert fail_res.status_code == 401

    # 3. Trigger successful login
    success_res = test_client.post(
        "/auth/login",
        json={"email": "auth_audit_user@intellibreak.com", "password": "ValidPass123!"}
    )
    assert success_res.status_code == 200
    token = success_res.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 4. Trigger logout
    logout_res = test_client.post("/auth/logout", headers=headers)
    assert logout_res.status_code == 200

    # Give the login target a tenant so its authentication events are visible to the admin.
    organization = Organization(name="Auth Audit Org")
    db.add(organization)
    db.commit()
    db.add(OrganizationMembership(user_id=user.id, organization_id=organization.id, role="EMPLOYEE", status="APPROVED"))
    db.commit()

    # 5. Verify via Admin Audit Logs API
    # Create admin for retrieval
    admin_user = User(
        email="auth_audit_admin@intellibreak.com",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Auth Audit Admin",
        role="ADMIN",
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    db.add(OrganizationMembership(user_id=admin_user.id, organization_id=organization.id, role="ADMIN", status="APPROVED"))
    db.commit()

    admin_login = test_client.post(
        "/auth/login",
        json={"email": "auth_audit_admin@intellibreak.com", "password": "AdminPass123!"}
    )
    admin_token = admin_login.json()["access_token"]
    admin_headers = {"Authorization": f"Bearer {admin_token}"}

    logs_res = test_client.get("/admin/audit-logs?category=SECURITY", headers=admin_headers)
    assert logs_res.status_code == 200
    logs = logs_res.json()

    # Unauthenticated failed logins have no actor organization and are intentionally omitted.
    action_types = [l["action_type"] for l in logs]
    assert "LOGIN_FAILED" not in action_types
    assert "LOGIN_SUCCESS" in action_types
    assert "LOGOUT" in action_types

    success_item = next(l for l in logs if l["action_type"] == "LOGIN_SUCCESS" and l["target_display_label"] == "auth_audit_user@intellibreak.com")
    assert success_item["outcome"] == "SUCCESS"
    assert success_item["target_display_label"] == "auth_audit_user@intellibreak.com"

    logout_item = next(l for l in logs if l["action_type"] == "LOGOUT" and l["target_display_label"] == "auth_audit_user@intellibreak.com")
    assert logout_item["outcome"] == "SUCCESS"
    assert logout_item["target_display_label"] == "auth_audit_user@intellibreak.com"


def test_admin_accountability_audit_events(test_client: TestClient, db: Session):
    # 1. Create organization and admin user
    org = Organization(name="AuditCorp")
    db.add(org)
    db.commit()
    db.refresh(org)

    admin_user = User(
        email="accountability_admin@intellibreak.com",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Accountability Admin",
        role="ADMIN",
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    db.add(OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    db.commit()

    admin_login = test_client.post(
        "/auth/login",
        json={"email": "accountability_admin@intellibreak.com", "password": "AdminPass123!"}
    )
    token = admin_login.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 2. Create a manager (triggers USER_CREATED)
    mgr_res = test_client.post(
        "/admin/managers",
        json={
            "email": "new_manager@intellibreak.com",
            "full_name": "New Manager",
            "organization_id": str(org.id)
        },
        headers=headers
    )
    assert mgr_res.status_code == 201
    mgr_id = mgr_res.json()["id"]

    # 3. Create an employee and access wellbeing & recommendations
    emp = User(
        email="employee_target@intellibreak.com",
        password_hash=get_password_hash("EmpPass123!"),
        full_name="Employee Target",
        role="EMPLOYEE",
        approval_status="APPROVED",
    )
    db.add(emp)
    db.commit()
    db.refresh(emp)

    emp_membership = OrganizationMembership(
        user_id=emp.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db.add(emp_membership)
    db.commit()

    # Access wellbeing
    wellbeing_res = test_client.get(f"/admin/users/{emp.id}/wellbeing", headers=headers)
    assert wellbeing_res.status_code == 200

    # Access recommendations
    rec_res = test_client.get(f"/admin/users/{emp.id}/recommendations", headers=headers)
    assert rec_res.status_code == 200

    # 4. Verify audit logs via GET /admin/audit-logs
    logs_res = test_client.get("/admin/audit-logs", headers=headers)
    assert logs_res.status_code == 200
    logs = logs_res.json()

    action_types = [l["action_type"] for l in logs]
    assert "USER_CREATED" in action_types
    assert "ADMIN_ACCESSED_WELLBEING" in action_types
    assert "ADMIN_ACCESSED_RECOMMENDATIONS" in action_types

    user_created_log = next(l for l in logs if l["action_type"] == "USER_CREATED")
    assert user_created_log["category"] == "ACCOUNT"
    assert user_created_log["outcome"] == "SUCCESS"
    assert user_created_log["target_display_label"] == "new_manager@intellibreak.com"

    wellbeing_log = next(l for l in logs if l["action_type"] == "ADMIN_ACCESSED_WELLBEING")
    assert wellbeing_log["category"] == "DATA_ACCESS"
    assert wellbeing_log["outcome"] == "SUCCESS"
    assert wellbeing_log["target_display_label"] == "employee_target@intellibreak.com"

    rec_log = next(l for l in logs if l["action_type"] == "ADMIN_ACCESSED_RECOMMENDATIONS")
    assert rec_log["category"] == "DATA_ACCESS"
    assert rec_log["outcome"] == "SUCCESS"
    assert rec_log["target_display_label"] == "employee_target@intellibreak.com"


def test_audit_log_immutability(db: Session):
    # Create audit log entry
    log_entry = log_system_activity(
        db=db,
        user_id=None,
        action_type="TEST_IMMUTABILITY",
        category="SECURITY",
        outcome="SUCCESS",
        summary="Testing immutability"
    )
    db.commit()

    # Query fresh from session and attempt update -> should raise RuntimeError
    fetched = db.query(SystemActivityLog).filter_by(action_type="TEST_IMMUTABILITY").first()
    fetched.action_type = "HACKED"
    with pytest.raises(Exception) as excinfo:
        db.commit()
    db.rollback()
    assert "append-only" in str(excinfo.value) or "modified" in str(excinfo.value)

    # Attempt delete -> should raise RuntimeError
    fetched_del = db.query(SystemActivityLog).filter_by(action_type="TEST_IMMUTABILITY").first()
    db.delete(fetched_del)
    with pytest.raises(Exception) as excinfo_del:
        db.commit()
    db.rollback()
    assert "append-only" in str(excinfo_del.value) or "deleted" in str(excinfo_del.value)


def test_audit_log_summary_endpoint(test_client: TestClient, db: Session):
    admin_user = User(
        email="summary_admin@intellibreak.com",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Summary Admin",
        role="ADMIN",
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    organization = Organization(name="Summary Audit Org")
    db.add(organization)
    db.commit()
    db.add(OrganizationMembership(user_id=admin_user.id, organization_id=organization.id, role="ADMIN", status="APPROVED"))
    db.commit()

    log_system_activity(
        db=db,
        user_id=admin_user.id,
        action_type="LOGIN_SUCCESS",
        category="SECURITY",
        outcome="SUCCESS",
        summary="Successful login"
    )
    log_system_activity(
        db=db,
        user_id=admin_user.id,
        action_type="LOGIN_FAILED",
        category="SECURITY",
        outcome="FAILURE",
        summary="Failed login"
    )
    db.commit()

    response = test_client.post(
        "/auth/login",
        json={"email": "summary_admin@intellibreak.com", "password": "AdminPass123!"},
    )
    token = response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    res = test_client.get("/admin/audit-logs/summary", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert data["total_events"] >= 2
    assert data["auth_security_events"] >= 2
    assert data["failed_events"] >= 1
    assert data["earliest_date"] is not None
    assert data["latest_date"] is not None




