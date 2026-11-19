import uuid
import pytest
from datetime import date
from sqlalchemy import func

from app.models import User, Organization, OrganizationMembership, WorkSession, Break, Task, RecommendationFeedback, SessionWellbeingCheckin, Profile
from app.services.historical_behavioral_generator import generate_historical_behavioral_dataset


def test_generator_repeated_execution_idempotency(test_db):
    admin = User(
        email=f"idemp-admin-{uuid.uuid4()}@test.local",
        full_name="Idempotency Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name=f"Idempotent Test Org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # First run (Oct 1 - Oct 3, 2026)
    summary1 = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 10, 1),
        end_date=date(2026, 10, 3),
        num_managers=2,
        num_employees=5,
        num_teams=2,
    )

    counts_run1 = {
        'work_sessions': test_db.query(WorkSession).count(),
        'breaks': test_db.query(Break).count(),
        'tasks': test_db.query(Task).count(),
        'feedback': test_db.query(RecommendationFeedback).count(),
        'checkins': test_db.query(SessionWellbeingCheckin).count(),
    }

    # Second identical run (should add zero duplicate records due to date check)
    summary2 = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 10, 1),
        end_date=date(2026, 10, 3),
        num_managers=2,
        num_employees=5,
        num_teams=2,
    )

    counts_run2 = {
        'work_sessions': test_db.query(WorkSession).count(),
        'breaks': test_db.query(Break).count(),
        'tasks': test_db.query(Task).count(),
        'feedback': test_db.query(RecommendationFeedback).count(),
        'checkins': test_db.query(SessionWellbeingCheckin).count(),
    }

    assert counts_run1 == counts_run2
    assert counts_run1['work_sessions'] > 0
