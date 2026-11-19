import pytest
from datetime import date, datetime, timezone, timedelta
import uuid
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db
from app.auth.security import get_password_hash
from app import models

client = TestClient(app)

def test_wellbeing_endpoints_rbac_unauthorized(test_db):
    # Create employee user
    emp_user = models.User(
        email=f"emp_{uuid.uuid4()}@test.com",
        full_name="Regular Employee",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(emp_user)
    test_db.commit()

    # Login / token or dependency override
    # Since TestClient uses Depends(get_current_active_user), let's override or test with employee credentials
    from app.routers.auth import get_current_active_user
    app.dependency_overrides[get_current_active_user] = lambda: emp_user

    response = client.get("/manager/wellbeing/weekly")
    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_wellbeing_health_endpoint(test_db):
    mgr_user = models.User(
        email=f"mgr_{uuid.uuid4()}@test.com",
        full_name="Manager User",
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(mgr_user)
    test_db.commit()

    from app.routers.auth import get_current_active_user
    app.dependency_overrides[get_current_active_user] = lambda: mgr_user

    response = client.get("/manager/wellbeing/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "operational"
    assert "employees_monitored" in data

    app.dependency_overrides.clear()


def test_manager_access_unauthorized_employee(test_db):
    # Manager 1
    mgr1 = models.User(email=f"mgr1_{uuid.uuid4()}@test.com", full_name="Mgr One", role="MANAGER", approval_status="APPROVED", is_active=True, password_hash=get_password_hash("test"))
    # Employee in another team
    emp2 = models.User(email=f"emp2_{uuid.uuid4()}@test.com", full_name="Emp Two", role="EMPLOYEE", approval_status="APPROVED", is_active=True, password_hash=get_password_hash("test"))
    test_db.add_all([mgr1, emp2])
    test_db.commit()

    profile2 = models.Profile(user_id=emp2.id)
    test_db.add(profile2)
    test_db.commit()

    # Manager 1 tries to access emp2 detail without team membership
    from app.routers.auth import get_current_active_user
    app.dependency_overrides[get_current_active_user] = lambda: mgr1

    response = client.get(f"/manager/wellbeing/{profile2.id}/detail")
    assert response.status_code == 403

    app.dependency_overrides.clear()


def test_admin_access_wellbeing(test_db):
    admin_user = models.User(email=f"admin_{uuid.uuid4()}@test.com", full_name="Admin User", role="ADMIN", approval_status="APPROVED", is_active=True, password_hash=get_password_hash("test"))
    test_db.add(admin_user)
    test_db.commit()

    from app.routers.auth import get_current_active_user
    app.dependency_overrides[get_current_active_user] = lambda: admin_user

    response = client.get("/manager/wellbeing/weekly")
    assert response.status_code == 200

    app.dependency_overrides.clear()

