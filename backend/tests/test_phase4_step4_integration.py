"""
Phase 4 Step 4: Gap 1 Integration Test
Verify daily and weekly wellbeing trends are included in admin organization analytics
"""
import pytest
from datetime import datetime, timezone, timedelta, date
import uuid
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.models import (
    Base, User, Profile, Organization, OrganizationMembership,
    SessionWellbeingCheckin, WorkSession, Team, TeamMembership
)
from app.services.admin_organization_report_service import AdminOrganizationReportService


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
def test_org_with_members(db_session):
    """Create test organization with admin user and employees."""
    org = Organization(
        id=uuid.uuid4(),
        name="Test Analytics Org"
    )
    db_session.add(org)
    db_session.flush()

    # Create admin user
    admin = User(
        id=uuid.uuid4(),
        email="admin@test.com",
        password_hash="hash",
        full_name="Admin User",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True
    )
    db_session.add(admin)
    db_session.flush()

    admin_mem = OrganizationMembership(
        id=uuid.uuid4(),
        user_id=admin.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db_session.add(admin_mem)
    db_session.flush()

    # Create employees with profiles
    employees = []
    for i in range(2):
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
            organization_id=org.id,
            role="EMPLOYEE",
            status="APPROVED"
        )
        db_session.add(org_mem)
        db_session.flush()

        employees.append({"user": user, "profile": profile})

    db_session.commit()
    return {"org": org, "admin": admin, "employees": employees}


def test_admin_analytics_includes_wellbeing_trends(db_session, test_org_with_members):
    """Test that admin analytics response includes daily and weekly wellbeing trends."""
    org_data = test_org_with_members
    org_id = org_data["org"].id
    admin_user = org_data["admin"]
    employees = org_data["employees"]

    # Create wellbeing check-ins for employees
    today = datetime.now(timezone.utc)

    for emp_idx, emp in enumerate(employees):
        profile_id = emp["profile"].id
        user_id = emp["user"].id

        # Create work session and check-in
        session = WorkSession(
            id=uuid.uuid4(),
            profile_id=profile_id,
            started_at=today,
            ended_at=today + timedelta(hours=8)
        )
        db_session.add(session)
        db_session.flush()

        # Vary wellbeing scores by employee
        base_score = 3 + emp_idx
        checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user_id,
            work_session_id=session.id,
            overall_wellbeing=base_score,
            mental_fatigue=2,
            workload_manageability=3,
            perceived_focus=4,
            break_recovery=2,
            created_at=today + timedelta(hours=4)
        )
        db_session.add(checkin)

    db_session.commit()

    # Get admin analytics
    service = AdminOrganizationReportService(db_session, admin_user)
    analytics = service._get_org_context(
        org_ids=[org_id],
        period="today",
        start_date=today.date(),
        end_date=today.date(),
        include_test=False,
        user_tz="UTC"
    )

    # Verify organizational_wellbeing section
    assert "organizational_wellbeing" in analytics
    wellbeing = analytics["organizational_wellbeing"]

    # Verify basic metrics
    assert wellbeing["checkin_count"] == 2
    assert "overall_wellbeing" in wellbeing
    assert "participation_rate" in wellbeing
    assert "participation_count" in wellbeing

    # Verify participation rate: 2 out of 2 employees = 100%
    assert wellbeing["participation_count"] == 2
    assert wellbeing["participation_rate"] == 100.0

    # Verify historical trends structure
    assert "historical_trends" in wellbeing
    trends = wellbeing["historical_trends"]
    assert isinstance(trends, dict)
    assert "daily" in trends
    assert "weekly" in trends

    # Verify daily trends
    daily_trends = trends["daily"]
    assert isinstance(daily_trends, list)
    assert len(daily_trends) >= 1

    daily = daily_trends[0]
    assert daily["date"] == today.date()
    assert daily["checkin_count"] == 2
    assert "overall_wellbeing" in daily
    assert "mental_fatigue" in daily
    assert "workload_manageability" in daily
    assert "perceived_focus" in daily
    assert "break_recovery" in daily

    # Verify weekly trends
    weekly_trends = trends["weekly"]
    assert isinstance(weekly_trends, list)
    assert len(weekly_trends) >= 1

    weekly = weekly_trends[0]
    assert "week_start" in weekly
    assert "week_end" in weekly
    assert "overall_wellbeing" in weekly
    assert "mental_fatigue" in weekly
    assert "risk_distribution" in weekly


def test_admin_analytics_empty_wellbeing_trends(db_session, test_org_with_members):
    """Test admin analytics when no wellbeing check-ins exist."""
    org_data = test_org_with_members
    org_id = org_data["org"].id
    admin_user = org_data["admin"]

    today = datetime.now(timezone.utc)

    # Query without any check-ins
    service = AdminOrganizationReportService(db_session, admin_user)
    analytics = service._get_org_context(
        org_ids=[org_id],
        period="today",
        start_date=today.date(),
        end_date=today.date(),
        include_test=False,
        user_tz="UTC"
    )

    # Verify wellbeing section exists but trends are empty
    wellbeing = analytics["organizational_wellbeing"]
    assert wellbeing["checkin_count"] == 0
    assert wellbeing["participation_rate"] == 0.0

    trends = wellbeing["historical_trends"]
    assert trends["daily"] == []
    assert trends["weekly"] == []


def test_admin_analytics_multi_day_trends(db_session, test_org_with_members):
    """Test admin analytics with wellbeing data across multiple days."""
    org_data = test_org_with_members
    org_id = org_data["org"].id
    admin_user = org_data["admin"]
    employees = org_data["employees"]

    # Create wellbeing check-ins for 3 consecutive days
    base_date = datetime.now(timezone.utc)

    for day_offset in range(3):
        current_day = base_date + timedelta(days=day_offset)

        for emp in employees:
            profile_id = emp["profile"].id
            user_id = emp["user"].id

            session = WorkSession(
                id=uuid.uuid4(),
                profile_id=profile_id,
                started_at=current_day,
                ended_at=current_day + timedelta(hours=8)
            )
            db_session.add(session)
            db_session.flush()

            # Vary scores by day
            base_score = 2 + day_offset
            checkin = SessionWellbeingCheckin(
                id=uuid.uuid4(),
                user_id=user_id,
                work_session_id=session.id,
                overall_wellbeing=base_score,
                mental_fatigue=2,
                workload_manageability=3,
                perceived_focus=4,
                break_recovery=2,
                created_at=current_day + timedelta(hours=4)
            )
            db_session.add(checkin)

    db_session.commit()

    # Get admin analytics for the 3-day period
    service = AdminOrganizationReportService(db_session, admin_user)
    analytics = service._get_org_context(
        org_ids=[org_id],
        period="custom",
        start_date=base_date.date(),
        end_date=(base_date + timedelta(days=2)).date(),
        include_test=False,
        user_tz="UTC"
    )

    wellbeing = analytics["organizational_wellbeing"]
    trends = wellbeing["historical_trends"]

    # Verify daily trends span 3 days
    daily_trends = trends["daily"]
    assert len(daily_trends) == 3

    for i, daily in enumerate(daily_trends):
        expected_date = (base_date + timedelta(days=i)).date()
        assert daily["date"] == expected_date
        assert daily["checkin_count"] == 2  # 2 employees per day


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
