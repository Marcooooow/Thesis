import uuid
import pytest
from datetime import date
from sqlalchemy import func

from app.models import User, Organization, OrganizationMembership, Team, TeamMembership, WorkSession, Break, Task, Recommendation, RecommendationFeedback, SessionWellbeingCheckin, Profile, SystemActivityLog, LeaveRequest, AbsenceRecord
from app.services.historical_behavioral_generator import generate_historical_behavioral_dataset


def test_calibrated_historical_dataset_exact_counts(test_db):
    admin = User(
        email=f"cal-admin-{uuid.uuid4()}@test.local",
        full_name="Calibration Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name=f"Calibration Defense Org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    summary = generate_historical_behavioral_dataset(
        test_db,
        current_user=admin,
        organization_name=org.name,
        start_date=date(2026, 8, 1),
        end_date=date(2026, 11, 16),
        num_managers=5,
        num_employees=24,
        num_teams=5,
    )

    assert summary["managers_created"] == 5
    assert summary["employees_created"] == 24
    assert summary["teams_created"] == 5
    assert not summary["errors"]

    # Exact counts
    counts = {
        'users': test_db.query(User).count(),
        'admins': test_db.query(User).filter_by(role="ADMIN").count(),
        'managers': test_db.query(User).filter_by(role="MANAGER").count(),
        'employees': test_db.query(User).filter_by(role="EMPLOYEE").count(),
        'organizations': test_db.query(Organization).count(),
        'teams': test_db.query(Team).count(),
        'organization_memberships': test_db.query(OrganizationMembership).count(),
        'team_memberships': test_db.query(TeamMembership).count(),
        'work_sessions': test_db.query(WorkSession).count(),
        'breaks': test_db.query(Break).count(),
        'tasks': test_db.query(Task).count(),
        'recommendations': test_db.query(Recommendation).count(),
        'recommendation_feedback': test_db.query(RecommendationFeedback).count(),
        'session_wellbeing_checkins': test_db.query(SessionWellbeingCheckin).count(),
    }
    print("EXACT COUNTS:", counts)

    assert counts['users'] == 30
    assert counts['admins'] == 1
    assert counts['managers'] == 5
    assert counts['employees'] == 24
    assert counts['organizations'] == 1
    assert counts['teams'] == 5
    assert counts['organization_memberships'] == 30
    assert counts['team_memberships'] == 24  # 24 employees assigned to teams
    assert counts['work_sessions'] > 0
    assert counts['breaks'] > 0
    assert counts['tasks'] > 0
    assert counts['recommendations'] > 0
    assert counts['recommendation_feedback'] > 0
    assert counts['session_wellbeing_checkins'] > 0

    # Date coverage
    ws = test_db.query(WorkSession).all()
    starts = [w.started_at for w in ws]
    ends = [w.ended_at for w in ws]
    print("FIRST_START:", min(starts).isoformat(), "LAST_START:", max(starts).isoformat())
    print("WORK_DAYS_COVERED:", len({w.started_at.date() for w in ws}))
    print("OUTSIDE_PERIOD:", sum(1 for x in starts if x.date() < date(2026, 8, 1) or x.date() > date(2026, 11, 16)))
    print("WEEKEND_SESSIONS:", sum(1 for w in ws if w.started_at.weekday() >= 5))

    # Integrity checks
    breaks = test_db.query(Break).all()
    sessions_by_id = {w.id: w for w in ws}
    print("BREAK_OUTSIDE_SESSION:", sum(1 for b in breaks if b.started_at < sessions_by_id[b.work_session_id].started_at or b.ended_at > sessions_by_id[b.work_session_id].ended_at or b.ended_at <= b.started_at))

    feedbacks = test_db.query(RecommendationFeedback).all()
    rec_ids = {r.id for r in test_db.query(Recommendation).all()}
    print("FEEDBACK_INVALID_REC:", sum(1 for f in feedbacks if f.recommendation_id not in rec_ids))

    tasks = test_db.query(Task).all()
    print("TASKS_WITH_SESSION:", sum(1 for t in tasks if t.work_session_id is not None))

    checkins = test_db.query(SessionWellbeingCheckin).all()
    print("CHECKINS_WITH_SESSION:", sum(1 for c in checkins if c.work_session_id is not None))

    print("PROFILES_TEST_DATA_TRUE:", test_db.query(Profile).filter(Profile.is_test_data.is_(True)).count(), "PROFILES_TOTAL:", test_db.query(Profile).count())
    print("FEEDBACK_TEST_FLAGS_TRUE:", sum(1 for f in feedbacks if f.context_features.get('is_test_data') is True and f.context_features.get('dev_demo') is True), "FEEDBACK_TOTAL:", len(feedbacks))

    assert counts['work_sessions'] > 0
    assert counts['breaks'] > 0
    assert counts['tasks'] > 0
    assert counts['recommendations'] > 0
    assert counts['recommendation_feedback'] > 0
    assert counts['session_wellbeing_checkins'] > 0
