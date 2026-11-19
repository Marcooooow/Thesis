import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app.database import Base, engine, SessionLocal
from app import models
import uuid

client = TestClient(app)

@pytest.fixture
def admin_db(test_db: Session):
    yield test_db

@pytest.fixture
def admin_token(admin_db):
    admin = models.User(
        email="admin_reg@test.com",
        full_name="Reg Admin",
        role="ADMIN",
        account_type="organization",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("adminpass"),
    )
    admin_db.add(admin)
    admin_db.commit()
    admin_db.refresh(admin)
    # Profile needed for org membership queries
    profile = models.Profile(user_id=admin.id, target_daily_hours=8)
    admin_db.add(profile)
    # Organization
    org = models.Organization(name="RegTestOrg")
    admin_db.add(org)
    admin_db.commit()
    admin_db.refresh(org)
    # Membership
    mem = models.OrganizationMembership(
        user_id=admin.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED",
    )
    admin_db.add(mem)
    admin_db.commit()
    return create_access_token(data={"sub": admin.email})

def test_regression_admin_weekly_work_hours(admin_token):
    response = client.get(
        "/analytics/admin/weekly/work-hours",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 7
    for item in data:
        assert "day" in item
        assert "actualHours" in item
        assert "targetHours" in item
