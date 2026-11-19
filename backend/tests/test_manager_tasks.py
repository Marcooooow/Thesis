import pytest
from fastapi import HTTPException
from unittest.mock import MagicMock
from uuid import uuid4
from datetime import datetime, timezone

from app.models import Task, Profile, User, Team, TeamMembership
from app.routers.work import assign_manager_task, _validate_manager_team_access, get_manager_team_tasks
from app.schemas.work import ManagerTaskAssignRequest, TaskCreateRequest


class TestManagerTasksImplementation:

    def test_validate_manager_team_access_admin(self):
        db = MagicMock()
        admin = User(id=uuid4(), role="ADMIN")
        target_profile = Profile(id=uuid4(), user_id=uuid4())
        db.query.return_value.filter.return_value.first.return_value = target_profile

        profile = _validate_manager_team_access(db, admin, target_profile.id)
        assert profile == target_profile

    def test_validate_manager_team_access_unauthorized_manager(self):
        db = MagicMock()
        manager = User(id=uuid4(), role="MANAGER")
        target_profile = Profile(id=uuid4(), user_id=uuid4())

        # First query for target_profile
        db.query.return_value.filter.return_value.first.return_value = target_profile
        # Second query for manager_teams returns empty
        db.query.return_value.filter.return_value.all.return_value = []

        with pytest.raises(HTTPException) as exc_info:
            _validate_manager_team_access(db, manager, target_profile.id)
        assert exc_info.value.status_code == 403

    def test_employee_cannot_create_work_task_or_assigner(self):
        # Test Pydantic validation rejection of forbidden fields
        with pytest.raises(ValueError):
            TaskCreateRequest(
                title="Test Task",
                assigned_by_user_id=uuid4()
            )

        with pytest.raises(ValueError):
            TaskCreateRequest(
                title="Test Task",
                task_type="WORK"
            )

    def test_get_manager_team_tasks(self):
        db = MagicMock()
        manager = User(id=uuid4(), role="MANAGER")
        team = Team(id=uuid4(), manager_user_id=manager.id)
        membership = TeamMembership(team_id=team.id, profile_id=uuid4())

        db.query.return_value.filter.return_value.all.side_effect = [
            [team],
            [membership],
        ]
        db.query.return_value.filter.return_value.order_by.return_value.all.return_value = [
            Task(id=uuid4(), profile_id=membership.profile_id, title="Test", task_type="WORK", status="TODO")
        ]

        tasks = get_manager_team_tasks(current_user=manager, db=db)
        assert len(tasks) == 1
        assert tasks[0].title == "Test"
