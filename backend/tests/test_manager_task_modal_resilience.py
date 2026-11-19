import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app
from app.models import User, Profile, Task
from app.auth.security import create_access_token

client = TestClient(app)

def test_manager_task_serialization_and_employee_visibility(test_db: Session):
    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    employee03 = test_db.query(User).filter(User.email == "thesis.employee03@intellibreak.local").first()
    employee01 = test_db.query(User).filter(User.email == "thesis.employee01@intellibreak.local").first()

    assert manager is not None
    assert employee03 is not None
    assert employee01 is not None

    emp03_profile = test_db.query(Profile).filter(Profile.user_id == employee03.id).first()
    assert emp03_profile is not None

    # 1. Create a WORK task assigned to employee 03 by manager 01
    work_task = Task(
        profile_id=emp03_profile.id,
        assigned_by_user_id=manager.id,
        task_type="WORK",
        title="Serialization Test Task",
        status="TODO",
        priority="HIGH"
    )
    test_db.add(work_task)
    test_db.commit()

    emp03_token = create_access_token({"sub": str(employee03.id)})
    emp01_token = create_access_token({"sub": str(employee01.id)})

    # 2. Employee 03 retrieves task history -> should contain WORK task with serialized task_type and assigned_by_user_id
    response = client.get(
        "/work/tasks/history",
        headers={"Authorization": f"Bearer {emp03_token}"}
    )
    assert response.status_code == 200
    tasks = response.json()

    found_work_task = None
    for t in tasks:
        if t["title"] == "Serialization Test Task":
            found_work_task = t
            break

    assert found_work_task is not None
    assert found_work_task["task_type"] == "WORK"
    assert found_work_task["assigned_by_user_id"] == str(manager.id)

    # 3. Employee 01 cannot see Employee 03's tasks (isolation check)
    response_emp01 = client.get(
        "/work/tasks/history",
        headers={"Authorization": f"Bearer {emp01_token}"}
    )
    assert response_emp01.status_code == 200
    tasks_emp01 = response_emp01.json()
    for t in tasks_emp01:
        assert t["title"] != "Serialization Test Task"
