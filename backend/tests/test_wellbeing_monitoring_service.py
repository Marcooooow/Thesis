import pytest
from datetime import date, datetime, timezone, timedelta
import uuid
from app.services.wellbeing_monitoring import WellbeingMonitoringService
from app.schemas.wellbeing_monitoring import RiskTier, TrendDirection
from app import models
from app.auth.security import get_password_hash

def test_tier_0_insufficient_sessions(test_db):
    service = WellbeingMonitoringService(test_db)
    user = models.User(
        email=f"emp_{uuid.uuid4()}@test.com",
        full_name="Test Emp",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(user)
    test_db.commit()
    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    # 1 session only (<3)
    session = models.WorkSession(
        profile_id=profile.id,
        started_at=datetime(2026, 10, 26, 9, 0, tzinfo=timezone.utc),
        ended_at=datetime(2026, 10, 26, 17, 0, tzinfo=timezone.utc)
    )
    test_db.add(session)
    test_db.commit()

    detail = service.compute_weekly_risk(profile.id, date(2026, 10, 26))
    assert detail.risk_tier == RiskTier.INSUFFICIENT_DATA


def test_baseline_resolution_per_employee(test_db):
    service = WellbeingMonitoringService(test_db)
    user = models.User(
        email=f"emp_{uuid.uuid4()}@test.com",
        full_name="Test Emp 2",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(user)
    test_db.commit()

    # UserSettings with custom target hours 7.5
    settings = models.UserSettings(user_id=user.id, work_target_daily_hours=7.5)
    test_db.add(settings)
    test_db.commit()

    profile = models.Profile(user_id=user.id) # no profile target hours
    test_db.add(profile)
    test_db.commit()

    target = service._resolve_employee_target_hours(profile.id)
    assert target == 7.5


def test_privacy_no_raw_checkin_notes_exposed(test_db):
    service = WellbeingMonitoringService(test_db)
    user = models.User(
        email=f"emp_{uuid.uuid4()}@test.com",
        full_name="Test Emp 3",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(user)
    test_db.commit()
    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    # Create 3 sessions and 2 checkins with sensitive notes
    for i in range(3):
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=datetime(2026, 10, 26 + i, 9, 0, tzinfo=timezone.utc),
            ended_at=datetime(2026, 10, 26 + i, 17, 0, tzinfo=timezone.utc)
        )
        test_db.add(session)
        test_db.commit()
        if i < 2:
            checkin = models.SessionWellbeingCheckin(
                user_id=user.id,
                work_session_id=session.id,
                overall_wellbeing=4,
                mental_fatigue=3,
                workload_manageability=4,
                perceived_focus=4,
                break_recovery=3,
                stress_factors=["high_workload"],
                notes="Sensitive personal note that must never be exposed"
            )
            test_db.add(checkin)
            test_db.commit()

    detail = service.compute_weekly_risk(profile.id, date(2026, 10, 26))
    dumped = detail.model_dump()
    dumped_str = str(dumped)
    assert "Sensitive personal note" not in dumped_str
    assert "high_workload" not in dumped_str
    assert "notes" not in dumped_str
