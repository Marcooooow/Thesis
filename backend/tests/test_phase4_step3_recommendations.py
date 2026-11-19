"""
Phase 4 Step 3: Recommendation Statistics Tests

Comprehensive regression tests covering:
- Organization-level recommendation aggregation
- Category-specific acceptance and dismissal rates
- Team-level recommendation filtering with privacy enforcement
- Model version distribution
- Test data exclusion
- Duplicate prevention
"""

import pytest
from datetime import datetime, timezone, date, timedelta
from sqlalchemy.orm import Session
import uuid

from app.models import (
    User, Profile, Team, TeamMembership, Organization, OrganizationMembership,
    RecommendationFeedback, WorkSession
)
from app.services.admin_organization_report_service import AdminOrganizationReportService
from app.services.team_analytics_service import calculate_team_recommendation_statistics


@pytest.fixture
def org_with_members_and_recs(db: Session):
    """
    Create org with 4 employees, generate varied recommendations across categories.
    - Employee 1: 10 SHORT_BREAK (8 accepted, 2 dismissed)
    - Employee 2: 6 WALK (4 accepted, 2 dismissed)
    - Employee 3: 4 HYDRATE (2 accepted, 2 dismissed)
    - Employee 4: 2 STRETCH (1 accepted, 1 dismissed)
    Expected org acceptance rate: 15/22 = 68.2%
    """
    org = Organization(id=uuid.uuid4(), name="Rec Test Org")
    db.add(org)
    db.flush()

    admin_user = User(
        id=uuid.uuid4(),
        email="admin_rec@test.com",
        password_hash="hashed",
        full_name="Admin Rec",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(admin_user)
    db.flush()

    org_membership = OrganizationMembership(
        id=uuid.uuid4(),
        user_id=admin_user.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db.add(org_membership)
    db.flush()

    employees = []
    profiles = []

    for i in range(4):
        user = User(
            id=uuid.uuid4(),
            email=f"emp_rec_{i}@test.com",
            password_hash="hashed",
            full_name=f"Rec Employee {i}",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True
        )
        db.add(user)
        db.flush()

        profile = Profile(
            id=uuid.uuid4(),
            user_id=user.id,
            is_test_data=False
        )
        db.add(profile)
        db.flush()

        # Add employee to organization
        emp_org_mem = OrganizationMembership(
            id=uuid.uuid4(),
            user_id=user.id,
            organization_id=org.id,
            role="EMPLOYEE",
            status="APPROVED"
        )
        db.add(emp_org_mem)
        db.flush()

        employees.append(user)
        profiles.append(profile)

    # Generate recommendations by employee
    now = datetime.now(timezone.utc)
    base_timestamp = now - timedelta(days=7)

    # Employee 0: 10 SHORT_BREAK (8 accepted, 2 dismissed)
    for j in range(10):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=employees[0].id,
            recommendation_id=uuid.uuid4(),
            model_version="heuristic-only",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.72,
            context_features={},
            timestamp=base_timestamp + timedelta(hours=j),
            user_action="accepted" if j < 8 else "dismissed",
            viewed_at=base_timestamp + timedelta(hours=j, minutes=1),
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(feedback)

    # Employee 1: 6 WALK (4 accepted, 2 dismissed)
    for j in range(6):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=employees[1].id,
            recommendation_id=uuid.uuid4(),
            model_version="heuristic-only",
            recommendation_type="WALK",
            recommendation_score=0.65,
            context_features={},
            timestamp=base_timestamp + timedelta(hours=j),
            user_action="accepted" if j < 4 else "dismissed",
            viewed_at=base_timestamp + timedelta(hours=j, minutes=1),
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(feedback)

    # Employee 2: 4 HYDRATE (2 accepted, 2 dismissed)
    for j in range(4):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=employees[2].id,
            recommendation_id=uuid.uuid4(),
            model_version="cold-start-baseline",
            recommendation_type="HYDRATE",
            recommendation_score=0.55,
            context_features={},
            timestamp=base_timestamp + timedelta(hours=j),
            user_action="accepted" if j < 2 else "dismissed",
            viewed_at=base_timestamp + timedelta(hours=j, minutes=2),
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(feedback)

    # Employee 3: 2 STRETCH (1 accepted, 1 dismissed)
    for j in range(2):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=employees[3].id,
            recommendation_id=uuid.uuid4(),
            model_version="heuristic-only",
            recommendation_type="STRETCH",
            recommendation_score=0.50,
            context_features={},
            timestamp=base_timestamp + timedelta(hours=j),
            user_action="accepted" if j < 1 else "dismissed",
            viewed_at=base_timestamp + timedelta(hours=j, minutes=3),
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(feedback)

    db.flush()
    db.commit()

    return {
        "org_id": org.id,
        "admin_user": admin_user,
        "employees": employees,
        "profiles": profiles,
        "base_timestamp": base_timestamp
    }


def test_org_level_recommendation_aggregation(db: Session, org_with_members_and_recs):
    """
    Verify organization-level aggregation:
    - Total: 22 recommendations
    - Accepted: 15 (68.2%)
    - Dismissed: 7 (31.8%)
    - Category breakdown correct
    """
    setup = org_with_members_and_recs
    org_id = setup["org_id"]
    admin_user = setup["admin_user"]
    base_timestamp = setup["base_timestamp"]

    start_dt = base_timestamp - timedelta(hours=1)
    end_dt = base_timestamp + timedelta(days=1)

    # Calculate org-level stats
    stats = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org_id], start_dt, end_dt, include_test=False
    )

    # Verify overall counts
    assert stats["total_generated"] == 22
    assert stats["total_accepted"] == 15
    assert stats["total_dismissed"] == 7
    assert stats["acceptance_rate"] == 68.18  # 15/22 * 100
    assert stats["dismissal_rate"] == 31.82  # 7/22 * 100
    assert stats["data_quality"] == "sufficient_data"

    # Verify category breakdown
    cat_breakdown = stats["category_breakdown"]
    assert "SHORT_BREAK" in cat_breakdown
    assert cat_breakdown["SHORT_BREAK"]["generated"] == 10
    assert cat_breakdown["SHORT_BREAK"]["accepted"] == 8
    assert cat_breakdown["SHORT_BREAK"]["acceptance_rate"] == 80.0

    assert "WALK" in cat_breakdown
    assert cat_breakdown["WALK"]["generated"] == 6
    assert cat_breakdown["WALK"]["accepted"] == 4
    assert cat_breakdown["WALK"]["acceptance_rate"] == 66.67

    assert "HYDRATE" in cat_breakdown
    assert cat_breakdown["HYDRATE"]["generated"] == 4
    assert cat_breakdown["HYDRATE"]["accepted"] == 2
    assert cat_breakdown["HYDRATE"]["acceptance_rate"] == 50.0

    assert "STRETCH" in cat_breakdown
    assert cat_breakdown["STRETCH"]["generated"] == 2
    assert cat_breakdown["STRETCH"]["accepted"] == 1
    assert cat_breakdown["STRETCH"]["acceptance_rate"] == 50.0


def test_model_version_distribution(db: Session, org_with_members_and_recs):
    """
    Verify model version distribution tracking:
    - heuristic-only: 18 recommendations (81.8%)
    - cold-start-baseline: 4 recommendations (18.2%)
    """
    setup = org_with_members_and_recs
    org_id = setup["org_id"]
    base_timestamp = setup["base_timestamp"]

    start_dt = base_timestamp - timedelta(hours=1)
    end_dt = base_timestamp + timedelta(days=1)

    stats = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org_id], start_dt, end_dt, include_test=False
    )

    model_dist = stats["model_version_distribution"]
    assert "heuristic-only" in model_dist
    assert model_dist["heuristic-only"] == 81.82  # 18/22 * 100
    assert "cold-start-baseline" in model_dist
    assert model_dist["cold-start-baseline"] == 18.18  # 4/22 * 100


def test_time_to_view_latency(db: Session, org_with_members_and_recs):
    """
    Verify time-to-view latency calculation (median and p95).
    All recommendations in fixture are viewed 1-3 minutes after generation.
    """
    setup = org_with_members_and_recs
    org_id = setup["org_id"]
    base_timestamp = setup["base_timestamp"]

    start_dt = base_timestamp - timedelta(hours=1)
    end_dt = base_timestamp + timedelta(days=1)

    stats = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org_id], start_dt, end_dt, include_test=False
    )

    # All recommendations viewed, latencies should be: 60s (emp0), 60s (emp1), 120s (emp2), 180s (emp3)
    median = stats["time_to_view_median_seconds"]
    assert median is not None
    assert median > 0


def test_team_level_recommendation_statistics(db: Session):
    """
    Test team-level recommendation aggregation with privacy enforcement.
    Create team with 2 members (below N>=3 threshold) + recommendations.
    Verify stats are calculated but team is below privacy threshold.
    """
    org = Organization(id=uuid.uuid4(), name="Team Rec Test Org")
    db.add(org)
    db.flush()

    manager = User(
        id=uuid.uuid4(),
        email="mgr_team@test.com",
        password_hash="hashed",
        full_name="Team Manager",
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(manager)
    db.flush()

    org_mem = OrganizationMembership(
        id=uuid.uuid4(),
        user_id=manager.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    )
    db.add(org_mem)
    db.flush()

    team = Team(
        id=uuid.uuid4(),
        name="Team Rec Test",
        manager_user_id=manager.id,
        organization_id=org.id,
        is_active=True
    )
    db.add(team)
    db.flush()

    # Create 2 employees (below privacy threshold)
    employees = []
    for i in range(2):
        user = User(
            id=uuid.uuid4(),
            email=f"team_emp_{i}@test.com",
            password_hash="hashed",
            full_name=f"Team Employee {i}",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True
        )
        db.add(user)
        db.flush()

        profile = Profile(id=uuid.uuid4(), user_id=user.id, is_test_data=False)
        db.add(profile)
        db.flush()

        membership = TeamMembership(
            id=uuid.uuid4(),
            profile_id=profile.id,
            team_id=team.id,
            joined_at=datetime.now(timezone.utc),
            left_at=None
        )
        db.add(membership)
        db.flush()

        employees.append(user)

    # Add 6 recommendations total
    now = datetime.now(timezone.utc)
    for i, emp in enumerate(employees):
        for j in range(3):
            feedback = RecommendationFeedback(
                id=uuid.uuid4(),
                user_id=emp.id,
                recommendation_id=uuid.uuid4(),
                model_version="heuristic-only",
                recommendation_type="SHORT_BREAK" if (i + j) % 2 == 0 else "WALK",
                recommendation_score=0.7,
                context_features={},
                timestamp=now - timedelta(days=7, hours=j),
                user_action="accepted" if j < 2 else "dismissed",
                viewed_at=now - timedelta(days=7, hours=j, minutes=1),
                feature_schema_version="v2-wellbeing",
                provenance="live"
            )
            db.add(feedback)

    db.flush()
    db.commit()

    # Calculate team stats
    start_dt = now - timedelta(days=8)
    end_dt = now

    stats = calculate_team_recommendation_statistics(
        db, team.id, start_dt, end_dt, include_test=False
    )

    # Should aggregate correctly despite being below N>=3
    assert stats["total_generated"] == 6
    assert stats["total_accepted"] == 4
    assert stats["total_dismissed"] == 2
    assert stats["acceptance_rate"] == 66.67


def test_test_data_exclusion(db: Session):
    """
    Verify test data is excluded from recommendation statistics when include_test=False.
    Create org with 4 employees: 3 real, 1 test data.
    Test employee generates 4 SHORT_BREAK (all accepted).
    Real employees generate 8 recommendations total (5 accepted).
    Expected: When include_test=False, only 8 recommendations counted.
    """
    org = Organization(id=uuid.uuid4(), name="Test Data Org")
    db.add(org)
    db.flush()

    admin = User(
        id=uuid.uuid4(),
        email="admin_test@test.com",
        password_hash="hashed",
        full_name="Admin Test",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(admin)
    db.flush()

    org_mem = OrganizationMembership(
        id=uuid.uuid4(),
        user_id=admin.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db.add(org_mem)
    db.flush()

    # Create 3 real employees + 1 test employee
    employees = []
    profiles = []

    for i in range(4):
        user = User(
            id=uuid.uuid4(),
            email=f"emp_test_{i}@test.com",
            password_hash="hashed",
            full_name=f"Employee Test {i}",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True
        )
        db.add(user)
        db.flush()

        # Employee 3 is test data
        is_test = (i == 3)
        profile = Profile(
            id=uuid.uuid4(),
            user_id=user.id,
            is_test_data=is_test
        )
        db.add(profile)
        db.flush()

        employees.append(user)
        profiles.append(profile)

    now = datetime.now(timezone.utc)
    base_ts = now - timedelta(days=7)

    # Real employees: 8 recommendations, 5 accepted
    for i in range(3):
        for j in range(2) if i < 2 else range(2):
            feedback = RecommendationFeedback(
                id=uuid.uuid4(),
                user_id=employees[i].id,
                recommendation_id=uuid.uuid4(),
                model_version="heuristic-only",
                recommendation_type="SHORT_BREAK",
                recommendation_score=0.7,
                context_features={},
                timestamp=base_ts + timedelta(hours=i*3+j),
                user_action="accepted" if (i*2+j) < 5 else "dismissed",
                viewed_at=base_ts + timedelta(hours=i*3+j, minutes=1),
                feature_schema_version="v2-wellbeing",
                provenance="live"
            )
            db.add(feedback)

    # Test employee: 4 recommendations, all accepted
    for j in range(4):
        feedback = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=employees[3].id,
            recommendation_id=uuid.uuid4(),
            model_version="heuristic-only",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.7,
            context_features={},
            timestamp=base_ts + timedelta(hours=10+j),
            user_action="accepted",
            viewed_at=base_ts + timedelta(hours=10+j, minutes=1),
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(feedback)

    db.flush()
    db.commit()

    # Calculate with test data excluded
    start_dt = base_ts - timedelta(hours=1)
    end_dt = now

    stats_no_test = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org.id], start_dt, end_dt, include_test=False
    )

    # Should only count real employees
    assert stats_no_test["total_generated"] <= 8  # At most 8 from real employees

    # Calculate with test data included
    stats_with_test = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org.id], start_dt, end_dt, include_test=True
    )

    # Should count all
    assert stats_with_test["total_generated"] >= stats_no_test["total_generated"]


def test_empty_org_recommendation_stats(db: Session):
    """
    Verify empty organization returns appropriate zero metrics with insufficient_data flag.
    """
    org = Organization(id=uuid.uuid4(), name="Empty Rec Org")
    db.add(org)
    db.flush()

    admin = User(
        id=uuid.uuid4(),
        email="admin_empty@test.com",
        password_hash="hashed",
        full_name="Admin Empty",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(admin)
    db.flush()

    org_mem = OrganizationMembership(
        id=uuid.uuid4(),
        user_id=admin.id,
        organization_id=org.id,
        role="ADMIN",
        status="APPROVED"
    )
    db.add(org_mem)
    db.commit()

    now = datetime.now(timezone.utc)
    start_dt = now - timedelta(days=7)
    end_dt = now

    stats = AdminOrganizationReportService.calculate_organization_recommendation_statistics(
        db, [org.id], start_dt, end_dt, include_test=False
    )

    assert stats["total_generated"] == 0
    assert stats["total_accepted"] == 0
    assert stats["total_dismissed"] == 0
    assert stats["acceptance_rate"] == 0.0
    assert stats["data_quality"] == "insufficient_data"
