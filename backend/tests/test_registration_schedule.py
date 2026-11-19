"""
Regression test: registration must persist shift schedule onto the Profile.

Covers the end-to-end path Flutter uses: POST /auth/register with
shift_start_time / shift_end_time / work_days, then verify those values land on
the user's Profile row (not just the request body).
"""

from datetime import time
from sqlalchemy.orm import Session

from app.models import Profile, User


def _register_payload(email: str) -> dict:
    return {
        "email": email,
        "password": "securepass123",
        "full_name": "Schedule User",
        "account_type": "solo",
        "target_daily_hours": 8,
        "shift_start_time": "08:00",
        "shift_end_time": "17:00",
        "work_days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
    }


def test_registration_persists_schedule_to_profile(test_db: Session):
    from tests.test_invitation_registration import client

    response = client.post("/auth/register", json=_register_payload("sched-solo@test.com"))
    assert response.status_code == 201, response.text

    user = test_db.query(User).filter(User.email == "sched-solo@test.com").first()
    profile = test_db.query(Profile).filter(Profile.user_id == user.id).first()

    assert profile is not None, "registration must create a Profile"
    assert profile.shift_start_time is not None, "shift_start_time not persisted"
    assert profile.shift_end_time is not None, "shift_end_time not persisted"
    assert profile.work_days == [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
    ], f"work_days not persisted: {profile.work_days!r}"
    assert profile.shift_start_time == time(8, 0)
    assert profile.shift_end_time == time(17, 0)


def test_registration_persists_schedule_for_organization(test_db: Session):
    from tests.test_invitation_registration import client

    payload = _register_payload("sched-org@test.com")
    payload["account_type"] = "organization"
    payload["organization_name"] = "Schedule Org"

    response = client.post("/auth/register", json=payload)
    assert response.status_code == 201, response.text

    user = test_db.query(User).filter(User.email == "sched-org@test.com").first()
    profile = test_db.query(Profile).filter(Profile.user_id == user.id).first()

    assert profile is not None
    assert profile.shift_start_time is not None
    assert profile.shift_end_time is not None
    assert profile.work_days is not None and len(profile.work_days) == 5
    assert profile.shift_start_time == time(8, 0)
    assert profile.shift_end_time == time(17, 0)
