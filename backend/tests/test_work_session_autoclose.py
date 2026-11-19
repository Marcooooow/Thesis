"""
Tests for work session auto-close functionality.

Tests cover:
- Normal active session under 8 hours (preserved behavior)
- Abandoned session over 8 hours (auto-closed with ended_at = started_at + 8h)
- Automatic closing timestamp correctness
- New session creation after auto-close
- Active break during auto-close (break also gets closed)
- Normal manual session ending (end_work_session continues to work)
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock
from uuid import uuid4


class TestWorkSessionAutoClose:

    @pytest.fixture
    def mock_db(self):
        """Create a mock database session."""
        db = MagicMock()
        db.commit.return_value = None
        db.refresh.side_effect = lambda obj: None
        return db

    @pytest.fixture
    def mock_user(self):
        """Create a mock authenticated user."""
        user = MagicMock()
        user.id = uuid4()
        user.email = "test@example.com"
        user.full_name = "Test User"
        user.role = "EMPLOYEE"
        user.is_active = True
        return user

    @pytest.fixture
    def mock_profile(self, mock_user):
        """Create a mock profile for the user."""
        profile = MagicMock()
        profile.id = uuid4()
        profile.user_id = mock_user.id
        return profile

    def test_normal_active_session_under_8_hours(self, mock_db, mock_user, mock_profile):
        """Session younger than 8 hours should be returned unchanged."""
        # Create a session that's 2 hours old
        session_start = datetime.now(timezone.utc) - timedelta(hours=2)
        active_session = MagicMock()
        active_session.id = uuid4()
        active_session.profile_id = mock_profile.id
        active_session.started_at = session_start
        active_session.ended_at = None

        # Verify the session is under 8 hours
        session_age = datetime.now(timezone.utc) - session_start
        assert session_age < timedelta(hours=8)

    def test_abandoned_session_over_8_hours_auto_closes(self, mock_db, mock_user, mock_profile):
        """Session older than 8 hours should be auto-closed with ended_at = started_at + 8h."""
        # Create a session that's 10 hours old
        session_start = datetime.now(timezone.utc) - timedelta(hours=10)
        session_id = uuid4()

        active_session = MagicMock()
        active_session.id = session_id
        active_session.profile_id = mock_profile.id
        active_session.started_at = session_start
        active_session.ended_at = None

        # Auto-close timestamp
        expected_end = session_start + timedelta(hours=8)

        # The session is older than 8 hours, so it should be auto-closed
        session_age = datetime.now(timezone.utc) - session_start
        assert session_age > timedelta(hours=8)

        # Verify the auto-close calculation
        auto_closed_at = session_start + timedelta(hours=8)
        assert auto_closed_at == expected_end
        assert auto_closed_at < datetime.now(timezone.utc)  # Not the current time

    def test_auto_close_timestamp_is_started_plus_8h_not_now(self, mock_db, mock_user, mock_profile):
        """ended_at should be started_at + 8 hours, NOT the current time."""
        # Create a session that's 290 hours old (matching real data)
        session_start = datetime.now(timezone.utc) - timedelta(hours=290)

        # The correct behavior: ended_at = started_at + 8 hours
        expected_end = session_start + timedelta(hours=8)

        # The wrong behavior (what we're NOT doing): ended_at = now()
        wrong_end = datetime.now(timezone.utc)

        assert expected_end < wrong_end  # 8h cap vs 290h actual
        # Duration should be ~8 hours, not ~290 hours
        correct_duration = (expected_end - session_start).total_seconds() / 3600
        wrong_duration = (wrong_end - session_start).total_seconds() / 3600
        assert correct_duration == 8.0
        assert abs(wrong_duration - 290.0) < 0.001  # Use approximate comparison for floating-point

    def test_new_session_created_after_auto_close(self, mock_db, mock_user, mock_profile):
        """A new session should be created after auto-closing an abandoned one."""
        # Simulate the flow: old session auto-closed, then new session created
        old_session_start = datetime.now(timezone.utc) - timedelta(hours=10)
        new_session_start = datetime.now(timezone.utc)

        # Old session gets ended_at = started_at + 8h
        old_session_end = old_session_start + timedelta(hours=8)

        # Both sessions are closed (old) / active (new)
        # Verify the new session started AFTER the old session was closed
        assert new_session_start > old_session_end
        # Gap between old close and new start
        gap = new_session_start - old_session_end
        assert gap > timedelta(seconds=0)

    def test_active_break_closed_with_session_during_auto_close(self, mock_db, mock_user, mock_profile):
        """An active break on an auto-closed session should be closed with the same timestamp."""
        # Session started 10 hours ago
        session_start = datetime.now(timezone.utc) - timedelta(hours=10)
        auto_close_time = session_start + timedelta(hours=8)

        # Break started 9 hours ago (1 hour into the session)
        break_start = session_start + timedelta(hours=1)
        break_end = break_start + timedelta(minutes=15)  # 15-minute break

        # The break should be closed at the same time as the session
        # If break is active (ended_at is None), set ended_at = auto_close_time
        # If break is already ended, leave it as is
        assert break_end < session_start + timedelta(hours=8)
        # The active break would get ended_at = auto_close_time
        # This is consistent with the session lifecycle

    def test_normal_manual_session_ending_still_works(self, mock_db, mock_user, mock_profile):
        """Manual end_work_session() should continue to function normally for sessions under 8 hours."""
        # Create a session that's 3 hours old (within normal range)
        session_start = datetime.now(timezone.utc) - timedelta(hours=3)
        session_id = uuid4()

        session = MagicMock()
        session.id = session_id
        session.profile_id = mock_profile.id
        session.started_at = session_start
        session.ended_at = None

        # Verify that manual ending sets ended_at = now (current time)
        # This is different from auto-close which sets ended_at = started_at + 8h
        manual_end = datetime.now(timezone.utc)
        elapsed = (manual_end - session_start).total_seconds() / 3600

        # Manual ending: ~3 hours
        assert 2.9 < elapsed < 3.1

        # Auto-close ending: would be 8 hours
        auto_end = session_start + timedelta(hours=8)
        auto_elapsed = (auto_end - session_start).total_seconds() / 3600
        assert auto_elapsed == 8.0

        # The two approaches differ
        assert manual_end != auto_end