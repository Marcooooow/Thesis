import uuid
import pytest
from datetime import date
from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import User, Organization, OrganizationMembership, WorkSession, Break, Task, Recommendation, RecommendationFeedback, SessionWellbeingCheckin, Profile
from app.services.production_guard import verify_production_target
from app.services.historical_behavioral_generator import generate_historical_behavioral_dataset
from tests.conftest import _fix_sqlite_incompatibility


def test_production_guard_rejects_wrong_project_username():
    wrong_user_url = "postgresql://postgres.wrongproject:pass@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres?sslmode=require"
    with pytest.raises(RuntimeError, match="username does not contain expected Supabase project reference"):
        verify_production_target(wrong_user_url)


def test_production_guard_rejects_wrong_hostname():
    wrong_host_url = "postgresql://postgres.wwrwnpjsvtjotckqnsjt:pass@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require"
    with pytest.raises(RuntimeError, match="not the trusted Supabase pooler"):
        verify_production_target(wrong_host_url)


def test_production_guard_rejects_localhost():
    localhost_url = "postgresql://postgres.wwrwnpjsvtjotckqnsjt:pass@localhost:5432/postgres?sslmode=require"
    with pytest.raises(RuntimeError, match="Localhost/non-production hosts are rejected"):
        verify_production_target(localhost_url)


def test_production_guard_rejects_missing_ssl():
    insecure_url = "postgresql://postgres.wwrwnpjsvtjotckqnsjt:pass@aws-0-ap-southeast-2.pooler.supabase.com:5432/postgres"
    with pytest.raises(RuntimeError, match="Effective SSL mode"):
        verify_production_target(insecure_url)


def test_interrupted_run_recovery_and_bounded_transactions(test_db):
    _fix_sqlite_incompatibility()
    admin = User(
        email=f"recovery-admin-{uuid.uuid4()}@test.local",
        full_name="Recovery Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name=f"Recovery Org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    summary1 = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 10, 1),
        end_date=date(2026, 10, 1),
        num_managers=1,
        num_employees=3,
        num_teams=1,
    )
    assert summary1["records_generated"]["work_sessions"] > 0

    sessions = test_db.query(WorkSession).all()
    session_ids = [s.id for s in sessions]
    test_db.query(Break).filter(Break.work_session_id.in_(session_ids)).delete(synchronize_session=False)
    test_db.query(Task).filter(Task.work_session_id.in_(session_ids)).delete(synchronize_session=False)
    test_db.commit()

    assert test_db.query(Break).filter(Break.work_session_id.in_(session_ids)).count() == 0
    assert test_db.query(Task).filter(Task.work_session_id.in_(session_ids)).count() == 0

    summary2 = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 10, 1),
        end_date=date(2026, 10, 1),
        num_managers=1,
        num_employees=3,
        num_teams=1,
    )

    sessions_after = test_db.query(WorkSession).all()
    assert len(sessions_after) == len(sessions)
    assert test_db.query(Break).filter(Break.work_session_id.in_(session_ids)).count() > 0
    assert test_db.query(Task).filter(Task.work_session_id.in_(session_ids)).count() > 0
