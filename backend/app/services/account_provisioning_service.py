import uuid

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..auth.security import get_password_hash, get_organization_ids_for_user
from ..models import Organization, OrganizationMembership, Profile, Team, TeamMembership, User
from ..schemas.auth import UserCreate


def provision_account(
    db: Session,
    *,
    current_user: User,
    email: str,
    full_name: str,
    password: str,
    role: str,
    organization_id: uuid.UUID,
    team_id: uuid.UUID | None = None,
) -> User:
    """Create one simulated organization account idempotently with authorization and validation checks."""
    normalized_email = email.strip().lower()
    role = role.strip().upper()
    if role not in {"ADMIN", "MANAGER", "EMPLOYEE"}:
        raise ValueError("Unsupported account role")

    # Enforce caller authorization
    admin_orgs = get_organization_ids_for_user(db, current_user.id)
    if current_user.role.upper() != "ADMIN" or organization_id not in admin_orgs:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to provision accounts for this organization")

    # Validate password strength using existing schema rules
    is_valid, err_msg = UserCreate.validate_password(password)
    if not is_valid:
        raise ValueError(err_msg or "Invalid password")

    # Idempotent return if user already exists
    existing_user = db.query(User).filter(func.lower(User.email) == normalized_email).first()
    if existing_user:
        return existing_user

    try:
        organization = db.query(Organization).filter(Organization.id == organization_id).first()
        if not organization:
            raise ValueError("Organization does not exist")
        team = None
        if team_id is not None:
            team = db.query(Team).filter(Team.id == team_id).first()
            if team is None or team.organization_id != organization_id:
                raise ValueError("Team must belong to the selected organization")
            if role != "EMPLOYEE":
                raise ValueError("Only employees may be assigned to a team")

        user = User(
            email=normalized_email,
            full_name=full_name.strip(),
            password_hash=get_password_hash(password),
            account_type="organization",
            role=role,
            approval_status="APPROVED",
            is_active=True,
        )
        db.add(user)
        db.flush()
        profile = Profile(user_id=user.id, is_test_data=True)
        db.add(profile)
        db.flush()
        db.add(OrganizationMembership(
            user_id=user.id,
            organization_id=organization_id,
            role=role,
            status="APPROVED",
        ))
        if team is not None:
            db.add(TeamMembership(profile_id=profile.id, team_id=team.id, role="EMPLOYEE"))
        db.commit()
        db.refresh(user)
        return user
    except Exception:
        db.rollback()
        raise
