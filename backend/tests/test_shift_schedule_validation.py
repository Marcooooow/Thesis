"""Unit tests for shift schedule validation logic."""
import pytest
from datetime import time
from pydantic import ValidationError
from app.schemas.profile import ProfileUpdateRequest


def test_normal_daytime_schedule_08_to_17():
    """8:00 AM → 5:00 PM (normal same-day schedule) should succeed."""
    request = ProfileUpdateRequest(
        shift_start_time="08:00",
        shift_end_time="17:00",
        work_days=["monday", "tuesday", "wednesday", "thursday", "friday"]
    )
    assert request.shift_start_time == "08:00"
    assert request.shift_end_time == "17:00"


def test_afternoon_schedule_13_to_22():
    """1:00 PM → 10:00 PM (normal same-day schedule) should succeed."""
    request = ProfileUpdateRequest(
        shift_start_time="13:00",
        shift_end_time="22:00",
        work_days=["monday", "tuesday", "wednesday", "thursday", "friday"]
    )
    assert request.shift_start_time == "13:00"
    assert request.shift_end_time == "22:00"


def test_overnight_schedule_22_to_06():
    """10:00 PM → 6:00 AM (overnight schedule) should succeed."""
    request = ProfileUpdateRequest(
        shift_start_time="22:00",
        shift_end_time="06:00",
        work_days=["monday", "tuesday", "wednesday", "thursday", "friday"]
    )
    assert request.shift_start_time == "22:00"
    assert request.shift_end_time == "06:00"


def test_overnight_schedule_23_to_07():
    """11:00 PM → 7:00 AM (overnight schedule) should succeed."""
    request = ProfileUpdateRequest(
        shift_start_time="23:00",
        shift_end_time="07:00",
        work_days=["monday", "tuesday", "wednesday", "thursday", "friday"]
    )
    assert request.shift_start_time == "23:00"
    assert request.shift_end_time == "07:00"


def test_equal_times_22_to_22_rejected():
    """10:00 PM → 10:00 PM (equal start and end) should be rejected."""
    with pytest.raises(ValidationError) as exc_info:
        ProfileUpdateRequest(
            shift_start_time="22:00",
            shift_end_time="22:00",
            work_days=["monday", "tuesday", "wednesday", "thursday", "friday"]
        )
    errors = exc_info.value.errors()
    assert len(errors) > 0
    assert any("equal" in str(error).lower() or "cannot" in str(error).lower() for error in errors)


def test_equal_times_08_to_08_rejected():
    """8:00 AM → 8:00 AM (equal start and end) should be rejected."""
    with pytest.raises(ValidationError) as exc_info:
        ProfileUpdateRequest(
            shift_start_time="08:00",
            shift_end_time="08:00"
        )
    errors = exc_info.value.errors()
    assert len(errors) > 0
    assert any("equal" in str(error).lower() or "cannot" in str(error).lower() for error in errors)
