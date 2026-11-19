import uuid
import pytest
from datetime import date
from sqlalchemy import func

from app.models import User, Organization, OrganizationMembership, WorkSession, Break, Task, RecommendationFeedback, SessionWellbeingCheckin, Profile
from app.services.historical_behavioral_generator import generate_historical_behavioral_dataset


def test_generate_historical_behavioral_dataset(test_db):
    admin = User(
        email=f"history-admin-{uuid.uuid4()}@test.local",
        full_name="History Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name=f"Historical Org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Generate short date range for fast test execution (e.g. 5 days)
    summary = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 10, 1),
        end_date=date(2026, 10, 5),
        num_employees=20,
    )

    assert summary["total_employees"] == 20
    recs = summary["records_generated"]
    assert recs["work_sessions"] > 0
    assert recs["breaks"] > 0
    assert recs["tasks"] > 0
    assert recs["recommendation_feedback"] > 0
    assert recs["wellbeing_checkins"] > 0

    # Verify ML data isolation flag on synthetic feedback and profiles
    feedbacks = test_db.query(RecommendationFeedback).all()
    for f in feedbacks:
        assert f.context_features.get("is_test_data") is True
        assert f.context_features.get("dev_demo") is True

    profiles = test_db.query(Profile).join(User, Profile.user_id == User.id).filter(User.role == "EMPLOYEE").all()
    for p in profiles:
        assert p.is_test_data is True
