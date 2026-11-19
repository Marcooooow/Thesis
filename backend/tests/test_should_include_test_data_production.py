import pytest
import os
from sqlalchemy.orm import Session
from app.models import User, Profile, Team, TeamMembership, Organization, OrganizationMembership
from app.auth.security import should_include_test_data
from app.services.team_analytics_service import compute_team_analytics
from seed_thesis_demo_dataset import seed_thesis_dataset

@pytest.fixture(autouse=True)
def run_thesis_seeder(test_db: Session):
    seed_thesis_dataset(test_db)

def test_production_excludes_test_data_even_if_in_demo_org(test_db: Session):
    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    assert manager is not None

    old_env = os.environ.get("ENVIRONMENT")
    old_allow = os.environ.get("INTELLIBREAK_ALLOW_TEST_DATA")
    try:
        os.environ["ENVIRONMENT"] = "production"
        os.environ["INTELLIBREAK_ALLOW_TEST_DATA"] = "false"

        assert should_include_test_data(test_db, manager) is False, "Production must exclude test data even for demo org manager"

        analytics = compute_team_analytics(test_db, manager)
        assert analytics["total_employees"] == 0 or all(not test_db.query(Profile).get(p_id).is_test_data for p_id in analytics["profile_ids"])
    finally:
        if old_env is not None:
            os.environ["ENVIRONMENT"] = old_env
        else:
            os.environ.pop("ENVIRONMENT", None)
        if old_allow is not None:
            os.environ["INTELLIBREAK_ALLOW_TEST_DATA"] = old_allow
        else:
            os.environ.pop("INTELLIBREAK_ALLOW_TEST_DATA", None)

def test_development_can_include_test_data_when_enabled(test_db: Session):
    manager = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    assert manager is not None

    old_env = os.environ.get("ENVIRONMENT")
    old_allow = os.environ.get("INTELLIBREAK_ALLOW_TEST_DATA")
    try:
        os.environ["ENVIRONMENT"] = "development"
        os.environ["INTELLIBREAK_ALLOW_TEST_DATA"] = "true"

        assert should_include_test_data(test_db, manager) is True, "Development with allow flag must include test data"
    finally:
        if old_env is not None:
            os.environ["ENVIRONMENT"] = old_env
        else:
            os.environ.pop("ENVIRONMENT", None)
        if old_allow is not None:
            os.environ["INTELLIBREAK_ALLOW_TEST_DATA"] = old_allow
        else:
            os.environ.pop("INTELLIBREAK_ALLOW_TEST_DATA", None)

def test_genuine_employee_records_remain_visible(test_db: Session):
    gen_user = User(email="genuine.employee@intellibreak.local", password_hash="hash", role="EMPLOYEE", full_name="Genuine Employee", is_active=True)
    test_db.add(gen_user)
    test_db.commit()
    test_db.refresh(gen_user)

    gen_profile = Profile(user_id=gen_user.id, is_test_data=False)
    test_db.add(gen_profile)
    test_db.commit()

    profile_query = test_db.query(Profile).filter(Profile.is_test_data == False).all()
    assert gen_profile in profile_query

def test_managers_cannot_access_other_teams_records(test_db: Session):
    manager1 = test_db.query(User).filter(User.email == "thesis.manager01@intellibreak.local").first()
    manager2 = test_db.query(User).filter(User.email == "thesis.manager02@intellibreak.local").first()
    team2 = test_db.query(Team).filter(Team.manager_user_id == manager2.id).first()
    if team2:
        team2_member_profiles = [m.profile_id for m in test_db.query(TeamMembership).filter_by(team_id=team2.id).all()]
        analytics = compute_team_analytics(test_db, manager1, team_id=team2.id)
        for pid in analytics["profile_ids"]:
            assert pid not in team2_member_profiles
