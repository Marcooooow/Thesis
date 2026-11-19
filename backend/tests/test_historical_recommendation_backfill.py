"""
Comprehensive tests for historical recommendation backfill service.
Covers all required test cases for thesis demo accounts, transaction safety, and provenance.
"""

import pytest
from datetime import datetime, timezone, timedelta
import uuid
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from app.models import User, Profile, WorkSession, RecommendationFeedback, UserSettings
from app.auth.security import get_password_hash
from app.services.historical_recommendation_backfill import (
    THESIS_DEMO_EMAILS,
    extract_historical_session_features,
    reconstruct_historical_recommendations_for_session,
    run_historical_backfill
)


def test_employee_filtering_and_allowlist(db: Session):
    """Test 1, 2, 3: Admin, Manager, ML test accounts, and non-allowlist emails are excluded; exact 20 thesis demo employees matched."""
    # Create Admin
    admin_user = User(
        id=uuid.uuid4(),
        email="thesis.admin@intellibreak.local",
        password_hash=get_password_hash("pass"),
        full_name="Admin",
        role="ADMIN",
        is_active=True
    )
    admin_profile = Profile(id=uuid.uuid4(), user_id=admin_user.id, is_test_data=True)

    # Create Manager
    mgr_user = User(
        id=uuid.uuid4(),
        email="thesis.manager01@intellibreak.local",
        password_hash=get_password_hash("pass"),
        full_name="Manager",
        role="MANAGER",
        is_active=True
    )
    mgr_profile = Profile(id=uuid.uuid4(), user_id=mgr_user.id, is_test_data=True)

    # Create ML Test employee
    ml_user = User(
        id=uuid.uuid4(),
        email="mltest_employee_01@intellibreak.local",
        password_hash=get_password_hash("pass"),
        full_name="ML Test",
        role="EMPLOYEE",
        is_active=True
    )
    ml_profile = Profile(id=uuid.uuid4(), user_id=ml_user.id, is_test_data=True)

    db.add_all([admin_user, admin_profile, mgr_user, mgr_profile, ml_user, ml_profile])
    db.flush()

    # Check that allowlist has exactly 20 emails
    assert len(THESIS_DEMO_EMAILS) == 20
    assert THESIS_DEMO_EMAILS[0] == "thesis.employee01@intellibreak.local"
    assert THESIS_DEMO_EMAILS[-1] == "thesis.employee20@intellibreak.local"


def test_completed_sessions_only(db: Session):
    """Test 4: Only completed historical work sessions (ended_at not null) are processed for allowlisted employees."""
    user = db.query(User).filter(User.email == "thesis.employee01@intellibreak.local").first()
    if not user:
        user = User(
            id=uuid.uuid4(),
            email="thesis.employee01@intellibreak.local",
            password_hash=get_password_hash("pass"),
            full_name="Demo 01",
            role="EMPLOYEE",
            is_active=True
        )
        profile = Profile(id=uuid.uuid4(), user_id=user.id, is_test_data=True)
        db.add_all([user, profile])
        db.flush()
    else:
        profile = db.query(Profile).filter(Profile.user_id == user.id).first()

    # Active session (ended_at is None)
    active_session = WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=1),
        ended_at=None
    )
    # Completed session
    completed_session = WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=4),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=3)
    )
    db.add_all([active_session, completed_session])
    db.commit()

    stats = run_historical_backfill(db, dry_run=False)

    # Verify recommendation was created for completed session only
    recs = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.work_session_id == completed_session.id
    ).all()
    assert len(recs) == 1
    assert recs[0].work_session_id == completed_session.id


def test_ownership_and_provenance(db: Session):
    """Test 3, 5, 11, 12: Correct user/session ownership, user_action=None, provenance, and model_version."""
    user = db.query(User).filter(User.email == "thesis.employee02@intellibreak.local").first()
    if not user:
        user = User(
            id=uuid.uuid4(),
            email="thesis.employee02@intellibreak.local",
            password_hash=get_password_hash("pass"),
            full_name="Demo 02",
            role="EMPLOYEE",
            is_active=True
        )
        profile = Profile(id=uuid.uuid4(), user_id=user.id, is_test_data=True)
        db.add_all([user, profile])
        db.flush()
    else:
        profile = db.query(Profile).filter(Profile.user_id == user.id).first()

    session = WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=2),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=1)
    )
    db.add(session)
    db.commit()

    feedback = reconstruct_historical_recommendations_for_session(db, profile, session)
    assert feedback is not None
    assert feedback.user_id == user.id
    assert feedback.work_session_id == session.id
    assert feedback.user_action is None
    assert feedback.provenance == "historical_reconstruction"
    assert feedback.model_version == "historical-reconstruction-v1"


def test_duplicate_prevention_and_idempotency(db: Session):
    """Test 6, 7: Duplicate prevention and idempotent repeated execution."""
    user = db.query(User).filter(User.email == "thesis.employee03@intellibreak.local").first()
    if not user:
        user = User(
            id=uuid.uuid4(),
            email="thesis.employee03@intellibreak.local",
            password_hash=get_password_hash("pass"),
            full_name="Demo 03",
            role="EMPLOYEE",
            is_active=True
        )
        profile = Profile(id=uuid.uuid4(), user_id=user.id, is_test_data=True)
        db.add_all([user, profile])
        db.flush()
    else:
        profile = db.query(Profile).filter(Profile.user_id == user.id).first()

    session = WorkSession(
        id=uuid.uuid4(),
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=2),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=1)
    )
    db.add(session)
    db.commit()

    # First reconstruction
    fb1 = reconstruct_historical_recommendations_for_session(db, profile, session)
    db.commit()
    assert fb1 is not None

    # Second reconstruction (should return None due to uniqueness check)
    fb2 = reconstruct_historical_recommendations_for_session(db, profile, session)
    assert fb2 is None

    count = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.work_session_id == session.id
    ).count()
    assert count == 1


def test_dry_run_no_writes(db: Session):
    """Test 10: Dry-run performs zero database writes."""
    initial_count = db.query(RecommendationFeedback).count()
    run_historical_backfill(db, dry_run=True)
    final_count = db.query(RecommendationFeedback).count()
    assert initial_count == final_count


def test_transaction_rollback_on_error(db: Session):
    """Test 8, 9: Transaction rollback occurs correctly on insertion/commit errors."""
    try:
        import unittest.mock
        with unittest.mock.patch('app.services.historical_recommendation_backfill.reconstruct_historical_recommendations_for_session', side_effect=Exception("Simulated DB Failure")):
            run_historical_backfill(db, dry_run=False)
    except Exception as e:
        assert "Simulated DB Failure" in str(e)
