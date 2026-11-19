"""Tests for team invitation functionality."""

import pytest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch, MagicMock
import uuid
import hashlib

from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.main import app
from app.database import get_db
from app.models import User, Profile, Team, TeamMembership, WorkSession, Break, Task, Recommendation, SystemActivityLog, TeamInvitation, Notification, Group, Organization, OrganizationMembership  # noqa
from app.auth.security import get_password_hash, pwd_context


# Helper function to get auth headers
def get_auth_headers(client: TestClient, email: str, password: str):
    """Get authentication headers for a user."""
    login_data = {"email": email, "password": password}
    response = client.post("/auth/login", json=login_data)
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


# Fixtures
@pytest.fixture
def test_client(test_db: Session):
    """Create test client."""
    from fastapi.testclient import TestClient
    return TestClient(app)


@pytest.fixture
def db_session(test_db: Session):
    """Provide a database session for tests."""
    yield test_db


@pytest.fixture
def solo_user(db_session: Session, test_client: TestClient) -> User:
    """Create a solo employee user."""
    # Check if user already exists
    email = "solo@test.com"
    user = db_session.query(User).filter(User.email == email).first()
    if not user:
        # Create user
        hashed_password = get_password_hash("testpass123")
        user = User(
            email=email,
            full_name="Solo Employee",
            password_hash=hashed_password,
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True,
            account_type="solo"
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)

        # Create profile
        profile = Profile(
            user_id=user.id,
            job_role="Developer",
            industry="Technology",
            years_of_experience=5,
            age=30,
            education_attainment="Bachelor's",
            marital_status="Single",
            target_daily_hours=8,
        )
        db_session.add(profile)
        db_session.commit()

    return user


@pytest.fixture
def manager_user(db_session: Session, test_client: TestClient) -> User:
    """Create a manager user with a team."""
    # Use UUID to ensure unique email per test run
    unique_id = str(uuid.uuid4())[:8]
    email = f"manager_{unique_id}@test.com"

    # Create user
    hashed_password = get_password_hash("testpass123")
    user = User(
        email=email,
        full_name=f"Manager {unique_id}",
        password_hash=hashed_password,
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo",
    )
    db_session.add(user)
    db_session.flush()

    # Create profile
    profile = Profile(
        user_id=user.id,
        job_role="Engineering Manager",
        industry="Technology",
        years_of_experience=8,
        age=35,
        education_attainment="Master's",
        marital_status="Married",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.flush()

    # Create organization and membership for team creation authorization
    organization = Organization(name=f"Test Org {unique_id}")
    db_session.add(organization)
    db_session.flush()

    organization_membership = OrganizationMembership(
        user_id=user.id,
        organization_id=organization.id,
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(organization_membership)
    db_session.flush()

    # Create team
    team = Team(
        name=f"Test Team {unique_id}",
        description="A test team",
        manager_user_id=user.id,
        organization_id=organization.id,
        is_active=True
    )
    db_session.add(team)
    db_session.flush()  # Flush to get team ID and trigger back_populates

    # Create team membership for manager
    membership = TeamMembership(
        profile_id=profile.id,
        team_id=team.id,
        role="MANAGER",
        joined_at=datetime.now(timezone.utc)
    )
    db_session.add(membership)
    db_session.commit()

    # Refresh user to ensure relationships are loaded
    db_session.refresh(user)
    # Debug: Check if managed_teams is populated
    print(f"DEBUG: User {user.id} has {len(user.managed_teams)} managed_teams")
    if user.managed_teams:
        print(f"DEBUG: First managed team ID: {user.managed_teams[0].id}")
    else:
        print(f"DEBUG: No managed_teams found for user {user.id}")
        # Let's check teams directly
        teams = db_session.query(Team).filter(Team.manager_user_id == user.id).all()
        print(f"DEBUG: Direct query found {len(teams)} teams for manager {user.id}")
        for t in teams:
            print(f"DEBUG: Team ID: {t.id}, Name: {t.name}")

    return user


def test_solo_employee_can_exist_without_team(test_client, solo_user, db_session):
    """Test 1: Solo Employee can exist without a Team."""
    headers = get_auth_headers(test_client, solo_user.email, "testpass123")

    # Get user's teams - should be empty for solo employee
    response = test_client.get("/teams/my-teams", headers=headers)
    assert response.status_code == 200
    teams = response.json()
    assert isinstance(teams, list)
    assert len(teams) == 0

    # Get my team (should return None for solo employee)
    response = test_client.get("/teams/me", headers=headers)
    assert response.status_code == 200
    team = response.json()
    assert team is None


def test_employee_cannot_create_team(test_client, solo_user, db_session):
    """Test 2: Employee cannot create a Team (only managers can)."""
    headers = get_auth_headers(test_client, solo_user.email, "testpass123")

    # Create team
    team_data = {
        "name": "New Test Team",
        "description": "A team created by solo employee"
    }
    response = test_client.post("/teams/", json=team_data, headers=headers)
    assert response.status_code == 403
    assert "Only managers and admins can create teams" in response.json().get("detail", "")

    # Verify creator remained employee
    db_session.refresh(solo_user)
    assert solo_user.role == "EMPLOYEE"


def test_manager_can_create_team_and_remains_manager(test_client, manager_user, db_session):
    """Test 3: Manager can create a team and remains a Manager."""
    # Delete the team created by manager_user fixture
    db_session.query(Team).filter(Team.manager_user_id == manager_user.id).delete()
    db_session.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    team_data = {"name": "Manager Test Team"}
    response = test_client.post("/teams/", json=team_data, headers=headers)
    assert response.status_code == 201
    created_team = response.json()

    assert created_team["name"] == "Manager Test Team"
    assert created_team["manager_name"] == manager_user.full_name
    assert created_team["member_count"] == 1  # Creator should be counted

    # Verify creator remained manager (role unchanged)
    db_session.refresh(manager_user)
    assert manager_user.role == "MANAGER"


def test_manager_can_invite_by_email(test_client, manager_user, db_session):
    """Test 4: Manager can invite by email."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Send invitation
    invite_data = {
        "email": "invitee@test.com",
        "role": "EMPLOYEE"
    }
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=headers)

    assert response.status_code == 201
    invitation = response.json()

    assert invitation["email"] == "invitee@test.com"
    assert invitation["role"] == "EMPLOYEE"
    assert invitation["status"] == "PENDING"
    assert "token" not in invitation  # Token should not be in response
    assert invitation["inviter_name"] == manager_user.full_name
    assert invitation["team_name"] == manager_user.managed_teams[0].name

    # Check invitation exists in DB
    db_invitation = db_session.query(TeamInvitation).filter(
        TeamInvitation.email == "invitee@test.com"
    ).first()
    assert db_invitation is not None
    assert db_invitation.status == "PENDING"


def test_invitation_is_stored_as_pending(test_client, manager_user, db_session):
    """Test 5: Invitation is stored as PENDING."""
    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    invite_data = {"email": "pending@test.com", "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=headers)

    assert response.status_code == 201
    invitation = response.json()
    assert invitation["status"] == "PENDING"

    # Double-check in database
    db_invitation = db_session.query(TeamInvitation).filter(
        TeamInvitation.email == "pending@test.com"
    ).first()
    assert db_invitation.status == "PENDING"


def test_existing_invited_user_receives_notification(test_client, manager_user, db_session):
    """Test 6: Existing invited user receives notification."""
    # Create invited user
    invited_email = "existing@test.com"
    hashed_password = get_password_hash("testpass123")
    invited_user = User(
        email=invited_email,
        full_name="Existing User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(invited_user)
    db_session.flush()

    profile = Profile(
        user_id=invited_user.id,
        job_role="Designer",
        industry="Creative",
        years_of_experience=3,
        age=28,
        education_attainment="Associate's",
        marital_status="Single",
        target_daily_hours=7,
    )
    db_session.add(profile)
    db_session.commit()

    headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Send invitation
    invite_data = {"email": invited_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=headers)

    assert response.status_code == 201

    # Check notification was created for invited user
    db_session.refresh(invited_user)
    notifications = db_session.query(Notification).filter(
        Notification.recipient_user_id == invited_user.id
    ).all()

    assert len(notifications) >= 1
    notification = notifications[0]  # Get most recent
    assert notification.type == "TEAM_INVITATION"
    assert manager_user.full_name in notification.message
    assert manager_user.managed_teams[0].name in notification.message
    assert notification.is_read == False
    assert notification.is_actioned == False


def test_employee_can_accept_invitation(test_client, manager_user, db_session):
    """Test 7: Employee can accept invitation."""
    # Create invited user
    invited_email = "accept@test.com"
    hashed_password = get_password_hash("testpass123")
    invited_user = User(
        email=invited_email,
        full_name="Accept User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(invited_user)
    db_session.flush()

    profile = Profile(
        user_id=invited_user.id,
        job_role="Analyst",
        industry="Finance",
        years_of_experience=2,
        age=25,
        education_attainment="High School",
        marital_status="Single",
        target_daily_hours=9,
    )
    db_session.add(profile)
    db_session.commit()

    # Manager sends invitation
    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    invite_data = {"email": invited_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 201
    invitation_id = uuid.UUID(response.json()["id"])
    print(f"DEBUG: invitation_id = {invitation_id}")
    # Query the invitation directly from the db_session to see if it exists
    from app.models import TeamInvitation
    inv = db_session.query(TeamInvitation).filter(TeamInvitation.id == invitation_id).first()
    print(f"DEBUG: inv from db_session = {inv}")
    if inv:
        print(f"DEBUG: inv.id = {inv.id}, inv.email = {inv.email}")

    # Now accept as invited user
    user_headers = get_auth_headers(test_client, invited_email, "testpass123")
    response = test_client.post(f"/teams/invitations/{invitation_id}/accept",
                               headers=user_headers)

    assert response.status_code == 200
    result = response.json()
    assert result["status"] == "accepted"

    # Verify invitation status changed
    db_session.expire_all()  # Refresh from database
    invitation = db_session.query(TeamInvitation).filter(
        TeamInvitation.id == invitation_id
    ).first()
    assert invitation.status == "ACCEPTED"
    assert invitation.accepted_at is not None

    # Verify team membership was created
    membership = db_session.query(TeamMembership).filter(
        TeamMembership.profile_id == profile.id,
        TeamMembership.team_id == manager_user.managed_teams[0].id
    ).first()
    assert membership is not None
    assert membership.role == "EMPLOYEE"
    assert membership.left_at is None


def test_employee_becomes_team_member_employee(test_client, manager_user, db_session):
    """Test 8: Employee becomes TeamMembership = EMPLOYEE."""
    # Covered in test_employee_can_accept_invitation
    pass


def test_invitation_becomes_accepted(test_client, manager_user, db_session):
    """Test 9: Invitation becomes ACCEPTED."""
    # Covered in test_employee_can_accept_invitation
    pass


def test_manager_receives_acceptance_notification(test_client, manager_user, db_session):
    """Test 10: Manager receives acceptance notification."""
    # Create invited user
    invited_email = "notify@test.com"
    hashed_password = get_password_hash("testpass123")
    invited_user = User(
        email=invited_email,
        full_name="Notify User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(invited_user)
    db_session.flush()

    profile = Profile(
        user_id=invited_user.id,
        job_role="Tester",
        industry="QA",
        years_of_experience=4,
        age=32,
        education_attainment="Bachelor's",
        marital_status="Single",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.commit()

    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Send invitation
    invite_data = {"email": invited_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 201
    invitation_id = uuid.UUID(response.json()["id"])

    # Accept invitation
    user_headers = get_auth_headers(test_client, invited_email, "testpass123")
    response = test_client.post(f"/teams/invitations/{invitation_id}/accept",
                               headers=user_headers)

    assert response.status_code == 200

    # Check manager received notification
    db_session.refresh(manager_user)
    notifications = db_session.query(Notification).filter(
        Notification.recipient_user_id == manager_user.id
    ).all()

    assert len(notifications) >= 1
    # Find the acceptance notification
    acceptance_notif = None
    for notif in notifications:
        if notif.type == "TEAM_INVITATION_ACCEPTED":
            acceptance_notif = notif
            break

    assert acceptance_notif is not None
    assert "accepted your invitation" in acceptance_notif.message
    assert acceptance_notif.is_read == False
    assert acceptance_notif.is_actioned == False


def test_employee_can_decline_invitation(test_client, manager_user, db_session):
    """Test 11: Employee can decline invitation."""
    # Create invited user
    invited_email = "decline@test.com"
    hashed_password = get_password_hash("testpass123")
    invited_user = User(
        email=invited_email,
        full_name="Decline User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(invited_user)
    db_session.flush()

    profile = Profile(
        user_id=invited_user.id,
        job_role="DevOps",
        industry="Cloud",
        years_of_experience=6,
        age=33,
        education_attainment="Bachelor's",
        marital_status="Married",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.commit()

    # Manager sends invitation
    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    invite_data = {"email": invited_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 201
    invitation_id = uuid.UUID(response.json()["id"])

    # Now decline as invited user
    user_headers = get_auth_headers(test_client, invited_email, "testpass123")
    response = test_client.post(f"/teams/invitations/{invitation_id}/decline",
                               headers=user_headers)

    assert response.status_code == 200
    result = response.json()
    assert result["status"] == "declined"

    # Verify invitation status changed
    db_session.expire_all()
    invitation = db_session.query(TeamInvitation).filter(
        TeamInvitation.id == invitation_id
    ).first()
    assert invitation.status == "DECLINED"
    assert invitation.declined_at is not None

    # Verify NO team membership was created
    membership = db_session.query(TeamMembership).filter(
        TeamMembership.profile_id == profile.id,
        TeamMembership.team_id == manager_user.managed_teams[0].id
    ).first()
    assert membership is None


def test_invitation_becomes_declined(test_client, manager_user, db_session):
    """Test 12: Invitation becomes DECLINED."""
    # Covered in test_employee_can_decline_invitation
    pass


def test_manager_cannot_invite_to_team_they_do_not_manage(test_client, manager_user, db_session):
    """Test 13: Manager cannot invite to a team they do not manage."""
    # Create another manager with their own team
    other_manager_email = "other@test.com"
    hashed_password = get_password_hash("testpass123")
    other_manager = User(
        email=other_manager_email,
        full_name="Other Manager",
        password_hash=hashed_password,
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(other_manager)
    db_session.flush()

    profile = Profile(
        user_id=other_manager.id,
        job_role="Product Manager",
        industry="Product",
        years_of_experience=7,
        age=38,
        education_attainment="MBA",
        marital_status="Married",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.flush()

    # Create organization and membership for other manager (required for team creation)
    other_organization = Organization(name=f"Other Test Org {uuid.uuid4()}")
    db_session.add(other_organization)
    db_session.flush()

    other_organization_membership = OrganizationMembership(
        user_id=other_manager.id,
        organization_id=other_organization.id,
        role="MANAGER",
        status="APPROVED"
    )
    db_session.add(other_organization_membership)
    db_session.flush()

    # Create team for other manager
    other_team = Team(
        name="Other Team",
        description="Another manager's team",
        manager_user_id=other_manager.id,
        organization_id=other_organization.id,
        is_active=True
    )
    db_session.add(other_team)
    db_session.flush()

    # Other manager's membership
    membership = TeamMembership(
        profile_id=profile.id,
        team_id=other_team.id,
        role="MANAGER",
        joined_at=datetime.now(timezone.utc)
    )
    db_session.add(membership)
    db_session.commit()

    # Try to invite to other manager's team using first manager (who is NOT manager of that team)
    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Try to invite to OTHER manager's team - should fail
    invite_data = {"email": "someone@test.com", "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{other_team.id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 403  # Forbidden
    assert "Only the team manager can send invitations" in response.json()["detail"]


def test_user_cannot_accept_another_users_invitation(test_client, manager_user, db_session):
    """Test 14: User cannot accept another user's invitation."""
    # Create two users
    user1_email = "user1@test.com"
    user2_email = "user2@test.com"
    hashed_password = get_password_hash("testpass123")

    user1 = User(
        email=user1_email,
        full_name="User One",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    user2 = User(
        email=user2_email,
        full_name="User Two",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add_all([user1, user2])
    db_session.flush()

    # Profiles
    profile1 = Profile(user_id=user1.id, job_role="Dev1", industry="Tech", years_of_experience=2)
    profile2 = Profile(user_id=user2.id, job_role="Dev2", industry="Tech", years_of_experience=3)
    db_session.add_all([profile1, profile2])
    db_session.commit()

    # Manager invites user1
    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    invite_data = {"email": user1_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 201
    invitation_id = uuid.UUID(response.json()["id"])

    # Try to accept as user2 (wrong user) - should fail
    user2_headers = get_auth_headers(test_client, user2_email, "testpass123")
    response = test_client.post(f"/teams/invitations/{invitation_id}/accept",
                               headers=user2_headers)

    assert response.status_code == 403  # Forbidden
    assert "Not authorized to accept this invitation" in response.json()["detail"]


def test_expired_invitation_cannot_be_accepted(test_client, manager_user, db_session):
    """Test 15: Expired invitation cannot be accepted."""
    # Create user to invite
    invitee_email = "expired@test.com"
    hashed_password = get_password_hash("testpass123")
    invitee_user = User(
        email=invitee_email,
        full_name="Expired Invitee",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(invitee_user)
    db_session.flush()

    profile = Profile(
        user_id=invitee_user.id,
        job_role="Intern",
        industry="Tech",
        years_of_experience=0,
        age=22,
        education_attainment="High School",
        marital_status="Single",
        target_daily_hours=6,
    )
    db_session.add(profile)
    db_session.commit()

    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")

    # Manually create an expired invitation in DB
    expired_time = datetime.now(timezone.utc) - timedelta(days=1)  # Yesterday
    invitation = TeamInvitation(
        team_id=manager_user.managed_teams[0].id,
        email=invitee_email,
        invited_by=manager_user.id,
        role="EMPLOYEE",
        token_prefix="testtoken123",
        token_hash=hashlib.sha256("testtoken123".encode('utf-8')).hexdigest(),
        status="PENDING",
        expires_at=expired_time,  # Already expired
        created_at=datetime.now(timezone.utc) - timedelta(days=2)
    )
    db_session.add(invitation)
    db_session.commit()

    # Try to accept expired invitation - should fail
    user_headers = get_auth_headers(test_client, invitee_email, "testpass123")
    response = test_client.post(f"/teams/invitations/{invitation.id}/accept",
                               headers=user_headers)

    assert response.status_code == 400  # Bad Request
    assert "Invitation has expired" in response.json()["detail"]

    # Verify invitation status changed to EXPIRED
    db_session.refresh(invitation)
    assert invitation.status == "EXPIRED"


def test_notification_read_state_works(test_client, manager_user, db_session):
    """Test 16: Notification read state works."""
    # Create user to receive invitation notification
    user_email = "notifyread@test.com"
    hashed_password = get_password_hash("testpass123")
    test_user = User(
        email=user_email,
        full_name="Notify Read User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(test_user)
    db_session.flush()

    profile = Profile(
        user_id=test_user.id,
        job_role="Reader",
        industry="Media",
        years_of_experience=1,
        age=24,
        education_attainment="Some College",
        marital_status="Single",
        target_daily_hours=7,
    )
    db_session.add(profile)
    db_session.commit()

    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    user_headers = get_auth_headers(test_client, user_email, "testpass123")

    # Send invitation (creates TEAM_INVITATION notification for the invited user)
    invite_data = {"email": user_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)

    assert response.status_code == 201

    # Get notifications for the invited user (they should have an unread TEAM_INVITATION notification)
    notifications_before = test_client.get("/notifications/", headers=user_headers)
    assert notifications_before.status_code == 200
    data_before = notifications_before.json()
    unread_count_before = data_before["unread_count"]
    assert unread_count_before > 0

    # Get first unread notification ID
    first_notif_id = data_before["notifications"][0]["id"]

    # Mark notification as read
    response = test_client.patch(f"/notifications/{first_notif_id}/read",
                                headers=user_headers)
    assert response.status_code == 200

    # Check notification is now marked as read
    notifications_after = test_client.get("/notifications/", headers=user_headers)
    assert notifications_after.status_code == 200
    data_after = notifications_after.json()
    unread_count_after = data_after["unread_count"]
    assert unread_count_after == unread_count_before - 1

    # Find the notification we marked as read
    marked_notif = None
    for notif in data_after["notifications"]:
        if notif["id"] == first_notif_id:
            marked_notif = notif
            break

    assert marked_notif is not None
    assert marked_notif["is_read"] == True
    assert marked_notif["read_at"] is not None


def test_notification_action_state_works(test_client, manager_user, db_session):
    """Test 17: Notification action state works - invited employee accepts and manager is notified."""
    # Create user to receive invitation notification
    user_email = "notifyaction@test.com"
    hashed_password = get_password_hash("testpass123")
    test_user = User(
        email=user_email,
        full_name="Notify Action User",
        password_hash=hashed_password,
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        account_type="solo"
    )
    db_session.add(test_user)
    db_session.flush()

    profile = Profile(
        user_id=test_user.id,
        job_role="Actor",
        industry="Entertainment",
        years_of_experience=5,
        age=29,
        education_attainment="Bachelor's",
        marital_status="Divorced",
        target_daily_hours=8,
    )
    db_session.add(profile)
    db_session.commit()

    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    user_headers = get_auth_headers(test_client, user_email, "testpass123")

    # Send invitation (creates TEAM_INVITATION notification for employee)
    invite_data = {"email": user_email, "role": "EMPLOYEE"}
    response = test_client.post(f"/teams/{manager_user.managed_teams[0].id}/invitations",
                               json=invite_data, headers=manager_headers)
    assert response.status_code == 201
    invitation_id = uuid.UUID(response.json()["id"])

    # Employee accepts invitation (creates TEAM_INVITATION_ACCEPTED notification for manager)
    response = test_client.post(f"/teams/invitations/{invitation_id}/accept",
                               headers=user_headers)
    assert response.status_code == 200

    # Get notifications for manager
    notifications_response = test_client.get("/notifications/", headers=manager_headers)
    assert notifications_response.status_code == 200
    data = notifications_response.json()
    assert data["unread_count"] > 0

    # Find TEAM_INVITATION_ACCEPTED notification (manager receives this when employee accepts)
    found_notif = None
    for notif in data["notifications"]:
        if notif["type"] == "TEAM_INVITATION_ACCEPTED":
            found_notif = notif
            break

    assert found_notif is not None
    # is_actioned=False because the manager (recipient) has NOT yet taken action on the notification
    # The notification signals that the employee accepted; is_actioned becomes True only when manager acts on it
    assert found_notif["is_actioned"] == False

    # Verify the employee's TEAM_INVITATION is marked as is_actioned=True (they acted on it by accepting)
    employee_notifications = test_client.get("/notifications/", headers=user_headers)
    assert employee_notifications.status_code == 200
    employee_data = employee_notifications.json()
    employee_notif = None
    for notif in employee_data["notifications"]:
        if notif["type"] == "TEAM_INVITATION":
            employee_notif = notif
            break

    assert employee_notif is not None
    # Employee's TEAM_INVITATION has is_actioned=True because they acted on it (accepted)
    assert employee_notif["is_actioned"] == True


def test_non_authorized_users_cannot_access_anothers_notifications(test_client, solo_user, manager_user, db_session):
    """Test 18: Non-authorized users cannot access another user's notifications."""
    # Get notifications for manager
    manager_headers = get_auth_headers(test_client, manager_user.email, "testpass123")
    manager_notifs_before = test_client.get("/notifications/", headers=manager_headers)
    assert manager_notifs_before.status_code == 200
    manager_data_before = manager_notifs_before.json()

    # Try to access notifications as solo_user (different user)
    solo_headers = get_auth_headers(test_client, solo_user.email, "testpass123")
    response = test_client.get("/notifications/", headers=solo_headers)
    assert response.status_code == 200
    solo_data = response.json()

    # The notification lists should be different (each user sees only their own)
    # Since we haven't triggered any notifications for solo_user yet, their count might be 0
    # While manager might have some from setup
    # Most importantly, solo_user should NOT see manager's notifications

    # More direct test: try to access a specific notification that belongs to manager
    if manager_data_before["notifications"]:
        manager_notif_id = manager_data_before["notifications"][0]["id"]
        # Try to access manager's notification as solo_user - should fail or return empty/not found
        response = test_client.get(f"/notifications/{manager_notif_id}/read",
                                  headers=solo_headers)
        # Depending on implementation, this might be 403 (forbidden) or 404 (not found from their perspective)
        # Either way, solo_user should not be able to modify manager's notification
        assert response.status_code in [403, 404]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])