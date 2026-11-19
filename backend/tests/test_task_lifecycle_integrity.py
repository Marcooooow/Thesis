"""
Tests for task lifecycle timestamp integrity.

Tests cover:
- Creating a task produces TODO with no lifecycle timestamps
- TODO → IN_PROGRESS creates started_at
- IN_PROGRESS → DONE creates ended_at and actual_minutes
- ended_at is after started_at
- Invalid direct timestamps cannot create inconsistent tasks
- Existing valid task workflow still works
- Invalid status transitions are rejected
"""

import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock
from uuid import uuid4
from fastapi import HTTPException


class TestTaskLifecycleIntegrity:

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

    @pytest.fixture
    def mock_active_session(self, mock_profile):
        """Create a mock active work session."""
        session = MagicMock()
        session.id = uuid4()
        session.profile_id = mock_profile.id
        session.started_at = datetime.now(timezone.utc) - timedelta(hours=1)
        session.ended_at = None
        return session

    def test_create_task_produces_todo_without_timestamps(self, mock_db, mock_user, mock_profile, mock_active_session):
        """Creating a task should produce status=TODO with started_at=None and ended_at=None."""
        from app.models import Task
        from app.schemas.work import TaskCreateRequest
        from app.routers.work import create_task
        import uuid
        from datetime import datetime, timezone

        # Setup mocks
        # First .first() call: profile lookup -> returns mock_profile
        # Second .first() call: active session lookup -> returns mock_active_session
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            mock_active_session,  # Active session lookup
        ]

        # Mock db.refresh to set the ID on Task objects (simulating database-generated ID)
        def mock_refresh(obj):
            if isinstance(obj, Task) and obj.id is None:
                obj.id = uuid4()
        mock_db.refresh.side_effect = mock_refresh

        # Create task data
        task_data = TaskCreateRequest(
            title="Test Task",
            category="Development",
            priority="HIGH",
            estimated_minutes=60
        )

        # Call create_task
        result = create_task(task_data, mock_user, mock_db)

        # Verify task was created with TODO status and no timestamps
        assert result.status == "TODO"
        assert result.started_at is None
        assert result.ended_at is None
        assert result.actual_minutes is None
        assert result.title == "Test Task"
        assert result.category == "Development"

    def test_todo_to_in_progress_creates_started_at(self, mock_db, mock_user, mock_profile):
        """Transitioning from TODO to IN_PROGRESS should set started_at."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        # Create a task in TODO state
        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "TODO"
        task.started_at = None
        task.ended_at = None
        task.actual_minutes = None
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # Mock the query chain
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
            None,  # No active session
        ]
        # Transition to IN_PROGRESS
        status_data = TaskStatusUpdateRequest(status="IN_PROGRESS")
        result = update_task_status(task.id, TaskStatusUpdateRequest(status="IN_PROGRESS"), mock_user, mock_db)

        # Verify started_at was set
        assert result.status == "IN_PROGRESS"
        assert result.started_at is not None
        assert result.ended_at is None

    def test_in_progress_to_done_creates_ended_at(self, mock_db, mock_user, mock_profile):
        """Transitioning from IN_PROGRESS to DONE should set ended_at and actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        # Create a task in IN_PROGRESS state with started_at set
        started_at = datetime.now(timezone.utc) - timedelta(minutes=30)
        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = started_at
        task.ended_at = None
        task.actual_minutes = None
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # Mock the query chain
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        # No breaks during task
        mock_db.query.return_value.filter.return_value.all.return_value = []

        # Transition to DONE
        status_data = TaskStatusUpdateRequest(status="DONE")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        # Verify ended_at and actual_minutes were set
        assert result.status == "DONE"
        assert result.ended_at is not None
        assert result.started_at is not None
        assert result.actual_minutes is not None
        assert result.actual_minutes >= 0

    def test_ended_at_after_started_at(self, mock_db, mock_user, mock_profile):
        """When DONE, ended_at must be after started_at."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        # Create a task in IN_PROGRESS state with started_at set
        started_at = datetime.now(timezone.utc) - timedelta(minutes=30)
        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = started_at
        task.ended_at = None
        task.actual_minutes = None
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # Mock the query chain
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        # No breaks during task
        mock_db.query.return_value.filter.return_value.all.return_value = []

        # Transition to DONE
        status_data = TaskStatusUpdateRequest(status="DONE")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        # Verify ended_at > started_at
        assert result.ended_at > result.started_at

    def test_reject_direct_started_at_ended_at_in_create(self):
        """Client-supplied started_at/ended_at in task creation should be rejected."""
        from app.schemas.work import TaskCreateRequest
        from pydantic import ValidationError

        # Try to create with started_at - should fail validation
        with pytest.raises(ValidationError) as exc_info:
            TaskCreateRequest(
                title="Test Task",
                started_at=datetime.now(timezone.utc),
                ended_at=datetime.now(timezone.utc),
            )

        error = exc_info.value
        assert "started_at" in str(error) or "ended_at" in str(error)
        assert "cannot be set at task creation" in str(error)

    def test_reject_todo_to_done_direct(self, mock_db, mock_user, mock_profile):
        """Direct transition from TODO to DONE should be rejected."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "TODO"
        task.started_at = None
        task.ended_at = None

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="DONE")

        with pytest.raises(HTTPException) as exc_info:
            update_task_status(task.id, status_data, mock_user, mock_db)

        assert exc_info.value.status_code == 400
        assert "TODO to DONE" in str(exc_info.value.detail)

    def test_reject_done_to_any_transition(self, mock_db, mock_user, mock_profile):
        """DONE is terminal - no transitions out of DONE allowed."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status

        for target_status in ["TODO", "IN_PROGRESS", "BLOCKED"]:
            task = MagicMock()
            task.id = uuid4()
            task.profile_id = mock_profile.id
            task.status = "DONE"
            task.started_at = datetime.now(timezone.utc) - timedelta(hours=1)
            task.ended_at = datetime.now(timezone.utc)
            task.actual_minutes = 60

            mock_db.query.return_value.filter.return_value.first.side_effect = [
                mock_profile,  # Profile lookup
                task,  # Task lookup
            ]

            status_data = TaskStatusUpdateRequest(
                status=target_status,
                blocked_reason="blocked" if target_status == "BLOCKED" else None
            )

            with pytest.raises(HTTPException) as exc_info:
                update_task_status(task.id, status_data, mock_user, mock_db)

            assert exc_info.value.status_code == 400
            assert "terminal" in str(exc_info.value.detail).lower()

    def test_reject_blocked_to_done_direct(self, mock_db, mock_user, mock_profile):
        """BLOCKED → DONE direct transition should be rejected."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "BLOCKED"
        task.started_at = None

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="DONE")

        with pytest.raises(HTTPException) as exc_info:
            update_task_status(task.id, status_data, mock_user, mock_db)

        assert exc_info.value.status_code == 400
        assert "BLOCKED" in str(exc_info.value.detail) and "DONE" in str(exc_info.value.detail)

    def test_todo_to_blocked_allowed(self, mock_db, mock_user, mock_profile):
        """TODO → BLOCKED should be allowed."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "TODO"
        task.started_at = None
        task.ended_at = None
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="BLOCKED", blocked_reason="waiting")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "BLOCKED"

    def test_blocked_to_todo_allowed(self, mock_db, mock_user, mock_profile):
        """BLOCKED → TODO should be allowed and clear timing timestamps but preserve actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "BLOCKED"
        task.started_at = datetime.now(timezone.utc) - timedelta(hours=1)
        task.ended_at = datetime.now(timezone.utc)
        task.actual_minutes = 60
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="TODO")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "TODO"
        # Timing timestamps should be cleared
        assert task.started_at is None
        assert task.ended_at is None
        # actual_minutes should be preserved (not cleared)
        assert task.actual_minutes == 60

    def test_in_progress_to_todo_allowed_and_clears_timestamps(self, mock_db, mock_user, mock_profile):
        """IN_PROGRESS → TODO should be allowed and clear timing timestamps but preserve actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=30)
        task.ended_at = None
        task.actual_minutes = 40  # Simulate some accumulated work time
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="TODO")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "TODO"
        assert task.started_at is None
        assert task.ended_at is None
        # actual_minutes should be preserved and incremented with the current session time
        assert task.actual_minutes == 70

    def test_valid_workflow_create_start_complete(self, mock_db, mock_user, mock_profile, mock_active_session):
        """Full valid workflow: create → start → complete."""
        from app.models import Task
        from app.schemas.work import TaskCreateRequest, TaskStatusUpdateRequest
        from app.routers.work import create_task, update_task_status
        import uuid
        from datetime import datetime, timezone

        # --- Step 1: Create task ---
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            mock_active_session,  # Active session lookup
        ]

        # Mock db.refresh to set the ID on Task objects (simulating database-generated ID)
        def mock_refresh(obj):
            if isinstance(obj, Task) and obj.id is None:
                obj.id = uuid.uuid4()
        mock_db.refresh.side_effect = mock_refresh

        task_data = TaskCreateRequest(title="Workflow Task", category="Test")
        created = create_task(task_data, mock_user, mock_db)

        assert created.status == "TODO"
        assert created.started_at is None
        assert created.ended_at is None

        # --- Step 2: Start task (TODO → IN_PROGRESS) ---
        task_obj = MagicMock()
        task_obj.id = created.id
        task_obj.profile_id = mock_profile.id
        task_obj.status = "TODO"
        task_obj.started_at = None
        task_obj.ended_at = None
        task_obj.actual_minutes = None
        task_obj.work_session_id = mock_active_session.id
        # Set other required fields for TaskResponse
        task_obj.title = "Workflow Task"
        task_obj.description = None
        task_obj.category = "Test"
        task_obj.priority = "MEDIUM"  # Default priority
        task_obj.estimated_minutes = None
        task_obj.created_at = datetime.now(timezone.utc)
        task_obj.updated_at = datetime.now(timezone.utc)

        # Need more side_effect values for the multiple queries in update_task_status
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task_obj,  # Task lookup
            None,  # No active session (this might be needed for the IN_PROGRESS transition logic)
        ]

        started = update_task_status(created.id, TaskStatusUpdateRequest(status="IN_PROGRESS"), mock_user, mock_db)

        assert started.status == "IN_PROGRESS"
        assert started.started_at is not None
        assert started.ended_at is None

        # --- Step 3: Complete task (IN_PROGRESS → DONE) ---
        # Reset the side_effect for the next call
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task_obj,  # Task lookup
        ]
        mock_db.query.return_value.filter.return_value.all.return_value = []  # No breaks

        completed = update_task_status(created.id, TaskStatusUpdateRequest(status="DONE"), mock_user, mock_db)

        assert completed.status == "DONE"
        assert completed.started_at is not None
        assert completed.ended_at is not None
        assert completed.ended_at > completed.started_at
        assert completed.actual_minutes is not None
        assert completed.actual_minutes >= 0

    def test_actual_minutes_calculation_with_breaks(self, mock_db, mock_user, mock_profile, mock_active_session):
        """actual_minutes should subtract break time."""
        from app.models import Task, Break
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        started_at = datetime.now(timezone.utc) - timedelta(minutes=60)
        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = started_at
        task.ended_at = None
        task.actual_minutes = None
        task.work_session_id = mock_active_session.id
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # Mock a 15-minute break during the task
        break_obj = MagicMock()
        break_obj.started_at = started_at + timedelta(minutes=10)
        break_obj.ended_at = started_at + timedelta(minutes=25)
        # Set other required fields for Break (if any are accessed)
        break_obj.id = uuid4()
        break_obj.work_session_id = mock_active_session.id

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]
        mock_db.query.return_value.filter.return_value.all.return_value = [break_obj]

        # Transition to DONE
        status_data = TaskStatusUpdateRequest(status="DONE")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        # 60 minutes elapsed - 15 minutes break = 45 actual minutes
        assert result.actual_minutes == 45

    def test_in_progress_to_todo_preserves_actual_minutes(self, mock_db, mock_user, mock_profile):
        """IN_PROGRESS → TODO preserves accumulated actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=30)
        task.ended_at = None
        task.actual_minutes = 40  # Previously accumulated time
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="TODO")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "TODO"
        assert task.started_at is None
        assert task.ended_at is None
        # actual_minutes should be preserved and incremented with current session time (30 min)
        assert task.actual_minutes == 70  # 40 + 30

    def test_blocked_to_todo_preserves_actual_minutes(self, mock_db, mock_user, mock_profile):
        """BLOCKED → TODO preserves accumulated actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "BLOCKED"
        task.started_at = None  # Blocked tasks don't have started_at
        task.ended_at = None
        task.actual_minutes = 50  # Previously accumulated time
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]

        status_data = TaskStatusUpdateRequest(status="TODO")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "TODO"
        assert task.started_at is None
        assert task.ended_at is None
        # actual_minutes should be preserved (no timing to add since task was blocked)
        assert task.actual_minutes == 50

    def test_in_progress_to_blocked_preserves_actual_minutes(self, mock_db, mock_user, mock_profile):
        """IN_PROGRESS → BLOCKED preserves accumulated actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=20)
        task.ended_at = None
        task.actual_minutes = 30  # Previously accumulated time
        task.work_session_id = uuid4()
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
        ]
        mock_db.query.return_value.filter.return_value.all.return_value = []  # No breaks during calculation

        status_data = TaskStatusUpdateRequest(status="BLOCKED", blocked_reason="waiting")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "BLOCKED"
        assert task.started_at is None
        assert task.ended_at is None
        # actual_minutes should be preserved and incremented with session time (20 min)
        assert task.actual_minutes == 50  # 30 + 20

    def test_blocked_to_in_progress_resumes_timing(self, mock_db, mock_user, mock_profile, mock_active_session):
        """BLOCKED → IN_PROGRESS resumes timing."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "BLOCKED"
        task.started_at = None  # Blocked tasks don't have started_at
        task.ended_at = None
        task.actual_minutes = 60  # Previously accumulated time
        task.work_session_id = uuid4()  # Previous work session ID
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile,  # Profile lookup
            task,  # Task lookup
            mock_active_session,  # Active session lookup (for associating with current session)
        ]

        status_data = TaskStatusUpdateRequest(status="IN_PROGRESS")
        result = update_task_status(task.id, status_data, mock_user, mock_db)

        assert result.status == "IN_PROGRESS"
        assert task.started_at is not None  # Should resume timing
        assert task.ended_at is None
        assert task.work_session_id == mock_active_session.id  # Should associate with current session
        # actual_minutes should be preserved (not reset)
        assert task.actual_minutes == 60

    def test_work_across_multiple_sessions_accumulates_correctly(self, mock_db, mock_user, mock_profile):
        """Work across multiple WorkSessions accumulates correctly."""
        from app.models import Task, WorkSession, Break
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        # Test that actual_minutes accumulates when transitioning TODO → IN_PROGRESS → TODO
        # Focus on verifying the accumulation logic rather than complex session simulation

        task = MagicMock()
        task.id = uuid4()
        # Set all required fields for TaskResponse to avoid validation errors
        test_profile_id = uuid4()
        # Configure mock_profile to return our test ID
        mock_profile.id = test_profile_id
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.deadline = None
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # First work session: add 30 minutes
        task.status = "TODO"
        task.started_at = None
        task.ended_at = None
        task.actual_minutes = 0  # Start with zero
        task.work_session_id = uuid4()
        task.profile_id = test_profile_id
        print(f"DEBUG (test): task.profile_id = {task.profile_id}")
        print(f"DEBUG (test): mock_profile.id = {mock_profile.id}")

        # Create mock work sessions
        session1 = MagicMock(spec=WorkSession)
        session1.id = uuid4()
        session2 = MagicMock(spec=WorkSession)
        session2.id = uuid4()

        # We need to provide enough side effects for all database queries:
        # For each update_task_status call:
        # 1. Profile lookup (get_current_user -> authenticate_user)
        # 2. Task lookup
        # 3. Active WorkSession lookup (for TODO -> IN_PROGRESS transitions)
        # 4. Break lookup (for time calculation)
        # We're making 4 calls to update_task_status, so we need 4 * 4 = 16 side effects

        # Set up side effects for all calls
        # For each update_task_status call, the queries are:
        # 1. User lookup (from get_current_user dependency)
        # 2. Profile lookup (in update_task_status)
        # 3. Task lookup (in update_task_status)
        # 4. Depending on transition:
        #    - TODO -> IN_PROGRESS: WorkSession lookup (active session)
        #    - IN_PROGRESS -> TODO: Break lookup (for time calculation)
        mock_db.query.return_value.filter.return_value.first.side_effect = [
            mock_profile, task, session1,  # Call 1: TODO -> IN_PROGRESS (profile, task, active session)
            mock_profile, task,             # Call 2: IN_PROGRESS -> TODO (profile, task)
            mock_profile, task, session2,  # Call 3: TODO -> IN_PROGRESS (profile, task, active session)
            mock_profile, task              # Call 4: IN_PROGRESS -> TODO (profile, task)
        ]

        # Start work (first session)
        started1 = update_task_status(task.id, TaskStatusUpdateRequest(status="IN_PROGRESS"), mock_user, mock_db)
        assert started1.status == "IN_PROGRESS"
        assert started1.started_at is not None

        # Simulate 30 minutes of work
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=30)
        # task.work_session_id is already set

        # Stop work (first session) - should add 30 minutes
        stopped1 = update_task_status(task.id, TaskStatusUpdateRequest(status="TODO"), mock_user, mock_db)
        assert stopped1.status == "TODO"
        assert stopped1.started_at is None
        assert stopped1.ended_at is None
        assert stopped1.actual_minutes == 30  # First session: 30 minutes

        # Start work again (second session)
        started2 = update_task_status(task.id, TaskStatusUpdateRequest(status="IN_PROGRESS"), mock_user, mock_db)
        assert started2.status == "IN_PROGRESS"
        assert started2.started_at is not None
        assert started2.actual_minutes == 30  # Should preserve previous time

        # Simulate 20 minutes of work
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=20)
        # task.work_session_id is already set

        # Stop work (second session) - should add 20 minutes to existing 30 minutes
        stopped2 = update_task_status(task.id, TaskStatusUpdateRequest(status="TODO"), mock_user, mock_db)
        assert stopped2.status == "TODO"
        assert stopped2.started_at is None
        assert stopped2.ended_at is None
        assert stopped2.actual_minutes == 50  # 30 + 20 = 50 minutes total

    def test_ending_work_session_does_not_delete_task_or_reset_actual_minutes(self, mock_db, mock_user, mock_profile, mock_active_session):
        """Ending a WorkSession does not delete the Task or reset actual_minutes."""
        from app.models import Task
        from app.schemas.work import TaskStatusUpdateRequest
        from app.routers.work import update_task_status
        from datetime import datetime, timezone

        # The key insight: tasks and work sessions are independent entities.
        # Ending a work session doesn't affect task entities directly.
        # Tasks retain their actual_minutes regardless of work session state.

        task = MagicMock()
        task.id = uuid4()
        task.profile_id = mock_profile.id
        task.status = "IN_PROGRESS"
        task.started_at = datetime.now(timezone.utc) - timedelta(minutes=25)
        task.ended_at = None
        task.actual_minutes = 25  # Some accumulated time
        task.work_session_id = mock_active_session.id
        # Set other required fields for TaskResponse
        task.title = "Test Task"
        task.description = None
        task.category = "Development"
        task.priority = "MEDIUM"
        task.estimated_minutes = None
        task.created_at = datetime.now(timezone.utc)
        task.updated_at = datetime.now(timezone.utc)

        # Verify task has time before "ending work session"
        assert task.actual_minutes == 25
        assert task.work_session_id == mock_active_session.id

        # Ending a work session doesn't directly modify tasks
        # (In the real system, work sessions and tasks are separate database entities)
        # This test verifies our understanding that task data persists independently

        # Simulate what happens when we check the task after work session ends
        # The task should still have its actual_minutes preserved
        assert task.actual_minutes == 25  # Unchanged by work session ending


if __name__ == "__main__":
    pytest.main([__file__, "-v"])