import pytest
from datetime import datetime, timedelta, timezone, date
from sqlalchemy.orm import Session
from app.models import User, Profile, Team, TeamMembership, WorkSession, Break
from seed_thesis_demo_dataset import seed_thesis_dataset
from app.auth.security import create_access_token

@pytest.fixture(autouse=True)
def run_thesis_seeder(test_db: Session):
    seed_thesis_dataset(test_db)

def test_zero_active_sessions_means_zero_working(test_db: Session):
    # Ensure all active sessions are ended
    test_db.query(WorkSession).update({WorkSession.ended_at: datetime.now(timezone.utc)})
    test_db.commit()

    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    memberships = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).all()

    working_count = 0
    for m in memberships:
        active_session = test_db.query(WorkSession).filter(
            WorkSession.profile_id == m.profile_id,
            WorkSession.ended_at.is_(None)
        ).first()
        assert active_session is None
        working_count += 1 if active_session else 0

    assert working_count == 0, "Zero active sessions must mean zero working employees"

def test_ten_demo_accounts_remain_visible_while_offline(test_db: Session):
    test_db.query(WorkSession).update({WorkSession.ended_at: datetime.now(timezone.utc)})
    test_db.commit()

    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    memberships = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).all()

    assert len(memberships) == 10, "All 10 demo accounts must remain visible"
    for m in memberships:
        active_session = test_db.query(WorkSession).filter(
            WorkSession.profile_id == m.profile_id,
            WorkSession.ended_at.is_(None)
        ).first()
        status = 'Working' if active_session else 'Offline'
        assert status == 'Offline'

def test_one_valid_active_session_produces_one_working(test_db: Session):
    test_db.query(WorkSession).update({WorkSession.ended_at: datetime.now(timezone.utc)})
    test_db.commit()

    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    membership = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).first()

    # Create one active session
    new_session = WorkSession(profile_id=membership.profile_id, started_at=datetime.now(timezone.utc), ended_at=None)
    test_db.add(new_session)
    test_db.commit()

    memberships = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).all()
    working_count = 0
    for m in memberships:
        active_session = test_db.query(WorkSession).filter(
            WorkSession.profile_id == m.profile_id,
            WorkSession.ended_at.is_(None)
        ).first()
        active_break = test_db.query(Break).filter(
            Break.work_session_id == active_session.id if active_session else None,
            Break.ended_at.is_(None)
        ).first() if active_session else None

        status = 'On Break' if active_break else ('Working' if active_session else 'Offline')
        if status == 'Working':
            working_count += 1

    assert working_count == 1, "Exactly one active session must produce KPI = 1 and one Working employee"

def test_active_break_produces_on_break_not_working(test_db: Session):
    test_db.query(WorkSession).update({WorkSession.ended_at: datetime.now(timezone.utc)})
    test_db.commit()

    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    membership = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).first()

    new_session = WorkSession(profile_id=membership.profile_id, started_at=datetime.now(timezone.utc), ended_at=None)
    test_db.add(new_session)
    test_db.commit()
    test_db.refresh(new_session)

    new_break = Break(work_session_id=new_session.id, started_at=datetime.now(timezone.utc), ended_at=None, break_type="SHORT_BREAK")
    test_db.add(new_break)
    test_db.commit()

    active_session = test_db.query(WorkSession).filter(
        WorkSession.profile_id == membership.profile_id,
        WorkSession.ended_at.is_(None)
    ).first()
    active_break = test_db.query(Break).filter(
        Break.work_session_id == active_session.id,
        Break.ended_at.is_(None)
    ).first()

    status = 'On Break' if active_break else ('Working' if active_session else 'Offline')
    assert status == 'On Break', "Active break must classify as On Break, not Working"

def test_ended_and_historical_sessions_never_produce_working(test_db: Session):
    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    membership = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).first()

    # Create ended session
    ended_session = WorkSession(
        profile_id=membership.profile_id,
        started_at=datetime.now(timezone.utc) - timedelta(hours=5),
        ended_at=datetime.now(timezone.utc) - timedelta(hours=4)
    )
    test_db.add(ended_session)
    test_db.commit()

    active_session = test_db.query(WorkSession).filter(
        WorkSession.profile_id == membership.profile_id,
        WorkSession.ended_at.is_(None)
    ).first()
    status = 'Working' if active_session else 'Offline'
    assert status == 'Offline', "Ended sessions must never produce Working status"

def test_employee_manager_detail_endpoint_logic(test_db: Session):
    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    team = test_db.query(Team).filter(Team.manager_user_id == manager.id).first()
    membership = test_db.query(TeamMembership).filter_by(team_id=team.id, left_at=None).first()
    employee_user = test_db.query(User).join(Profile).filter(Profile.id == membership.profile_id).first()

    assert employee_user is not None
    # Verify manager can resolve employee detail via wellbeing service or employee router logic
    from app.services.wellbeing_monitoring import WellbeingMonitoringService
    service = WellbeingMonitoringService(test_db)
    detail = service.compute_weekly_risk(membership.profile_id, date.today() - timedelta(days=date.today().weekday()))
    assert detail is not None
    assert detail.employee_id == membership.profile_id

