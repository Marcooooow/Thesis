"""
Phase 4 Step 4: Organization Wellbeing Statistics — Gap 1 Tests
Daily and Weekly Wellbeing Trends with UTC boundary handling
"""
import pytest
from datetime import datetime, timezone, timedelta, date
import uuid
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.models import (
    Base, User, Profile, Organization, OrganizationMembership,
    SessionWellbeingCheckin, WorkSession
)
from app.services.wellbeing_monitoring import WellbeingMonitoringService


@pytest.fixture
def db_session():
    """Create in-memory SQLite database for testing."""
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()


@pytest.fixture
def test_org(db_session):
    """Create test organization."""
    org = Organization(
        id=uuid.uuid4(),
        name="Test Organization"
    )
    db_session.add(org)
    db_session.commit()
    return org


@pytest.fixture
def test_employees(db_session, test_org):
    """Create 3 test employees."""
    employees = []
    for i in range(3):
        user = User(
            id=uuid.uuid4(),
            email=f"emp{i}@test.com",
            password_hash="hash",
            full_name=f"Employee {i}",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True
        )
        db_session.add(user)
        db_session.flush()

        profile = Profile(
            id=uuid.uuid4(),
            user_id=user.id,
            is_test_data=False
        )
        db_session.add(profile)
        db_session.flush()

        org_mem = OrganizationMembership(
            id=uuid.uuid4(),
            user_id=user.id,
            organization_id=test_org.id,
            role="EMPLOYEE",
            status="APPROVED"
        )
        db_session.add(org_mem)
        db_session.flush()

        employees.append({"user": user, "profile": profile})

    db_session.commit()
    return employees


def test_daily_wellbeing_trends_single_day(db_session, test_employees):
    """Test daily aggregation for a single day with multiple check-ins."""
    profile_id = test_employees[0]["profile"].id
    user_id = test_employees[0]["user"].id

    today = datetime.now(timezone.utc)

    # Create multiple work sessions (one per check-in, since SessionWellbeingCheckin has UNIQUE work_session_id)
    checkins_data = [
        (3, 2, 3, 4, 2),  # overall, fatigue, workload, focus, recovery
        (4, 2, 3, 4, 3),
        (3, 3, 2, 3, 2),
    ]

    for idx, (overall, fatigue, workload, focus, recovery) in enumerate(checkins_data):
        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=today + timedelta(hours=idx*2),
            ended_at=today + timedelta(hours=idx*2 + 1)
        )
        db_session.add(session)
        db_session.flush()

        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=overall,
            mental_fatigue=fatigue,
            workload_manageability=workload,
            perceived_focus=focus,
            break_recovery=recovery,
            created_at=today + timedelta(hours=idx*2 + 0.5)
        )
        db_session.add(checkin)

    db_session.commit()

    # Compute daily trends
    wb_service = WellbeingMonitoringService(db_session)
    start = datetime.combine(today.date(), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today.date(), datetime.max.time(), tzinfo=timezone.utc)

    trends = wb_service.compute_daily_wellbeing_trends([profile_id], start, end)

    # Verify
    assert len(trends) == 1
    daily = trends[0]
    assert daily["date"] == today.date()
    assert daily["checkin_count"] == 3

    # Verify averages
    assert daily["overall_wellbeing"] == pytest.approx(3.33, rel=0.01)
    assert daily["mental_fatigue"] == pytest.approx(2.33, rel=0.01)
    assert daily["workload_manageability"] == pytest.approx(2.67, rel=0.01)
    assert daily["perceived_focus"] == pytest.approx(3.67, rel=0.01)
    assert daily["break_recovery"] == pytest.approx(2.33, rel=0.01)


def test_daily_wellbeing_trends_multiple_days(db_session, test_employees):
    """Test daily aggregation across multiple days."""
    profile_id = test_employees[0]["profile"].id
    user_id = test_employees[0]["user"].id

    base_date = datetime.now(timezone.utc)

    # Create check-ins for 3 consecutive days
    for day_offset in range(3):
        current_day = base_date + timedelta(days=day_offset)

        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=current_day,
            ended_at=current_day + timedelta(hours=1)
        )
        db_session.add(session)
        db_session.flush()

        base_score = 2 + day_offset
        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=base_score,
            mental_fatigue=base_score - 1,
            workload_manageability=base_score,
            perceived_focus=base_score + 1,
            break_recovery=base_score - 1,
            created_at=current_day + timedelta(hours=0.5)
        )
        db_session.add(checkin)

    db_session.commit()

    # Compute daily trends
    wb_service = WellbeingMonitoringService(db_session)
    start = datetime.combine(base_date.date(), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine((base_date + timedelta(days=2)).date(), datetime.max.time(), tzinfo=timezone.utc)

    trends = wb_service.compute_daily_wellbeing_trends([profile_id], start, end)

    # Verify
    assert len(trends) == 3

    # Check dates are in order
    for i, daily in enumerate(trends):
        expected_date = (base_date + timedelta(days=i)).date()
        assert daily["date"] == expected_date
        assert daily["checkin_count"] == 1


def test_daily_wellbeing_trends_multiple_employees(db_session, test_employees):
    """Test daily aggregation across multiple employees."""
    base_date = datetime.now(timezone.utc)

    # Create check-ins for 2 employees on same day
    for emp_idx in range(2):
        profile_id = test_employees[emp_idx]["profile"].id
        user_id = test_employees[emp_idx]["user"].id

        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=base_date,
            ended_at=base_date + timedelta(hours=1)
        )
        db_session.add(session)
        db_session.flush()

        # Each employee has check-in with different score
        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=2 + emp_idx,  # 2, 3
            mental_fatigue=2,
            workload_manageability=3,
            perceived_focus=4,
            break_recovery=2,
            created_at=base_date + timedelta(hours=0.5)
        )
        db_session.add(checkin)

    db_session.commit()

    # Compute daily trends for both employees
    profile_ids = [test_employees[i]["profile"].id for i in range(2)]
    wb_service = WellbeingMonitoringService(db_session)
    start = datetime.combine(base_date.date(), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(base_date.date(), datetime.max.time(), tzinfo=timezone.utc)

    trends = wb_service.compute_daily_wellbeing_trends(profile_ids, start, end)

    # Verify
    assert len(trends) == 1
    daily = trends[0]
    assert daily["checkin_count"] == 2
    assert daily["overall_wellbeing"] == 2.5  # (2 + 3) / 2


def test_weekly_wellbeing_trends_single_week(db_session, test_employees):
    """Test weekly aggregation for a single week."""
    profile_id = test_employees[0]["profile"].id
    user_id = test_employees[0]["user"].id

    # Start on a Monday
    monday = datetime.now(timezone.utc)
    monday = monday - timedelta(days=monday.weekday())  # Move to Monday

    # Create check-ins for each day of the week
    for day_offset in range(5):  # Mon-Fri
        current_day = monday + timedelta(days=day_offset)

        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=current_day,
            ended_at=current_day + timedelta(hours=1)
        )
        db_session.add(session)
        db_session.flush()

        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=3,
            mental_fatigue=2,
            workload_manageability=3,
            perceived_focus=4,
            break_recovery=2,
            created_at=current_day + timedelta(hours=0.5)
        )
        db_session.add(checkin)

    db_session.commit()

    # Compute weekly trends
    profile_ids = [profile_id]
    wb_service = WellbeingMonitoringService(db_session)
    start = datetime.combine(monday.date(), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine((monday + timedelta(days=6)).date(), datetime.max.time(), tzinfo=timezone.utc)

    trends = wb_service.compute_weekly_wellbeing_trends(profile_ids, start, end)

    # Verify
    assert len(trends) == 1
    weekly = trends[0]
    assert weekly["week_start"] == monday.date()
    assert weekly["day_count"] == 5
    assert weekly["overall_wellbeing"] == 3.0
    assert weekly["mental_fatigue"] == 2.0
    assert "risk_distribution" in weekly


def test_weekly_wellbeing_trends_multiple_weeks(db_session, test_employees):
    """Test weekly aggregation across multiple weeks."""
    profile_id = test_employees[0]["profile"].id
    user_id = test_employees[0]["user"].id

    # Start on a Monday 2 weeks ago
    today = datetime.now(timezone.utc)
    monday = today - timedelta(days=today.weekday())
    start_monday = monday - timedelta(weeks=2)

    # Create check-ins for 3 consecutive weeks
    for week_offset in range(3):
        week_start = start_monday + timedelta(weeks=week_offset)

        # Create 2 check-ins per week (Mon and Wed)
        for day_offset in [0, 2]:
            current_day = week_start + timedelta(days=day_offset)

            session = WorkSession(
                id=uuid.uuid4(),
                profile_id=profile_id,
                started_at=current_day,
                ended_at=current_day + timedelta(hours=1)
            )
            db_session.add(session)
            db_session.flush()

            # Vary scores by week
            base_score = 2 + week_offset
            checkin = SessionWellbeingCheckin(
                id=uuid.uuid4(),
                user_id=user_id,
                work_session_id=session.id,
                overall_wellbeing=base_score,
                mental_fatigue=base_score - 1,
                workload_manageability=base_score,
                perceived_focus=base_score + 1,
                break_recovery=base_score - 1,
                created_at=current_day + timedelta(hours=0.5)
            )
            db_session.add(checkin)

    db_session.commit()

    # Compute weekly trends
    profile_ids = [profile_id]
    wb_service = WellbeingMonitoringService(db_session)
    start = datetime.combine(start_monday.date(), datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine((start_monday + timedelta(weeks=3)).date(), datetime.max.time(), tzinfo=timezone.utc)

    trends = wb_service.compute_weekly_wellbeing_trends(profile_ids, start, end)

    # Verify
    assert len(trends) == 3

    # Check weeks are in order
    for i, weekly in enumerate(trends):
        expected_week_start = (start_monday + timedelta(weeks=i)).date()
        assert weekly["week_start"] == expected_week_start


def test_empty_period_returns_empty_trends(db_session, test_employees):
    """Test that querying a period with no data returns empty trends."""
    profile_id = test_employees[0]["profile"].id

    # Query a future date range with no check-ins
    future_start = datetime.now(timezone.utc) + timedelta(days=30)
    future_end = future_start + timedelta(days=7)

    wb_service = WellbeingMonitoringService(db_session)
    daily_trends = wb_service.compute_daily_wellbeing_trends([profile_id], future_start, future_end)
    weekly_trends = wb_service.compute_weekly_wellbeing_trends([profile_id], future_start, future_end)

    # Verify
    assert daily_trends == []
    assert weekly_trends == []


def test_participation_rate_calculation(db_session, test_org, test_employees):
    """Test check-in participation rate calculation."""
    base_date = datetime.now(timezone.utc)

    # Employee 0: 1 check-in
    # Employee 1: 1 check-in
    # Employee 2: no check-ins

    for emp_idx in range(2):
        profile_id = test_employees[emp_idx]["profile"].id
        user_id = test_employees[emp_idx]["user"].id

        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=base_date,
            ended_at=base_date + timedelta(hours=1)
        )
        db_session.add(session)
        db_session.flush()

        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=3,
            mental_fatigue=2,
            workload_manageability=3,
            perceived_focus=4,
            break_recovery=2,
            created_at=base_date + timedelta(hours=0.5)
        )
        db_session.add(checkin)

    db_session.commit()

    # Query all check-ins and compute participation
    checkins = db_session.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.created_at >= datetime.combine(base_date.date(), datetime.min.time(), tzinfo=timezone.utc),
        SessionWellbeingCheckin.created_at <= datetime.combine(base_date.date(), datetime.max.time(), tzinfo=timezone.utc)
    ).all()

    # Calculate participation
    unique_participants = len(set(c.user_id for c in checkins))
    total_employees = len(test_employees)
    participation_rate = (unique_participants / total_employees * 100) if total_employees > 0 else 0

    # Verify: 2 out of 3 employees = 66.67%
    assert unique_participants == 2
    assert participation_rate == pytest.approx(66.67, rel=0.01)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
