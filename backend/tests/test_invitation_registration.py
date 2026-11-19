"""Tests for invitation token registration flow."""

import pytest
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import secrets

from app.main import app
from app.database import get_db
from app.models import User, Team, TeamInvitation, Profile, Notification, Organization
from app.auth.security import pwd_context, get_password_hash


client = TestClient(app)


class TestInvitationValidation:
    """Test invitation token validation endpoint."""

    def test_validate_valid_pending_invitation(self, test_db: Session):
        """Test validating a valid, pending invitation token."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create invitation
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)

        invitation = TeamInvitation(
            team_id=team.id,
            email="newuser@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="PENDING",
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Validate token
        response = client.get(f"/teams/invitations/validate/{token}")
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True
        assert data["email"] == "newuser@test.com"
        assert data["team_name"] == "Test Team"
        assert data["role"] == "EMPLOYEE"
        assert str(data["invitation_id"]) == str(invitation.id)

    def test_validate_invalid_token(self, test_db: Session):
        """Test validating an invalid token."""
        response = client.get("/teams/invitations/validate/invalid_token_xyz")
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is False
        assert "not found" in data["message"].lower()

    def test_validate_expired_invitation(self, test_db: Session):
        """Test validating an expired invitation."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create expired invitation (created 8 days ago, expires 1 day ago)
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        created_at = datetime.now(timezone.utc) - timedelta(days=8)
        expires_at = datetime.now(timezone.utc) - timedelta(days=1)

        invitation = TeamInvitation(
            team_id=team.id,
            email="newuser@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="PENDING",
            created_at=created_at,
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Validate token
        response = client.get(f"/teams/invitations/validate/{token}")
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is False
        assert "expired" in data["message"].lower()

        # Check invitation status was updated
        test_db.refresh(invitation)
        assert invitation.status == "EXPIRED"

    def test_validate_already_accepted_invitation(self, test_db: Session):
        """Test validating an already accepted invitation."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create accepted invitation
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)

        invitation = TeamInvitation(
            team_id=team.id,
            email="newuser@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="ACCEPTED",
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Validate token
        response = client.get(f"/teams/invitations/validate/{token}")
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is False
        assert "not found" in data["message"].lower()


class TestRegistrationWithInvitation:
    """Test registration with invitation token."""

    def test_register_with_valid_invitation(self, test_db: Session):
        """Test successful registration with valid invitation token."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create invitation
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)

        invitation = TeamInvitation(
            team_id=team.id,
            email="newuser@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="PENDING",
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Register with invitation token
        response = client.post("/auth/register", json={
            "email": "newuser@test.com",
            "password": "securepass123",
            "full_name": "New User",
            "account_type": "solo",
            "invitation_token": token,
        })

        assert response.status_code == 201
        data = response.json()
        assert data["email"] == "newuser@test.com"
        assert data["full_name"] == "New User"

        # Verify invitation remains PENDING (not auto-accepted)
        test_db.refresh(invitation)
        assert invitation.status == "PENDING"

        # Verify TEAM_INVITATION notification was created
        notifications = test_db.query(Notification).filter(
            Notification.related_entity_id == invitation.id,
            Notification.type == "TEAM_INVITATION",
        ).all()
        assert len(notifications) > 0

    def test_register_with_wrong_email(self, test_db: Session):
        """Test registration fails when email doesn't match invitation."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create invitation for specific email
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        expires_at = datetime.now(timezone.utc) + timedelta(days=7)

        invitation = TeamInvitation(
            team_id=team.id,
            email="invited@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="PENDING",
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Try to register with different email
        response = client.post("/auth/register", json={
            "email": "different@test.com",
            "password": "securepass123",
            "full_name": "New User",
            "account_type": "solo",
            "invitation_token": token,
        })

        assert response.status_code == 400
        data = response.json()
        assert "different email" in data["detail"].lower()

    def test_register_with_expired_invitation(self, test_db: Session):
        """Test registration fails with expired invitation."""
        # Create team and manager
        manager = User(
            email="manager@test.com",
            full_name="Manager",
            password_hash=get_password_hash("password"),
            role="MANAGER",
            approval_status="APPROVED",
        )
        test_db.add(manager)
        test_db.flush()

        # Create organization for the team
        organization = Organization(name="Test Org")
        test_db.add(organization)
        test_db.flush()

        team = Team(
            name="Test Team",
            manager_user_id=manager.id,
            organization_id=organization.id,
            is_active=True,
        )
        test_db.add(team)
        test_db.flush()

        # Create expired invitation (created 8 days ago, expires 1 day ago)
        token = secrets.token_urlsafe(32)
        token_prefix = token[:12]
        token_hash = get_password_hash(token)
        created_at = datetime.now(timezone.utc) - timedelta(days=8)
        expires_at = datetime.now(timezone.utc) - timedelta(days=1)

        invitation = TeamInvitation(
            team_id=team.id,
            email="newuser@test.com",
            invited_by=manager.id,
            role="EMPLOYEE",
            token_prefix=token_prefix,
            token_hash=token_hash,
            status="PENDING",
            created_at=created_at,
            expires_at=expires_at,
        )
        test_db.add(invitation)
        test_db.commit()

        # Try to register
        response = client.post("/auth/register", json={
            "email": "newuser@test.com",
            "password": "securepass123",
            "full_name": "New User",
            "account_type": "solo",
            "invitation_token": token,
        })

        assert response.status_code == 400
        data = response.json()
        assert "expired" in data["detail"].lower()

    def test_register_without_invitation_still_works(self, test_db: Session):
        """Test normal registration without invitation still works."""
        response = client.post("/auth/register", json={
            "email": "solo@test.com",
            "password": "securepass123",
            "full_name": "Solo User",
            "account_type": "solo",
        })

        assert response.status_code == 201
        data = response.json()
        assert data["email"] == "solo@test.com"
        assert data["account_type"] == "solo"