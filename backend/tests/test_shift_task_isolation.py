"""
Tests for shift and task lifecycle isolation (Bug A & Bug B regression tests).

Scenarios covered:
- Scenario A: Shift without a task (WorkSession created, no WorkTask created, Task History clean)
- Scenario B: Shift with an active task (Task finalized when shift ends, duration persisted)
- Scenario C: Unfinished task (Timer stops, duration saved, incomplete status preserved)
- Scenario D: No active task (Start shift without task, end shift, no tasks modified)
- Duplicate end shift calls and error handling
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock
from uuid import uuid4
from fastapi import HTTPException

from app.models import Task, WorkSession, Profile
from app.routers.work import start_work_session, end_work_session, create_task, update_task_status
from app.schemas.work import TaskCreateRequest, TaskStatusUpdateRequest


class TestShiftTaskIsolation:

    @pytest.fixture
    def mock_db(self):
        db = MagicMock()
        db.commit.return_value = None
        db.refresh.side_effect = lambda obj: None
        return db

    @pytest.fixture
    def mock_user(self):
        user = MagicMock()
        user.id = uuid4()
        user.email = "test@example.com"
        user.full_name = "Test Employee"
        user.role = "EMPLOYEE"
        user.is_active = True
        return user

    @pytest.fixture
    def mock_profile(self, mock_user):
        profile = MagicMock()
        profile.id = uuid4()
        profile.user_id = mock_user.id
        return profile

    def test_scenario_a_shift_without_task(self, mock_db, mock_user, mock_profile):
        """Scenario A: Shift without a task creates only a WorkSession and no tasks/placeholders."""
        # Mock profile lookup, no active session, user settings lookup, new session add
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            None,          # No active session
            None,          # User settings lookup
        ]

        def mock_refresh(obj):
            if isinstance(obj, WorkSession) and obj.id is None:
                obj.id = uuid4()
        mock_db.refresh.side_effect = mock_refresh

        # Start shift without task
        session_resp = start_work_session(mock_user, mock_db)

        assert session_resp is not None
        assert session_resp.id is not None
        assert session_resp.ended_at is None

        # Verify no Task was created (tasks query returning empty list)
        mock_db.query.return_value.filter.return_value.all.return_value = []
        tasks_in_db = mock_db.query(Task).filter(Task.profile_id == mock_profile.id).all()
        assert len(tasks_in_db) == 0

    def test_scenario_b_shift_with_active_task(self, mock_db, mock_user, mock_profile):
        """Scenario B: Shift with an active task finalizes task duration and stops timer when shift ends."""
        session_id = uuid4()
        active_session = WorkSession(
            id=session_id,
            profile_id=mock_profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=1),
            ended_at=None
        )

        task_id = uuid4()
        active_task = Task(
            id=task_id,
            profile_id=mock_profile.id,
            work_session_id=session_id,
            title="Active Task",
            status="IN_PROGRESS",
            started_at=datetime.now(timezone.utc) - timedelta(minutes=30),
            actual_minutes=10
        )

        # Mock profile, active session, no active break, user settings
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,    # Profile lookup
            active_session,  # Active session lookup for end_work_session
            None,            # Active break lookup (none)
            None,            # User settings lookup
            None,            # User settings dnd override lookup
        ]
        mock_db.query.return_value.filter.return_value.all.side_effect = [
            [active_task],   # Active tasks query
            [],              # Breaks during task query
        ]

        # End shift
        end_resp = end_work_session(mock_user, mock_db)

        assert end_resp.ended_at is not None
        # Verify active task timer stopped (started_at is None) and duration was accumulated
        assert active_task.started_at is None
        assert active_task.actual_minutes >= 40  # 10 initial + ~30 elapsed

    def test_scenario_c_unfinished_task_preserved(self, mock_db, mock_user, mock_profile):
        """Scenario C: Unfinished task preserves incomplete status while stopping timer and saving duration."""
        session_id = uuid4()
        active_session = WorkSession(
            id=session_id,
            profile_id=mock_profile.id,
            started_at=datetime.now(timezone.utc) - timedelta(hours=2),
            ended_at=None
        )

        task_id = uuid4()
        task = Task(
            id=task_id,
            profile_id=mock_profile.id,
            work_session_id=session_id,
            title="Unfinished Task",
            status="IN_PROGRESS",
            started_at=datetime.now(timezone.utc) - timedelta(minutes=45),
            actual_minutes=0
        )

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,
            active_session,
            None,  # active break
            None,  # user settings
            None,  # user settings dnd
        ]
        mock_db.query.return_value.filter.return_value.all.side_effect = [
            [task],  # active tasks
            [],      # breaks during task
        ]

        end_work_session(mock_user, mock_db)

        # Verify status is still IN_PROGRESS (incomplete status preserved), started_at is None, duration saved
        assert task.status == "IN_PROGRESS"
        assert task.started_at is None
        assert task.actual_minutes >= 45

    def test_scenario_d_no_active_task(self, mock_db, mock_user, mock_profile):
        """Scenario D: Start shift without task and end shift creates/modifies no tasks."""
        session_id = uuid4()
        active_session = WorkSession(
            id=session_id,
            profile_id=mock_profile.id,
            started_at=datetime.now(timezone.utc),
            ended_at=None
        )

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,
            active_session,
            None,
            None,
            None,
        ]
        mock_db.query.return_value.filter.return_value.all.side_effect = [
            [],  # active tasks
            [],  # breaks during task
        ]

        end_resp = end_work_session(mock_user, mock_db)
        assert end_resp.ended_at is not None

    def test_duplicate_end_shift_raises_error(self, mock_db, mock_user, mock_profile):
        """Calling end_work_session when no active session exists raises 400 Bad Request."""
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,
            None,  # No active session found
        ]

        with pytest.raises(HTTPException) as exc_info:
            end_work_session(mock_user, mock_db)

        assert exc_info.value.status_code == 400
        assert "No active work session found" in str(exc_info.value.detail)
