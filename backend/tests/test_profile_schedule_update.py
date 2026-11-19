from datetime import date, time, timedelta

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy.orm import Session

from app.models import EmployeeSchedule, Profile, User
from app.routers.profile import get_current_user_profile, update_current_user_profile
from app.schemas.profile import ProfileUpdateRequest


def _create_active_schedule(test_db: Session, user: User):
    profile = test_db.query(Profile).filter_by(user_id=user.id).one()
    profile.shift_start_time = time(8, 0)
    profile.shift_end_time = time(17, 0)
    profile.work_days = ["monday", "tuesday", "wednesday", "thursday", "friday"]
    profile.job_role = "Engineer"
    profile.target_daily_hours = 8
    schedule = EmployeeSchedule(
        profile_id=profile.id,
        effective_from=date.today() - timedelta(days=1),
        work_days=profile.work_days,
        shift_start=time(8, 0),
        shift_end=time(17, 0),
        timezone="Asia/Manila",
        created_by=user.id,
    )
    test_db.add(schedule)
    test_db.commit()
    test_db.refresh(schedule)
    return profile, schedule


@pytest.mark.parametrize(
    ("changes", "expected_start", "expected_end"),
    [
        ({"shift_start_time": "09:15"}, time(9, 15), time(17, 0)),
        ({"shift_end_time": "18:15"}, time(8, 0), time(18, 15)),
        (
            {"shift_start_time": "10:00", "shift_end_time": "19:00"},
            time(10, 0),
            time(19, 0),
        ),
    ],
)
def test_schedule_time_updates_persist_without_overwriting_other_profile_fields(
    test_db: Session,
    test_user: User,
    changes: dict,
    expected_start: time,
    expected_end: time,
):
    profile, schedule = _create_active_schedule(test_db, test_user)

    update_current_user_profile(
        ProfileUpdateRequest(**changes),
        current_user=test_user,
        db=test_db,
    )

    test_db.expire_all()
    stored_schedule = test_db.query(EmployeeSchedule).filter_by(id=schedule.id).one()
    stored_profile = test_db.query(Profile).filter_by(user_id=test_user.id).one()
    retrieved_profile = get_current_user_profile(test_user, test_db)

    assert stored_schedule.shift_start == expected_start
    assert stored_schedule.shift_end == expected_end
    assert retrieved_profile["shift_start_time"] == expected_start.strftime("%H:%M")
    assert retrieved_profile["shift_end_time"] == expected_end.strftime("%H:%M")
    assert stored_profile.job_role == "Engineer"
    assert stored_profile.target_daily_hours == 8
    assert stored_schedule.updated_at.tzinfo is not None
    assert stored_schedule.updated_at.utcoffset() == timedelta(0)


def test_partial_schedule_update_rejects_equal_effective_times(
    test_db: Session,
    test_user: User,
):
    profile, schedule = _create_active_schedule(test_db, test_user)

    with pytest.raises(HTTPException) as exc_info:
        update_current_user_profile(
            ProfileUpdateRequest(shift_start_time="17:00"),
            current_user=test_user,
            db=test_db,
        )

    assert exc_info.value.status_code == 400
    test_db.refresh(profile)
    test_db.refresh(schedule)
    assert profile.shift_start_time == time(8, 0)
    assert schedule.shift_start == time(8, 0)


def test_invalid_shift_time_format_is_rejected():
    with pytest.raises(ValidationError):
        ProfileUpdateRequest(shift_start_time="25:00")
