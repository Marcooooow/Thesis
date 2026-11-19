
import pytest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock
from uuid import uuid4
from app.models import Task, WorkSession
from app.routers.work import update_task_status

class TestTaskResumeRegression:

    def test_resume_in_progress_task_in_new_session(self):
        """Regression test: Task already IN_PROGRESS should update to new WorkSession ID."""

        # 1. Setup
        profile_id = uuid4()
        old_session_id = uuid4()
        new_session_id = uuid4()
        task_id = uuid4()
        now = datetime.now(timezone.utc)

        # Original task: IN_PROGRESS in Session 1, 42 minutes accumulated
        task = Task(
            id=task_id,
            profile_id=profile_id,
            work_session_id=old_session_id,
            status='IN_PROGRESS',
            started_at=now - timedelta(minutes=42),
            actual_minutes=42,
            title="Test Task",
            description="Test task description",
            category="Work",
            priority="Medium",
        )

        # Mock DB
        db = MagicMock()
        db.query.return_value.filter.return_value.first.side_effect = [
            MagicMock(id=profile_id), # Profile query
            task,                     # Task query
            MagicMock(id=new_session_id) # New Active WorkSession
        ]

        # Mock User
        current_user = MagicMock(id=uuid4())

        # 2. Action
        status_data = MagicMock(status='IN_PROGRESS')

        # Trigger the status update
        update_task_status(task_id, status_data, current_user, db)

        # 3. Verify
        assert task.work_session_id == new_session_id
        assert task.status == 'IN_PROGRESS'
        assert task.actual_minutes == 42 # Unchanged
        # started_at should remain unchanged because it wasn't null
        assert task.started_at == now - timedelta(minutes=42)
