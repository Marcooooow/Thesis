"""
Comprehensive unit tests for short-lived analytics caching (Optimization 2).
"""
import pytest
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from app.models import User, Profile, Organization, OrganizationMembership, Team, TeamMembership, WorkSession
from app.services.team_analytics_service import compute_team_analytics
from app.services.cache_service import analytics_cache
from app.auth.security import get_password_hash


@pytest.fixture(autouse=True)
def clear_cache():
    analytics_cache.invalidate()
    yield
    analytics_cache.invalidate()


def test_analytics_cache_hit_and_miss(test_db: Session):
    """Test cache hit on repeated analytics calls and cache miss on first call."""
    org = Organization(name="Cache Org 1")
    test_db.add(org)
    test_db.flush()

    manager = User(
        email="manager_cache1@intellibreak.local",
        password_hash=get_password_hash("password"),
        full_name="Manager 1",
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(manager)
    test_db.flush()

    org_mem = OrganizationMembership(organization_id=org.id, user_id=manager.id, status="APPROVED")
    test_db.add(org_mem)

    team = Team(name="Team A", organization_id=org.id, manager_user_id=manager.id, is_active=True)
    test_db.add(team)
    test_db.flush()

    emp = User(
        email="emp_cache1@intellibreak.local",
        password_hash=get_password_hash("password"),
        full_name="Emp 1",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    test_db.add(emp)
    test_db.flush()

    profile = Profile(user_id=emp.id, job_role="Dev", industry="Tech", is_test_data=False)
    test_db.add(profile)
    test_db.flush()

    t_mem = TeamMembership(team_id=team.id, profile_id=profile.id)
    test_db.add(t_mem)
    test_db.commit()

    # First call (Cache Miss)
    res1 = compute_team_analytics(db=test_db, current_user=manager, team_id=team.id)
    assert res1 is not None

    # Check cache store has items
    assert len(analytics_cache._store) == 1

    # Second call (Cache Hit)
    res2 = compute_team_analytics(db=test_db, current_user=manager, team_id=team.id)
    assert res2 is not None
    assert res1["session_count"] == res2["session_count"]


def test_analytics_cache_isolation_and_rbac(test_db: Session):
    """Test that different managers/teams and RBAC scopes do not collide in cache."""
    org = Organization(name="Cache Org 2")
    test_db.add(org)
    test_db.flush()

    m1 = User(email="m1@intellibreak.local", password_hash=get_password_hash("p"), full_name="M1", role="MANAGER", approval_status="APPROVED", is_active=True)
    m2 = User(email="m2@intellibreak.local", password_hash=get_password_hash("p"), full_name="M2", role="MANAGER", approval_status="APPROVED", is_active=True)
    test_db.add_all([m1, m2])
    test_db.flush()

    t1 = Team(name="Team 1", organization_id=org.id, manager_user_id=m1.id, is_active=True)
    t2 = Team(name="Team 2", organization_id=org.id, manager_user_id=m2.id, is_active=True)
    test_db.add_all([t1, t2])
    test_db.flush()

    emp1 = User(email="emp1@intellibreak.local", password_hash=get_password_hash("p"), full_name="E1", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    emp2 = User(email="emp2@intellibreak.local", password_hash=get_password_hash("p"), full_name="E2", role="EMPLOYEE", approval_status="APPROVED", is_active=True)
    test_db.add_all([emp1, emp2])
    test_db.flush()

    p1 = Profile(user_id=emp1.id, is_test_data=False)
    p2 = Profile(user_id=emp2.id, is_test_data=False)
    test_db.add_all([p1, p2])
    test_db.flush()

    test_db.add(TeamMembership(team_id=t1.id, profile_id=p1.id))
    test_db.add(TeamMembership(team_id=t2.id, profile_id=p2.id))
    test_db.commit()

    res_m1 = compute_team_analytics(db=test_db, current_user=m1, team_id=t1.id)
    res_m2 = compute_team_analytics(db=test_db, current_user=m2, team_id=t2.id)

    assert len(analytics_cache._store) == 2
    assert res_m1["profile_ids"] != res_m2["profile_ids"]


def test_analytics_cache_invalidation(test_db: Session):
    """Test manual cache invalidation."""
    org = Organization(name="Cache Org 3")
    test_db.add(org)
    test_db.flush()

    manager = User(email="m3@intellibreak.local", password_hash=get_password_hash("p"), full_name="M3", role="MANAGER", approval_status="APPROVED", is_active=True)
    test_db.add(manager)
    test_db.flush()

    res1 = compute_team_analytics(db=test_db, current_user=manager)
    assert len(analytics_cache._store) == 1

    analytics_cache.invalidate()
    assert len(analytics_cache._store) == 0
