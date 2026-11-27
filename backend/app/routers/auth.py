import time as time_mod
from datetime import datetime, timedelta, timezone, time, date
from typing import Optional
import hashlib
import hmac
import uuid
import secrets
from fastapi import APIRouter, Depends, HTTPException, Query, status, Request
from sqlalchemy.orm import Session, joinedload
from ..schemas.auth import (UserCreate, UserResponse, PaginatedUsersResponse, UserCountsResponse, UserLogin, Token,
                          ForgotPasswordRequest, ForgotPasswordResponse,
                          ResetPasswordRequest, ResetPasswordResponse,
                          TotpSetupResponse, TotpVerifyRequest, TotpVerifyResponse,
                          TotpToggleResponse, TokenChallenge, TokenChallengeVerify,
                          TotpDisableRequest, PasswordChangeRequest, PasswordChangeResponse)
from ..models import User, Profile, Organization, OrganizationMembership, TeamInvitation, Notification, Task, UserSettings, SystemActivityLog, RecommendationFeedback, EmployeeSchedule
from ..auth.security import (
    get_password_hash, authenticate_user, create_access_token,
    get_current_active_user, get_current_admin_user, get_current_restricted_user,
    ACCESS_TOKEN_EXPIRE_MINUTES, REFRESH_TOKEN_EXPIRE_DAYS,
    create_refresh_token, hash_refresh_token, verify_refresh_token_hash,
    generate_reset_token, hash_reset_token, verify_reset_token,
    verify_password, generate_totp_secret, get_totp_uri, verify_totp,
    SECRET_KEY, ALGORITHM, log_system_activity, get_organization_ids_for_user
)
from jose import JWTError, jwt
from ..database import get_db
from ..services.notification_dispatch_service import NotificationDispatchService
import os

# ponytail: in-memory rate limit; use Redis for multi-instance deployments
_login_failures: dict[str, list[float]] = {}

router = APIRouter(
    prefix="/auth",
    tags=["auth"],
    responses={404: {"description": "Not found"}},
)


def _get_client_ip(request: Request) -> str:
    """Extract client IP from request, handling proxies."""
    if request.client:
        return request.client.host
    return "unknown"


def _check_login_rate_limit(ip: str) -> None:
    """
    Check if IP has exceeded login attempt limit.
    Raises HTTPException if rate limit exceeded.
    Cleans old entries older than 15 minutes.
    """
    now = time_mod.time()
    window = 15 * 60  # 15 minutes in seconds
    max_attempts = 5

    # Clean old entries for this IP
    if ip in _login_failures:
        _login_failures[ip] = [t for t in _login_failures[ip] if now - t < window]

    # Check if over limit
    if ip in _login_failures and len(_login_failures[ip]) >= max_attempts:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Please try again later."
        )


def _record_login_failure(ip: str) -> None:
    """Record a failed login attempt for this IP."""
    now = time_mod.time()
    if ip not in _login_failures:
        _login_failures[ip] = []
    _login_failures[ip].append(now)


def _clear_login_failures(ip: str) -> None:
    """Clear failure count for this IP on successful login."""
    if ip in _login_failures:
        del _login_failures[ip]



@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register_user(user: UserCreate, db: Session = Depends(get_db)):
    """
    Register a new user.
    - **email**: must be unique
    - **password**: minimum 12 characters, will be hashed with bcrypt
    - **account_type**: "solo" or "organization"
    - **organization_name**: required if account_type is "organization"
    - **role**: defaults to EMPLOYEE
    - **approval_status**: For solo accounts, APPROVED (immediate access). For organization accounts, PENDING (requires manager approval)
    - **invitation_token**: optional token from team invitation (for invited registrations)

    If invitation_token is provided:
    - email must match the invitation email
    - invitation must be PENDING and not expired
    - invitation is NOT automatically accepted (user must accept manually)
    """
    # Validate password
    is_valid, error_msg = UserCreate.validate_password(user.password)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg
        )

    # Check if user already exists
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    invitation = None
    invitation_id = None

    # If invitation token provided, validate it
    if user.invitation_token:
        token = user.invitation_token
        if len(token) < 12:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid invitation token format"
            )

        token_prefix = token[:12]

        # Find pending invitations with matching token prefix
        candidate_invitations = db.query(TeamInvitation).filter(
            TeamInvitation.token_prefix == token_prefix,
            TeamInvitation.status == "PENDING",
        ).all()

        if not candidate_invitations:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invitation not found or has been used"
            )

        # Verify plaintext token against SHA-256 hash (with legacy verify_password fallback)
        expected_token_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
        for candidate in candidate_invitations:
            if hmac.compare_digest(candidate.token_hash, expected_token_hash) or verify_password(token, candidate.token_hash):
                invitation = candidate
                break

        if not invitation:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid invitation token"
            )

        # Check expiration
        if datetime.now(timezone.utc) > invitation.expires_at:
            invitation.status = "EXPIRED"
            db.add(invitation)
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invitation has expired"
            )

        # Verify email matches invitation email (case-insensitive)
        if user.email.lower() != invitation.email.lower():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This invitation was sent to a different email address"
            )

        invitation_id = invitation.id

    # Determine role and approval_status based on account_type and invitation
    # Invitations: EMPLOYEE + PENDING (regardless of account_type)
    # Solo accounts (no invitation): EMPLOYEE + APPROVED (immediate access)
    # Organization accounts (no invitation): MANAGER + PENDING
    # ADMIN role can only be assigned via admin provisioning, not registration

    if user.invitation_token:
        # Invitations: EMPLOYEE + PENDING
        global_role = "EMPLOYEE"
        approval_status = "PENDING"
    else:
        if user.account_type == "solo":
            # Solo accounts: EMPLOYEE + APPROVED
            global_role = "EMPLOYEE"
            approval_status = "APPROVED"
        else:
            # Organization accounts: MANAGER + PENDING
            global_role = "MANAGER"
            approval_status = "PENDING"

    # Create new user
    hashed_password = get_password_hash(user.password)
    db_user = User(
        email=user.email,
        full_name=user.full_name,
        organization_name=user.organization_name if user.account_type == "organization" else None,
        account_type=user.account_type,
        role=global_role,
        approval_status=approval_status,
        password_hash=hashed_password,
        terms_accepted_at=datetime.now(timezone.utc) if user.terms_accepted is True else None,
        terms_version="terms-2026-11" if user.terms_accepted is True else None,
        data_consent_at=datetime.now(timezone.utc) if user.data_consent is True else None,
        privacy_notice_version="privacy-2026-11" if user.data_consent is True else None,
    )
    db.add(db_user)
    db.flush()

    # Create profile for the user with the flushed user id
    s_start = time.fromisoformat(user.shift_start_time) if isinstance(user.shift_start_time, str) else user.shift_start_time
    s_end = time.fromisoformat(user.shift_end_time) if isinstance(user.shift_end_time, str) else user.shift_end_time

    db_profile = Profile(
        user_id=db_user.id,
        job_role=user.job_role,
        industry=user.industry,
        years_of_experience=user.years_of_experience,
        age=user.age,
        gender=user.gender,
        education_attainment=user.education_attainment,
        marital_status=user.marital_status,
        target_daily_hours=user.target_daily_hours,
        shift_start_time=s_start,
        shift_end_time=s_end,
        work_days=user.work_days,
    )
    db.add(db_profile)
    db.flush()

    if s_start and s_end and db_profile.work_days:
        try:
            db.add(EmployeeSchedule(
                profile_id=db_profile.id,
                effective_from=db_profile.hire_date or date.today(),
                effective_until=None,
                work_days=db_profile.work_days,
                shift_start=s_start,
                shift_end=s_end,
                timezone='Asia/Manila',
                created_by=db_user.id
            ))
        except Exception:
            pass

    if user.work_profile and global_role == "EMPLOYEE":
        from ..services.work_profile_service import create_or_update_work_profile
        create_or_update_work_profile(db, db_user.id, user.work_profile, commit=False)

    # If invitation exists, create TEAM_INVITATION notification
    if invitation:
        # Get team info for notification
        team = db.query(TeamInvitation).filter(TeamInvitation.id == invitation.id).first()
        if team:
            # Get team name
            from ..models import Team
            team_record = db.query(Team).filter(Team.id == invitation.team_id).first()
            team_name = team_record.name if team_record else "Team"

            NotificationDispatchService.dispatch(
                db=db,
                recipient_user_id=db_user.id,
                title=f"You've been invited to join {team_name}",
                message=f"Accept this invitation to join {team_name} as {invitation.role}.",
                notification_type="TEAM_INVITATION",
                priority="STANDARD",
                idempotency_key=f"team_invitation_register_{invitation.id}_{db_user.id}",
                related_entity_id=invitation.id,
            )
    # For organization accounts without invitation, create organization and membership
    elif user.account_type == "organization":
        # Create organization
        db_organization = Organization(
            name=user.organization_name
        )
        db.add(db_organization)
        db.flush()  # to get the organization id

        # Create organization membership
        db_organization_membership = OrganizationMembership(
            user_id=db_user.id,
            organization_id=db_organization.id,
            role="MANAGER",
            status="APPROVED"
        )
        db.add(db_organization_membership)

    try:
        db.commit()
        db.refresh(db_user)
        db.refresh(db_profile)

        # Log registration with invitation if applicable
        if invitation_id:
            log_system_activity(
                db=db,
                user_id=db_user.id,
                action_type="USER_REGISTERED_WITH_INVITATION",
                action_details={
                    "invitation_id": str(invitation_id),
                    "team_id": str(invitation.team_id),
                }
            )
        else:
            log_system_activity(
                db=db,
                user_id=db_user.id,
                action_type="USER_REGISTERED",
                action_details={}
            )

        return db_user
    except Exception as e:
        db.rollback()
        raise



@router.post("/login", response_model=Token)
def login_for_access_token(
    form_data: UserLogin,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    OAuth2 compatible token login, get an access token for future requests.
    If 2FA is enabled, returns a 2FA challenge token instead of access token.
    """
    ip = _get_client_ip(request) if request else "unknown"

    # Check rate limit before attempting authentication
    _check_login_rate_limit(ip)

    user = authenticate_user(db, form_data.email, form_data.password)
    if not user:
        _record_login_failure(ip)
        log_system_activity(
            db=db,
            user_id=None,
            request=request,
            action_type="LOGIN_FAILED",
            category="SECURITY",
            target_type="user",
            target_display_label=form_data.email,
            outcome="FAILURE",
            summary=f"Failed login attempt for {form_data.email}",
            action_details={"email": form_data.email, "reason": "Incorrect email or password"}
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        _record_login_failure(ip)
        log_system_activity(
            db=db,
            user_id=user.id,
            request=request,
            action_type="LOGIN_FAILED",
            category="SECURITY",
            target_type="user",
            target_id=str(user.id),
            target_display_label=user.email,
            outcome="FAILURE",
            summary=f"Failed login attempt for {user.email} (Inactive user)",
            action_details={"email": user.email, "reason": "Inactive user"}
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Inactive user"
        )
    # Check approval status for all roles
    if user.approval_status != "APPROVED":
        _record_login_failure(ip)
        if user.role == "EMPLOYEE":
            detail = "Account not approved by manager"
        else:
            detail = "Account not approved"
        log_system_activity(
            db=db,
            user_id=user.id,
            request=request,
            action_type="LOGIN_FAILED",
            category="SECURITY",
            target_type="user",
            target_id=str(user.id),
            target_display_label=user.email,
            outcome="FAILURE",
            summary=f"Failed login attempt for {user.email} (Unapproved)",
            action_details={"email": user.email, "reason": detail}
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail
        )

    # If 2FA is enabled, return a 2FA challenge token
    if user.is_2fa_enabled:
        log_system_activity(
            db=db,
            user_id=user.id,
            request=request,
            action_type="LOGIN_CHALLENGE_REQUIRED",
            category="SECURITY",
            target_type="user",
            target_id=str(user.id),
            target_display_label=user.email,
            outcome="SUCCESS",
            summary=f"2FA challenge required for {user.email}",
            action_details={"email": user.email, "role": user.role, "login_type": "2fa_challenge"}
        )
        # Create short-lived 5-minute 2FA challenge token
        challenge_token_expires = timedelta(minutes=5)
        challenge_token = create_access_token(
            data={
                "sub": user.email,
                "type": "2fa_challenge",
                "challenge": "login"
            },
            expires_delta=challenge_token_expires
        )
        # Don't clear failures yet; only on successful 2FA completion
        return {
            "access_token": challenge_token,
            "token_type": "bearer",
            "requires_2fa": True,
            "message": "Two-factor authentication required."
        }

    # Restricted first-login token for users who must change password
    if user.must_change_password:
        _clear_login_failures(ip)
        log_system_activity(
            db=db,
            user_id=user.id,
            request=request,
            action_type="LOGIN_PASSWORD_CHANGE_REQUIRED",
            category="SECURITY",
            target_type="user",
            target_id=str(user.id),
            target_display_label=user.email,
            outcome="SUCCESS",
            summary=f"Password change required for {user.email}",
            action_details={"email": user.email, "role": user.role, "login_type": "password_change_required"}
        )
        restricted_token = create_access_token(
            data={
                "sub": user.email,
                "type": "restricted",
                "version": user.password_change_token_version
            },
            expires_delta=timedelta(minutes=15)
        )
        return {
            "access_token": restricted_token,
            "token_type": "bearer",
            "requires_2fa": False,
            "message": "Password change required"
        }

    # Successful login: clear failure counter and return access token + refresh token
    _clear_login_failures(ip)
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email, "type": "access"}, expires_delta=access_token_expires
    )
    refresh_token_expires = timedelta(days=7)
    refresh_token = create_refresh_token(
        data={"sub": user.email}, expires_delta=refresh_token_expires
    )
    # Hash and store refresh token
    user.refresh_token_hash = hash_refresh_token(refresh_token)
    user.refresh_token_expires_at = datetime.now(timezone.utc) + refresh_token_expires
    db.commit()

    log_system_activity(
        db=db,
        user_id=user.id,
        request=request,
        action_type="LOGIN_SUCCESS",
        category="SECURITY",
        target_type="user",
        target_id=str(user.id),
        target_display_label=user.email,
        outcome="SUCCESS",
        summary=f"Successful login for {user.email}",
        action_details={"email": user.email, "role": user.role, "login_type": "full"}
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "requires_2fa": False
    }


@router.post("/change-password", response_model=PasswordChangeResponse)
def change_password(
    request: PasswordChangeRequest,
    current_user: User = Depends(get_current_restricted_user),
    db: Session = Depends(get_db)
):
    """Restricted user changes their temporary password. Invalidates old restricted token."""
    # Verify current password
    if not verify_password(request.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect"
        )
    # Validate new password
    is_valid, error_msg = UserCreate.validate_password(request.new_password)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg
        )
    # Update
    current_user.password_hash = get_password_hash(request.new_password)
    current_user.must_change_password = False
    current_user.password_change_token_version += 1
    db.commit()

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="PASSWORD_CHANGED",
        category="SECURITY",
        target_type="user",
        target_id=str(current_user.id),
        target_display_label=current_user.email,
        outcome="SUCCESS",
        summary=f"Password changed for {current_user.email}",
        action_details={"email": current_user.email}
    )

    return PasswordChangeResponse(message="Password changed successfully.")


@router.get("/restricted/me", response_model=UserResponse)
def restricted_me(
    current_user: User = Depends(get_current_restricted_user)
):
    """Restricted user identity info (minimal first-login setup only)."""
    return current_user


@router.get("/me", response_model=UserResponse)
def read_users_me(current_user: User = Depends(get_current_active_user)):
    """
    Get current user information.
    """
    return current_user


@router.post("/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(request: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Request a password reset token.
    - For security, always return the same message regardless of whether email exists
    - In production, actually send an email with the token
    - For development, return the token in the response to simulate email
    """
    user = db.query(User).filter(User.email == request.email).first()

    # Always return same message to prevent email enumeration
    if user:
        # Generate reset token
        reset_token = generate_reset_token()
        hashed_token = hash_reset_token(reset_token)

        # Store hashed token and expiration (1 hour from now)
        user.reset_token_hash = hashed_token
        user.reset_token_expires_at = datetime.now(timezone.utc) + timedelta(hours=1)

        db.commit()

        # In production, send email here
        # For development, return token to simulate email delivery
        return ForgotPasswordResponse(
            message="If the email exists in our system, you will receive password reset instructions."
        )

    # Return same message even if user doesn't exist
    return ForgotPasswordResponse(
        message="If the email exists in our system, you will receive password reset instructions.",
        reset_token=None  # No token if user doesn't exist
    )


@router.post("/reset-password", response_model=ResetPasswordResponse)
def reset_password(request: ResetPasswordRequest, db: Session = Depends(get_db)):
    """
    Reset password using a token.
    Password must be at least 12 characters.
    """
    # Validate new password
    is_valid, error_msg = UserCreate.validate_password(request.new_password)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg
        )

    # Find user with valid reset token bound to email
    user = db.query(User).filter(
        User.email == request.email,
        User.reset_token_hash.is_not(None),
        User.reset_token_expires_at > datetime.now(timezone.utc)
    ).first()

    if not user or not verify_reset_token(request.token, user.reset_token_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token"
        )

    # Update password
    hashed_password = get_password_hash(request.new_password)
    user.password_hash = hashed_password

    # Clear reset token fields (token used once)
    user.reset_token_hash = None
    user.reset_token_expires_at = None

    db.commit()

    log_system_activity(
        db=db,
        user_id=user.id,
        action_type="PASSWORD_RESET",
        category="SECURITY",
        target_type="user",
        target_id=str(user.id),
        target_display_label=user.email,
        outcome="SUCCESS",
        summary=f"Password reset completed for {user.email}",
        action_details={"email": user.email}
    )

    return ResetPasswordResponse(
        message="Password has been successfully reset. You can now log in with your new password."
    )


# TOTP 2FA Endpoints
@router.post("/totp/setup", response_model=TotpSetupResponse)
def setup_totp(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Set up TOTP 2FA for the current user.
    Returns a secret and provisioning URI for QR code generation.
    Does not enable 2FA until verification is successful.
    """
    # Generate new secret
    secret = generate_totp_secret()

    # Store as pending secret with 10-minute expiration
    current_user.pending_totp_secret = secret
    current_user.pending_totp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    db.commit()

    # Generate provisioning URI
    provisioning_uri = get_totp_uri(secret, current_user.email)

    return TotpSetupResponse(
        secret=secret,
        provisioning_uri=provisioning_uri,
        qr_code_data=provisioning_uri  # In a real app, you'd generate an actual QR code image
    )


@router.post("/totp/verify-setup", response_model=TotpToggleResponse)
def verify_totp_setup(
    request: TotpVerifyRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Verify and complete TOTP 2FA setup.
    Validates the TOTP code against the pending secret and enables 2FA if valid.
    """
    # Check if there's a pending setup
    if not current_user.pending_totp_secret or not current_user.pending_totp_expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No TOTP setup in progress. Please start setup first."
        )

    # Check if pending secret has expired
    if current_user.pending_totp_expires_at < datetime.now(timezone.utc):
        # Clear expired pending data
        current_user.pending_totp_secret = None
        current_user.pending_totp_expires_at = None
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="TOTP setup has expired. Please start setup again."
        )

    # Verify the TOTP code
    if not verify_totp(current_user.pending_totp_secret, request.token):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid TOTP code"
        )

    # Setup successful - move pending secret to permanent and enable 2FA
    current_user.totp_secret = current_user.pending_totp_secret
    current_user.is_2fa_enabled = True
    current_user.pending_totp_secret = None
    current_user.pending_totp_expires_at = None

    db.commit()

    return TotpToggleResponse(
        is_2fa_enabled=True,
        message="Two-factor authentication has been successfully enabled."
    )


@router.post("/totp/disable", response_model=TotpToggleResponse)
def disable_totp(
    request: TotpDisableRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Disable TOTP 2FA for the current user.
    Requires current password and valid TOTP code for security.
    """
    # Check if 2FA is enabled
    if not current_user.is_2fa_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is not enabled"
        )

    # Verify password
    if not verify_password(request.password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incorrect password"
        )

    # Verify TOTP code
    if not current_user.totp_secret or not verify_totp(current_user.totp_secret, request.token):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid TOTP code"
        )

    # Disable 2FA and clear secret
    current_user.is_2fa_enabled = False
    current_user.totp_secret = None

    db.commit()

    return TotpToggleResponse(
        is_2fa_enabled=False,
        message="Two-factor authentication has been disabled."
    )


@router.post("/login/2fa", response_model=Token)
def verify_login_2fa(
    request: TokenChallengeVerify,
    db: Session = Depends(get_db)
):
    """
    Verify TOTP code during login and issue final access token.
    Requires a valid 2FA challenge token and correct TOTP code.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        # Decode the challenge token
        payload = jwt.decode(request.challenge_token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        token_type: str = payload.get("type")
        challenge: str = payload.get("challenge")

        # Validate token type and challenge
        if email is None or token_type != "2fa_challenge" or challenge != "login":
            raise credentials_exception

    except JWTError:
        raise credentials_exception

    # Find user by email
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception

    # Check if 2FA is enabled for this user
    if not user.is_2fa_enabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Two-factor authentication is not enabled for this account"
        )

    # Verify TOTP code
    if not user.totp_secret or not verify_totp(user.totp_secret, request.totp_token):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid TOTP code"
        )

    # Log successful 2FA login completion
    log_system_activity(
        db=db,
        user_id=user.id,
        action_type="LOGIN_SUCCESS",
        category="SECURITY",
        target_type="user",
        target_id=str(user.id),
        target_display_label=user.email,
        outcome="SUCCESS",
        summary=f"Successful 2FA login completion for {user.email}",
        action_details={"email": user.email, "role": user.role, "login_type": "2fa_completed"}
    )

    # TOTP verified - issue normal access token
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email, "type": "access"}, expires_delta=access_token_expires
    )

    return {"access_token": access_token, "token_type": "bearer"}


@router.get("/admin/users", response_model=PaginatedUsersResponse)
def get_all_users(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
    page: int = Query(1, ge=1),
    limit: int = Query(25, ge=1, le=100),
    search: Optional[str] = None,
    role: Optional[str] = None,
    status: Optional[str] = None,
    organization: Optional[str] = None,
):
    """
    Get all users with optional filtering and pagination.
    Only accessible by ADMIN.
    Supports filtering by search term, role, and approval status.
    Returns structured pagination response.
    """
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if org_ids:
        query = db.query(User).options(joinedload(User.profile)).join(
            OrganizationMembership, OrganizationMembership.user_id == User.id
        ).filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED"
        ).distinct()
    else:
        query = db.query(User).options(joinedload(User.profile))

    # Apply filters
    if search:
        search_term = f"%{search}%"
        query = query.filter(
            (User.email.ilike(search_term)) |
            (User.full_name.ilike(search_term)) |
            (User.organization_name.ilike(search_term))
        )

    if organization:
        query = query.filter(User.organization_name.ilike(f"%{organization}%"))

    if role:
        query = query.filter(User.role == role)

    if status:
        query = query.filter(User.approval_status == status)

    total = query.count()
    total_pages = (total + limit - 1) // limit if limit > 0 else 1

    # Order by newest first
    query = query.order_by(User.created_at.desc())

    # Pagination
    offset = (page - 1) * limit
    users = query.offset(offset).limit(limit).all()

    user_responses = [
        UserResponse(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            account_type=user.account_type,
            organization_name=user.organization_name,
            role=user.role,
            approval_status=user.approval_status,
            is_active=user.is_active,
            must_change_password=user.must_change_password,
            job_role=user.profile.job_role if user.profile else None,
            password_change_token_version=user.password_change_token_version,
            created_at=user.created_at,
            updated_at=user.updated_at,
        )
        for user in users
    ]

    return {
        "users": user_responses,
        "total": total,
        "page": page,
        "limit": limit,
        "total_pages": total_pages,
    }


@router.post("/admin/users/{user_id}/reset-password")
def admin_reset_user_password(
    user_id: str,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Reset a user's password by an admin.
    Only accessible by ADMIN.
    Generates a secure temporary password, sets must_change_password=True,
    invalidates existing sessions/tokens, and logs system activity.
    """
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format"
        )

    target_user = db.query(User).filter(User.id == user_uuid).first()
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    is_system_admin = (current_user.role and current_user.role.strip().upper() == "ADMIN" and not current_user.organization_name)

    if not is_system_admin:
        admin_org_ids = get_organization_ids_for_user(db, current_user.id)
        if admin_org_ids:
            emp_membership = db.query(OrganizationMembership).filter(
                OrganizationMembership.user_id == target_user.id,
                OrganizationMembership.organization_id.in_(admin_org_ids),
                OrganizationMembership.status == "APPROVED"
            ).first()
            if not emp_membership:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="User does not belong to your organization"
                )

    temp_password = secrets.token_urlsafe(16)
    target_user.password_hash = get_password_hash(temp_password)
    target_user.must_change_password = True
    target_user.password_change_token_version += 1
    target_user.reset_token_hash = None
    target_user.reset_token_expires_at = None
    target_user.refresh_token_hash = None
    target_user.refresh_token_expires_at = None

    db.commit()

    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="ADMIN_PASSWORD_RESET",
        category="SECURITY",
        target_type="user",
        target_id=str(target_user.id),
        target_display_label=target_user.email,
        outcome="SUCCESS",
        summary=f"Admin reset password for {target_user.email}",
        action_details={"target_user_id": str(target_user.id), "email": target_user.email}
    )

    return {
        "message": "Password reset successfully. Temporary password generated.",
        "temporary_password": temp_password
    }


@router.delete("/delete-account", status_code=status.HTTP_204_NO_CONTENT)
def delete_account(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Delete the authenticated user's account and all associated user-owned data.
    Uses the authenticated identity only; does not accept a user ID from client.
    Transactional: rolls back on failure.
    """
    user = current_user
    user_id = user.id

    try:
        # 1. Anonymize audit logs (retain records, set user_id to NULL)
        db.query(SystemActivityLog).filter(
            SystemActivityLog.user_id == user_id
        ).update({"user_id": None}, synchronize_session=False)

        # 2. Handle team invitations where user is inviter (RESTRICT on FK)
        # Delete invitations sent by this user to satisfy RESTRICT constraint
        db.query(TeamInvitation).filter(
            TeamInvitation.invited_by == user_id
        ).delete(synchronize_session=False)

        # 3. Handle tasks assigned_by_user_id (SET NULL strategy)
        # Tasks owned via profile will cascade when profile is deleted.
        # For tasks assigned by this user, set assigned_by_user_id to NULL
        db.query(Task).filter(
            Task.assigned_by_user_id == user_id
        ).update({"assigned_by_user_id": None}, synchronize_session=False)

        # 4. Soft-delete the user (preserves shared relationships; triggers profile cascade)
        # Profile cascade deletes profile and related work_sessions/breaks/tasks/recommendations
        user.is_active = False

        # 5. Explicitly clean remaining user-owned records that may not be fully covered
        # Notifications (CASCADE via FK)
        db.query(Notification).filter(
            Notification.recipient_user_id == user_id
        ).delete(synchronize_session=False)

        # User settings (CASCADE via FK)
        db.query(UserSettings).filter(
            UserSettings.user_id == user_id
        ).delete(synchronize_session=False)

        # Recommendation feedback (CASCADE via FK from user)
        db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_id == user_id
        ).delete(synchronize_session=False)

        # Organization memberships (CASCADE via FK)
        db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == user_id
        ).delete(synchronize_session=False)

        # Team memberships via profile cascade; profile deleted when user hard-deleted.
        # Here we rely on profile cascade via SQLAlchemy relationship.
        # To ensure profile is removed: delete profile explicitly
        profile = db.query(Profile).filter(Profile.user_id == user_id).first()
        if profile:
            db.delete(profile)

        db.commit()

        # After successful deletion, invalidate authentication by clearing token data
        user.password_hash = "DELETED"
        user.reset_token_hash = None
        user.reset_token_expires_at = None
        user.totp_secret = None
        user.pending_totp_secret = None
        user.pending_totp_expires_at = None
        db.commit()

        return None  # 204 No Content
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Account deletion failed. No changes have been made."
        )


@router.post("/logout")
def logout(
    request: Request,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Logout the current user by invalidating the refresh token.
    """
    # Invalidate refresh token by clearing its hash and expiration
    current_user.refresh_token_hash = None
    current_user.refresh_token_expires_at = None
    db.commit()

    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="LOGOUT",
        category="SECURITY",
        target_type="user",
        target_id=str(current_user.id),
        target_display_label=current_user.email,
        outcome="SUCCESS",
        summary=f"User logged out: {current_user.email}",
        action_details={"email": current_user.email}
    )

    return {"message": "Successfully logged out"}


@router.post("/refresh", response_model=Token)
def refresh_access_token(
    request: TokenChallenge,
    db: Session = Depends(get_db)
):
    """
    Refresh access token using a valid refresh token.
    Expects a refresh token in the challenge_token field.
    Returns a new access token.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        # Decode the refresh token
        payload = jwt.decode(request.challenge_token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        token_type: str = payload.get("type")

        # Validate token type
        if email is None or token_type != "refresh":
            raise credentials_exception

    except JWTError:
        raise credentials_exception

    # Find user by email
    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception

    # Verify refresh token against stored hash and check expiration
    if not user.refresh_token_hash or not user.refresh_token_expires_at:
        raise credentials_exception
    if datetime.now(timezone.utc) > user.refresh_token_expires_at:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not verify_refresh_token_hash(request.challenge_token, user.refresh_token_hash):
        raise credentials_exception

    # Check if user is active
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Inactive user"
        )

    # Check approval status
    if user.approval_status != "APPROVED":
        if user.role == "EMPLOYEE":
            detail = "Account not approved by manager"
        else:
            detail = "Account not approved"
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail
        )

    # Issue new access token
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.email, "type": "access"}, expires_delta=access_token_expires
    )

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "requires_2fa": False
    }
