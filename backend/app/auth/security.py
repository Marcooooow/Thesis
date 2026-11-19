from datetime import datetime, timedelta, timezone
from typing import Optional, Union
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from fastapi import Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer
from ..models import User, SystemActivityLog, OrganizationMembership, Profile, UserSettings
import uuid
import os
import sys
import bcrypt
import hashlib
import logging
import secrets
import pyotp
from ..database import get_db

logger = logging.getLogger(__name__)

# SECRET_KEY is validated at application startup in main.py
# This module just reads the value; validation happens in main.py _validate_secret_key()
SECRET_KEY = os.getenv("SECRET_KEY")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "480"))  # Default to 8 hours (480 min) to support work shifts
REFRESH_TOKEN_EXPIRE_DAYS = 7

# Password hashing context (legacy fallback)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# OAuth2 password bearer scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plain password against its hash (standard bcrypt, SHA-256 pre-hashed bcrypt, legacy passlib)."""
    # 1. Standard bcrypt (raw password)
    try:
        if bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8')):
            return True
    except Exception:
        pass
    # 2. SHA-256 pre-hashed bcrypt (current get_password_hash format)
    try:
        sha256_pass = hashlib.sha256(plain_password.encode('utf-8')).hexdigest()
        if bcrypt.checkpw(sha256_pass.encode('utf-8'), hashed_password.encode('utf-8')):
            return True
    except Exception:
        pass
    # 3. Legacy passlib
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    """Generate password hash from plain password using SHA-256 pre-hashed bcrypt to support passwords > 72 bytes safely."""
    sha256_pass = hashlib.sha256(password.encode('utf-8')).hexdigest()
    return bcrypt.hashpw(sha256_pass.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')


def authenticate_user(db: Session, email: str, password: str) -> Optional[User]:
    """Authenticate a user by email and password."""
    user = db.query(User).filter(User.email == email).first()
    if not user:
        return None
    if not verify_password(password, user.password_hash):
        return None
    return user
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a JWT access token."""
    to_encode = data.copy()
    to_encode.setdefault("type", "access")
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    """Get the current authenticated user from JWT token."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        token_type: str = payload.get("type")

        # Only allow access tokens for normal authentication
        if email is None or token_type != "access":
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception
    return user


async def get_current_active_user(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> User:
    """Get the current active user (not soft-deleted) and ensure profile/settings exist safely."""
    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")

    try:
        # Ensure profile exists for restored/imported backup accounts
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            profile = Profile(
                user_id=current_user.id,
                target_daily_hours=8,
                work_days=['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
            )
            db.add(profile)
            db.commit()

        # Ensure user settings exist
        settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
        if not settings:
            settings = UserSettings(
                user_id=current_user.id,
                timezone='UTC'
            )
            db.add(settings)
            db.commit()
    except IntegrityError:
        db.rollback()
    except Exception:
        db.rollback()
        raise

    return current_user


def get_current_admin_user(
    current_user: User = Depends(get_current_active_user),
) -> User:
    """Dependency to check if current user is admin."""
    if not current_user.role or current_user.role.strip().upper() != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )
    return current_user


async def get_current_restricted_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    """Get current user from restricted first-login token only."""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid restricted token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub")
        token_type = payload.get("type")
        if email is None or token_type != "restricted":
            raise credentials_exception
        user = db.query(User).filter(User.email == email).first()
        if user is None:
            raise credentials_exception
        if payload.get("version") != user.password_change_token_version:
            raise credentials_exception
        if not user.must_change_password:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    return user


def get_current_manager_user(
    current_user: User = Depends(get_current_active_user),
) -> User:
    """Dependency to check if current user is manager or admin."""
    role = (current_user.role or "").strip().upper()
    if role not in ["MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )
    return current_user


def get_current_manager_only_user(
    current_user: User = Depends(get_current_active_user),
) -> User:
    """Dependency to check if current user is manager (MANAGER role only, not ADMIN)."""
    role = (current_user.role or "").strip().upper()
    if role != "MANAGER":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )
    return current_user


def get_current_employee_user(
    current_user: User = Depends(get_current_active_user),
) -> User:
    """Dependency to check if current user is employee, manager, or admin."""
    role = (current_user.role or "").strip().upper()
    if role not in ["EMPLOYEE", "MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )
    return current_user


def should_include_test_data(db: Session, user: User) -> bool:
    """Determine if test data should be included for this user based on backend organization membership and environment."""
    if not user or not getattr(user, "is_active", True) or getattr(user, "approval_status", "APPROVED") == "REJECTED":
        return False
    env = os.getenv("ENVIRONMENT", "").lower()
    allow = os.getenv("INTELLIBREAK_ALLOW_TEST_DATA", "").lower() in ("true", "1", "yes")
    if env == "production" and not allow:
        return False
    from ..models import Organization, OrganizationMembership
    demo_org_names = ["IntelliBreak Thesis Demo Organization", "IntelliBreak Defense Organization"]
    orgs = db.query(Organization).filter(Organization.name.in_(demo_org_names)).all()
    if not orgs:
        return False
    org_ids = [org.id for org in orgs]
    membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == user.id,
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED"
    ).first()
    return membership is not None


def get_password_context() -> CryptContext:
    """Get the password hashing context."""
    return pwd_context


def generate_reset_token() -> str:
    """Generate a secure random password reset token."""
    return secrets.token_urlsafe(32)


def hash_reset_token(token: str) -> str:
    """Hash a reset token for storage."""
    return pwd_context.hash(token)


def verify_reset_token(token: str, hashed_token: str) -> bool:
    """Verify a reset token against its hash."""
    return pwd_context.verify(token, hashed_token)


def log_system_activity(
    db: Session,
    user_id: Optional[uuid.UUID],
    action_type: str,
    action_details: Optional[dict] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
    request: Optional[Request] = None,
    category: Optional[str] = None,
    target_type: Optional[str] = None,
    target_id: Optional[str] = None,
    target_display_label: Optional[str] = None,
    outcome: Optional[str] = None,
    summary: Optional[str] = None,
):
    """Log an activity to the system activity logs with structured metadata."""
    details = action_details or {}

    if request:
        if not ip_address:
            forwarded = request.headers.get("x-forwarded-for")
            if forwarded:
                ip_address = forwarded.split(",")[0].strip()
            elif request.client:
                ip_address = request.client.host
        if not user_agent:
            user_agent = request.headers.get("user-agent")

    resolved_category = category or details.get("category")
    if not resolved_category:
        if "USER" in action_type or "ROLE" in action_type or "ACCOUNT" in action_type:
            resolved_category = "ACCOUNT"
        elif "TEAM" in action_type:
            resolved_category = "TEAM"
        elif "RECOMMENDATION" in action_type or "ANALYTICS" in action_type or "WELLBEING" in action_type or "FOCUS" in action_type or "WORK_HOURS" in action_type:
            resolved_category = "ANALYTICS"
        elif "SETTING" in action_type:
            resolved_category = "SETTINGS"
        elif "LOGIN" in action_type or "LOGOUT" in action_type or "SECURITY" in action_type or "PASSWORD" in action_type or "TOTP" in action_type:
            resolved_category = "SECURITY"
        else:
            resolved_category = "SYSTEM"

    resolved_outcome = outcome or details.get("outcome") or "SUCCESS"
    resolved_summary = summary or details.get("summary") or action_type.replace("_", " ").title()

    resolved_target_type = target_type or details.get("target_type")
    resolved_target_id = target_id or details.get("target_id")
    resolved_target_display_label = target_display_label or details.get("target_display_label")

    details["category"] = resolved_category
    details["outcome"] = resolved_outcome
    details["summary"] = resolved_summary
    if resolved_target_type:
        details["target_type"] = resolved_target_type
    if resolved_target_id:
        details["target_id"] = resolved_target_id
    if resolved_target_display_label:
        details["target_display_label"] = resolved_target_display_label

    log_entry = SystemActivityLog(
        user_id=user_id,
        action_type=action_type,
        action_details=details,
        ip_address=ip_address,
        user_agent=user_agent
    )
    db.add(log_entry)
    db.commit()
    db.refresh(log_entry)
    return log_entry


def generate_totp_secret() -> str:
    """Generate a new TOTP secret key."""
    return pyotp.random_base32()


def get_totp_uri(secret: str, email: str, issuer: str = "IntelliBreak") -> str:
    """Generate TOTP provisioning URI for QR code."""
    totp = pyotp.TOTP(secret)
    return totp.provisioning_uri(name=email, issuer_name=issuer)


def verify_totp(secret: str, token: str, window: int = 1) -> bool:
    """Verify a TOTP token against the secret.

    Args:
        secret: The TOTP secret key
        token: The 6-digit TOTP token
        window: Validation window (default 1 allows for +/- 30 seconds)
    """
    if not secret or not token:
        return False
    try:
        totp = pyotp.TOTP(secret)
        return totp.verify(token, valid_window=window)
    except Exception:
        return False


def get_organization_ids_for_user(db: Session, user_id: uuid.UUID):
    """Get organization IDs for which the user has an approved membership."""
    org_ids = db.query(OrganizationMembership.organization_id).filter(
        OrganizationMembership.user_id == user_id,
        OrganizationMembership.status == "APPROVED"
    ).all()
    return [org_id for (org_id,) in org_ids]


def create_refresh_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a JWT refresh token."""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(days=7)  # Default 7 days
    to_encode.update({"exp": expire, "type": "refresh"})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def verify_refresh_token(token: str) -> Optional[dict]:
    """Verify and decode a refresh token."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        token_type: str = payload.get("type")
        if token_type != "refresh":
            return None
        return payload
    except JWTError:
        return None


def hash_refresh_token(token: str) -> str:
    """Hash a refresh token for storage."""
    token_digest = hashlib.sha256(token.encode('utf-8')).hexdigest()
    try:
        return bcrypt.hashpw(token_digest.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    except Exception:
        return pwd_context.hash(token_digest)


def verify_refresh_token_hash(plain_token: str, hashed_token: str) -> bool:
    """Verify a plain refresh token against its hash."""
    token_digest = hashlib.sha256(plain_token.encode('utf-8')).hexdigest()
    try:
        if hashed_token.startswith("$2"):
            return bcrypt.checkpw(token_digest.encode('utf-8'), hashed_token.encode('utf-8'))
    except Exception:
        pass
    return pwd_context.verify(token_digest, hashed_token)