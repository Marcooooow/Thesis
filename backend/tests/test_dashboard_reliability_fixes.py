"""
Tests for Production Dashboard Reliability Fixes:
1. Stale Active Work Session Auto-Closing (Scheduler / Max Shift Duration Policy)
2. Wellness Coach Endpoint / Response Adaptation
"""

import pytest
from sqlalchemy.orm import Session
from datetime import datetime, timezone, timedelta
import uuid

from app.models import WorkSession, Profile, User, SystemActivityLog
from app.scheduler import auto_close_stale_sessions
from app.auth.security import get_password_hash
from app.services.wlb_analysis_service import WLBAnalysisService

def test_stale_session_auto_close_policy(test_db: Session):
    """
    Test that active work sessions exceeding the 16-hour threshold are automatically closed
    by the scheduler, while recent or normal sessions remain active.
    """
    user = User(
        email="reliability_test@example.com",
        password_hash=get_password_hash("password123"),
        full_name="Reliability Test User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = Profile(
        user_id=user.id,
        job_role="Engineer"
    )
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    now = datetime.now(timezone.utc)

    recent_session = WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=2),
        ended_at=None
    )

    medium_session = WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=10),
        ended_at=None
    )

    stale_session = WorkSession(
        profile_id=profile.id,
        started_at=now - timedelta(hours=18),
        ended_at=None
    )

    test_db.add_all([recent_session, medium_session, stale_session])
    test_db.commit()

    # Run auto-close scheduler function with test_db session
    auto_close_stale_sessions(test_db)

    test_db.expire_all()

    assert test_db.query(WorkSession).filter(WorkSession.id == recent_session.id).first().ended_at is None
    assert test_db.query(WorkSession).filter(WorkSession.id == medium_session.id).first().ended_at is None

    closed_stale = test_db.query(WorkSession).filter(WorkSession.id == stale_session.id).first()
    assert closed_stale.ended_at is not None
    expected_end = stale_session.started_at + timedelta(hours=16)
    assert closed_stale.ended_at == expected_end

    audit_log = test_db.query(SystemActivityLog).filter(
        SystemActivityLog.action_type == "WORK_SESSION_SYSTEM_AUTO_CLOSED"
    ).first()
    assert audit_log is not None
    assert audit_log.action_details["reason"] == "max_shift_duration_exceeded_16h"

    # Idempotency test
    auto_close_stale_sessions(test_db)
    assert test_db.query(WorkSession).filter(WorkSession.id == stale_session.id).first().ended_at == expected_end

def test_wlb_analysis_service_summary(test_db: Session):
    """
    Test that WLB analysis service provides expected fields for wellness coach summary.
    """
    user = User(
        email="wlb_summary_test@example.com",
        password_hash=get_password_hash("password123"),
        full_name="WLB Summary User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    profile = Profile(
        user_id=user.id,
        job_role="Analyst"
    )
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    today = datetime.now(timezone.utc).date()
    monday = today - timedelta(days=today.weekday())

    service = WLBAnalysisService(test_db)
    analysis = service.get_weekly_wlb_analysis(profile.id, monday)

    assert "has_survey" in analysis
    assert "risk_tier" in analysis
    assert "risk_label" in analysis
    assert "behavioral_indicators" in analysis
    assert "recommendations" in analysis
