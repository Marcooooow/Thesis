from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
from uuid import UUID
from .user_work_profile import UserWorkProfileCreate

VALID_ROLES = {"ADMIN", "MANAGER", "EMPLOYEE"}
VALID_ACCOUNT_TYPES = {"solo", "organization"}

# ponytail: small blocklist, add entries if pattern emerges
COMMON_WEAK_PASSWORDS = {
    "password",
    "12345678",
    "qwerty",
    "password123",
    "admin123",
    "123456789",
    "11111111",
    "passw0rd",
    "password1234",
    "qwerty123456",
    "12345678abcd",
}

class UserCreate(BaseModel):
    email: str
    password: str
    full_name: str
    account_type: str  # "solo" or "organization"
    organization_name: Optional[str] = None
    # role is not controllable via registration; always set to EMPLOYEE
    invitation_token: Optional[str] = None  # Token from team invitation link
    # Profile fields (optional during registration)
    job_role: Optional[str] = None
    industry: Optional[str] = None
    years_of_experience: Optional[int] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    education_attainment: Optional[str] = None
    marital_status: Optional[str] = None
    target_daily_hours: Optional[int] = None
    shift_start_time: Optional[str] = None
    shift_end_time: Optional[str] = None
    work_days: Optional[List[str]] = None
    work_profile: Optional[UserWorkProfileCreate] = None
    terms_accepted: Optional[bool] = None
    data_consent: Optional[bool] = None

    @staticmethod
    def validate_password(password: str) -> tuple[bool, Optional[str]]:
        """
        Validate password strength.
        Returns (is_valid, error_message)
        """
        if not password or len(password) < 12:
            return False, "Password must be at least 12 characters long."
        if password.lower() in COMMON_WEAK_PASSWORDS:
            return False, "This password is too common. Please choose a stronger password."
        return True, None

class UserLogin(BaseModel):
    email: str
    password: str

class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str
    requires_2fa: bool
    message: Optional[str] = None

class ForgotPasswordRequest(BaseModel):
    email: str

class ForgotPasswordResponse(BaseModel):
    message: str
    reset_token: Optional[str] = None

class ResetPasswordRequest(BaseModel):
    email: str
    token: str
    new_password: str

class ResetPasswordResponse(BaseModel):
    message: str

class TotpSetupResponse(BaseModel):
    secret: str
    provisioning_uri: str
    qr_code_data: str

class TotpVerifyRequest(BaseModel):
    token: str

class TotpVerifyResponse(BaseModel):
    success: bool

class TotpToggleResponse(BaseModel):
    is_2fa_enabled: bool
    message: str

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str


class PasswordChangeResponse(BaseModel):
    message: str


class TokenChallenge(BaseModel):
    challenge_token: str

class TokenChallengeVerify(BaseModel):
    challenge_token: str
    totp_token: str

class TotpDisableRequest(BaseModel):
    password: str
    token: str

class UserResponse(BaseModel):
    id: UUID
    email: str
    full_name: str
    account_type: str
    organization_name: Optional[str] = None
    role: str
    approval_status: str
    is_active: bool
    must_change_password: bool
    job_role: Optional[str] = None
    password_change_token_version: int
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }

class PaginatedUsersResponse(BaseModel):
    users: List[UserResponse]
    total: int
    page: int
    limit: int
    total_pages: int

class UserCountsResponse(BaseModel):
    employees: int
    managers: int
    pending: int

class AuditLogResponse(BaseModel):
    id: str
    user_id: Optional[str] = None
    user_full_name: Optional[str] = None
    user_email: Optional[str] = None
    action_type: str
    category: Optional[str] = "SYSTEM"
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    target_display_label: Optional[str] = None
    outcome: Optional[str] = "SUCCESS"
    summary: Optional[str] = None
    action_details: Optional[dict] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    created_at: datetime
