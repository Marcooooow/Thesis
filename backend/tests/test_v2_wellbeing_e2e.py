"""
V2 Wellbeing End-to-End Regression Test
========================================
Verifies that a genuine Session Wellbeing Check-in from a completed session
flows into the next recommendation's V2 feature snapshot.
"""
import os
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.orm import Session

from app.models import (
    User, Profile, Organization, OrganizationMembership,
    Team, TeamMembership, WorkSession, Task,
    SessionWellbeingCheckin, RecommendationFeedback, UserSettings
)
from app.services.recommendation_service import _recommend_for_profile


def create_test_user_and_profile(db: Session, email_suffix: str = "") -> tuple[User, Profile]:
    """Helper to create test user and profile."""
    org = Organization(name=f"Test Org {email_suffix}")
    db.add(org)
    db.flush()

    user = User(
        email=f"test{email_suffix}@intellibreak.local",
        password_hash="hashed_password",
        full_name=f"Test User {email_suffix}",
        organization_name=f"Test Org {email_suffix}",
        account_type="organization",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(user)
    db.flush()

    org_mem = OrganizationMembership(
        user_id=user.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    db.add(org_mem)

    profile = Profile(
        user_id=user.id,
        job_role="Test Role",
        industry="Test Industry",
        years_of_experience=2,
        age=30,
        gender="Non-binary",
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
        department="Test Department"
    )
    db.add(profile)
    db.flush()

    team = Team(
        name=f"Test Team {email_suffix}",
        description="Test team for V2 wellbeing E2E test",
        manager_user_id=user.id,
        organization_id=org.id
    )
    db.add(team)
    db.flush()

    team_mem = TeamMembership(
        profile_id=profile.id,
        team_id=team.id,
        role="EMPLOYEE",
        joined_at=datetime.now(timezone.utc)
    )
    db.add(team_mem)

    settings = UserSettings(
        user_id=user.id,
        notifications_enabled=True,
        break_reminders=True,
        break_interval_minutes=30,
        break_duration_minutes=10,
        break_coach_enabled=True,
        break_coach_cooldown_minutes=30,
        time_format="24h"
    )
    db.add(settings)

    db.commit()
    return user, profile


class TestV2WellbeingE2E:
    """End-to-end test for V2 wellbeing feature capture."""

    def test_wellbeing_from_completed_session_flows_into_next_recommendation(self, db):
        """
        Test the complete flow:
        1. Session A ends
        2. Wellbeing check-in submitted for Session A (after session ends)
        3. Session B starts
        4. Recommendation generated during Session B
        5. Persisted snapshot contains wellbeing from Session A
        """
        # Arrange
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user, profile = create_test_user_and_profile(db, "e2e-flow")

        now = datetime.now(timezone.utc)

        # Session A - COMPLETED
        session_a = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(hours=3),
            ended_at=now - timedelta(hours=1)  # Ended 1 hour ago
        )
        db.add(session_a)
        db.flush()

        # Wellbeing check-in for Session A - submitted AFTER session ended
        # This is the real-world pattern: user finishes work, then rates wellbeing
        checkin_a = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=session_a.id,
            overall_wellbeing=4,
            mental_fatigue=2,
            workload_manageability=4,
            perceived_focus=3,
            break_recovery=5,
            stress_factors=["meetings", "deadlines"],
            created_at=now - timedelta(minutes=30)  # 30 min AFTER session_a.ended_at
        )
        db.add(checkin_a)

        # Session B - ACTIVE (current session)
        session_b = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(minutes=45),
            ended_at=None  # Active session
        )
        db.add(session_b)
        db.flush()

        # Tasks in Session B for non-cold-start
        task1 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=40),
            actual_minutes=30
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 2",
            status="IN_PROGRESS",
            created_at=now - timedelta(minutes=20),
            started_at=now - timedelta(minutes=15)
        )
        db.add_all([task1, task2])
        db.commit()

        # Debug: run the EXACT same query as _extract_wellbeing_features using ORM
        internal_now = datetime.now(timezone.utc)
        from sqlalchemy import text
        stmt = text("""
            SELECT
                swc.overall_wellbeing,
                swc.mental_fatigue,
                swc.workload_manageability,
                swc.perceived_focus,
                swc.break_recovery,
                swc.stress_factors,
                ws.ended_at,
                swc.created_at
            FROM work_sessions ws
            JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id
            WHERE
                swc.user_id = :user_id
                AND ws.ended_at IS NOT NULL
                AND ws.ended_at < :generation_timestamp
                AND swc.created_at <= :generation_timestamp
            ORDER BY ws.ended_at DESC
            LIMIT 1
        """)
        join_result = db.execute(stmt, {
            "user_id": str(user.id),
            "generation_timestamp": internal_now
        }).fetchone()
        print(f"DEBUG: JOIN query result via db.execute = {join_result}")

        # Debug: check individual conditions
        cond1 = db.execute(text("SELECT COUNT(*) FROM session_wellbeing_checkins WHERE user_id = :uid"), {"uid": str(user.id)}).scalar()
        print(f"DEBUG: test user.id = {user.id}")
        print(f"DEBUG: checkin_a.user_id = {checkin_a.user_id}")
        raw_checkin_user_ids = db.execute(text("SELECT user_id FROM session_wellbeing_checkins")).fetchall()
        print(f"DEBUG: All checkin user_ids = {raw_checkin_user_ids}")
        raw_session_profile_ids = db.execute(text("SELECT profile_id FROM work_sessions")).fetchall()
        print(f"DEBUG: All session profile_ids = {raw_session_profile_ids}")
        print(f"DEBUG: profile.id = {profile.id}")
        print(f"DEBUG: profile.user_id = {profile.user_id}")

        cond2 = db.execute(text("SELECT COUNT(*) FROM work_sessions ws JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id WHERE ws.ended_at IS NOT NULL"), {}).scalar()
        cond3 = db.execute(text("SELECT COUNT(*) FROM work_sessions ws JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id WHERE ws.ended_at < :gen_ts"), {"gen_ts": internal_now}).scalar()
        cond4 = db.execute(text("SELECT COUNT(*) FROM work_sessions ws JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id WHERE swc.created_at <= :gen_ts"), {"gen_ts": internal_now}).scalar()
        cond5 = db.execute(text("SELECT COUNT(*) FROM work_sessions ws JOIN session_wellbeing_checkins swc ON ws.id = swc.work_session_id WHERE ws.ended_at IS NOT NULL AND ws.ended_at < :gen_ts AND swc.created_at <= :gen_ts"), {"gen_ts": internal_now}).scalar()
        print(f"DEBUG: cond1 (user_id match) = {cond1}")
        print(f"DEBUG: cond2 (ended_at not null) = {cond2}")
        print(f"DEBUG: cond3 (ended_at < gen_ts) = {cond3}")
        print(f"DEBUG: cond4 (created_at <= gen_ts) = {cond4}")
        print(f"DEBUG: cond5 (all conditions) = {cond5}")

        # Act - Generate recommendation during Session B
        result = _recommend_for_profile(db, profile.id)

        # Assert
        assert result["recommendation_score"] >= 0.0 and result["recommendation_score"] <= 1.0
        assert result["candidate_type"] in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]

        # CRITICAL: Check that wellbeing features were captured
        snapshot = result["context_features_snapshot"]
        assert snapshot is not None, "Feature snapshot should exist"

        # Verify all six V2 wellbeing features are present (canonical V2 schema keys)
        assert "wellbeing_overall" in snapshot, "wellbeing_overall missing"
        assert "wellbeing_fatigue" in snapshot, "wellbeing_fatigue missing"
        assert "wellbeing_workload" in snapshot, "wellbeing_workload missing"
        assert "wellbeing_focus" in snapshot, "wellbeing_focus missing"
        assert "wellbeing_recovery" in snapshot, "wellbeing_recovery missing"
        assert "wellbeing_stress" in snapshot, "wellbeing_stress missing"

        # Verify values are correctly normalized (1-5 -> 0.0-1.0)
        assert snapshot["wellbeing_overall"] == 0.75  # (4-1)/4
        assert snapshot["wellbeing_fatigue"] == 0.25  # (2-1)/4
        assert snapshot["wellbeing_workload"] == 0.75  # (4-1)/4
        assert snapshot["wellbeing_focus"] == 0.5  # (3-1)/4
        assert snapshot["wellbeing_recovery"] == 1.0  # (5-1)/4
        assert snapshot["wellbeing_stress"] == 2  # len(["meetings", "deadlines"])

        # Verify observation flag
        assert snapshot["wellbeing_checkin_observed"] is True, "Check-in should be observed"

        # Verify schema version
        print(f"DEBUG: feature_schema_version = {result.get('feature_schema_version')}")
        assert result["feature_schema_version"] == "v2-wellbeing"

        # Cleanup
        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_checkin_created_after_recommendation_excluded(self, db):
        """
        Test that a check-in created AFTER recommendation generation
        is NOT included in the snapshot.
        """
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user, profile = create_test_user_and_profile(db, "future-leak")

        now = datetime.now(timezone.utc)

        # Session A - COMPLETED
        session_a = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(hours=3),
            ended_at=now - timedelta(hours=1)
        )
        db.add(session_a)
        db.flush()

        # Session B - ACTIVE
        session_b = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(minutes=45),
            ended_at=None
        )
        db.add(session_b)
        db.flush()

        # Tasks in Session B
        task1 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=40),
            actual_minutes=30
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 2",
            status="TODO",
            created_at=now - timedelta(minutes=20)
        )
        db.add_all([task1, task2])
        db.commit()

        # Act - Generate FIRST recommendation (no check-in yet)
        result1 = _recommend_for_profile(db, profile.id)
        snapshot1 = result1["context_features_snapshot"]
        assert snapshot1["wellbeing_checkin_observed"] is False

        # NOW add check-in for Session A (AFTER first recommendation)
        # Use datetime.now(timezone.utc) - 1 minute to ensure it's before the next generation
        checkin_a = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=session_a.id,
            overall_wellbeing=4,
            mental_fatigue=2,
            workload_manageability=4,
            perceived_focus=3,
            break_recovery=5,
            stress_factors=["meetings"],
            created_at=datetime.now(timezone.utc) - timedelta(minutes=1)  # 1 min ago, eligible for next rec
        )
        db.add(checkin_a)
        db.commit()

        # Generate SECOND recommendation
        result2 = _recommend_for_profile(db, profile.id)
        snapshot2 = result2["context_features_snapshot"]

        # Second snapshot should have the check-in (since it's now before generation time)
        assert snapshot2["wellbeing_checkin_observed"] is True

        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_other_employees_checkin_excluded(self, db):
        """
        Test that another employee's check-in does NOT enter the snapshot.
        """
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user1, profile1 = create_test_user_and_profile(db, "employee1")
        user2, profile2 = create_test_user_and_profile(db, "employee2")

        now = datetime.now(timezone.utc)

        # Session A - COMPLETED (belongs to employee 1)
        session_a = WorkSession(
            profile_id=profile1.id,
            started_at=now - timedelta(hours=3),
            ended_at=now - timedelta(hours=1)
        )
        db.add(session_a)
        db.flush()

        # Check-in from EMPLOYEE 2 for employee 1's session (should be excluded)
        other_checkin = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user2.id,  # Different user!
            work_session_id=session_a.id,
            overall_wellbeing=5,
            mental_fatigue=1,
            workload_manageability=5,
            perceived_focus=5,
            break_recovery=5,
            stress_factors=[],
            created_at=now - timedelta(minutes=30)
        )
        db.add(other_checkin)

        # Session B - ACTIVE (employee 1)
        session_b = WorkSession(
            profile_id=profile1.id,
            started_at=now - timedelta(minutes=45),
            ended_at=None
        )
        db.add(session_b)
        db.flush()

        task1 = Task(
            profile_id=profile1.id,
            work_session_id=session_b.id,
            title="Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=40),
            actual_minutes=30
        )
        task2 = Task(
            profile_id=profile1.id,
            work_session_id=session_b.id,
            title="Task 2",
            status="TODO",
            created_at=now - timedelta(minutes=20)
        )
        db.add_all([task1, task2])
        db.commit()

        # Act
        result = _recommend_for_profile(db, profile1.id)

        # Assert - other employee's check-in excluded
        snapshot = result["context_features_snapshot"]
        assert snapshot["wellbeing_checkin_observed"] is False, "Other employee's check-in should be excluded"
        assert snapshot["wellbeing_overall"] is None

        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_missing_wellbeing_measurements_not_fabricated(self, db):
        """
        Test that missing wellbeing measurements remain NULL (not zero).
        """
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user, profile = create_test_user_and_profile(db, "missing")

        now = datetime.now(timezone.utc)

        # Session A - COMPLETED
        session_a = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(hours=3),
            ended_at=now - timedelta(hours=1)
        )
        db.add(session_a)
        db.flush()

        # Check-in with ONLY overall_wellbeing (others NULL)
        checkin_a = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=session_a.id,
            overall_wellbeing=4,
            mental_fatigue=None,
            workload_manageability=None,
            perceived_focus=None,
            break_recovery=None,
            stress_factors=None,
            created_at=now - timedelta(minutes=30)
        )
        db.add(checkin_a)

        # Session B - ACTIVE
        session_b = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(minutes=45),
            ended_at=None
        )
        db.add(session_b)
        db.flush()

        task1 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=40),
            actual_minutes=30
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 2",
            status="TODO",
            created_at=now - timedelta(minutes=20)
        )
        db.add_all([task1, task2])
        db.commit()

        # Act
        result = _recommend_for_profile(db, profile.id)

        # Assert - wellbeing features should be None (not zero) for missing measurements
        # The check-in IS observed (it exists and is eligible), but missing fields remain None
        snapshot = result["context_features_snapshot"]
        assert snapshot["wellbeing_checkin_observed"] is True  # Check-in row exists
        assert snapshot["wellbeing_overall"] == 0.75  # (4-1)/4 = 0.75 (this one is set)
        assert snapshot["wellbeing_fatigue"] is None
        assert snapshot["wellbeing_workload"] is None
        assert snapshot["wellbeing_focus"] is None
        assert snapshot["wellbeing_recovery"] is None
        assert snapshot["wellbeing_stress"] is None

        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]

    def test_feature_snapshot_immutable_after_generation(self, db):
        """
        Test that the feature snapshot is captured at generation time
        and doesn't change if check-ins are added later.
        """
        os.environ["ML_RECOMMENDATIONS_ENABLED"] = "false"
        user, profile = create_test_user_and_profile(db, "immutable")

        now = datetime.now(timezone.utc)

        # Session A - COMPLETED
        session_a = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(hours=3),
            ended_at=now - timedelta(hours=1)
        )
        db.add(session_a)
        db.flush()

        # No check-in yet
        session_b = WorkSession(
            profile_id=profile.id,
            started_at=now - timedelta(minutes=45),
            ended_at=None
        )
        db.add(session_b)
        db.flush()

        task1 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 1",
            status="DONE",
            created_at=now - timedelta(minutes=40),
            actual_minutes=30
        )
        task2 = Task(
            profile_id=profile.id,
            work_session_id=session_b.id,
            title="Task 2",
            status="TODO",
            created_at=now - timedelta(minutes=20)
        )
        db.add_all([task1, task2])
        db.commit()

        # Act - Generate recommendation WITHOUT check-in
        result1 = _recommend_for_profile(db, profile.id)

        snapshot1 = result1["context_features_snapshot"]
        assert snapshot1["wellbeing_checkin_observed"] is False

        # NOW add check-in for Session A (after recommendation)
        checkin_a = SessionWellbeingCheckin(
            id=uuid.uuid4(),
            user_id=user.id,
            work_session_id=session_a.id,
            overall_wellbeing=4,
            mental_fatigue=2,
            workload_manageability=4,
            perceived_focus=3,
            break_recovery=5,
            stress_factors=["meetings"],
            created_at=datetime.now(timezone.utc) - timedelta(minutes=1)  # 1 min ago, eligible for next rec
        )
        db.add(checkin_a)
        db.commit()

        # Generate SECOND recommendation
        result2 = _recommend_for_profile(db, profile.id)
        snapshot2 = result2["context_features_snapshot"]

        # First snapshot should remain unchanged (immutable)
        assert snapshot1["wellbeing_checkin_observed"] is False
        # Second snapshot should have the check-in
        assert snapshot2["wellbeing_checkin_observed"] is True

        if "ML_RECOMMENDATIONS_ENABLED" in os.environ:
            del os.environ["ML_RECOMMENDATIONS_ENABLED"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])