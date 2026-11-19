"""Schemas for team-related requests and responses."""

from pydantic import BaseModel, EmailStr, field_validator
from typing import List, Optional
from datetime import datetime
from uuid import UUID


class UserSearchResult(BaseModel):
    """Response for user search in team invitations."""
    id: UUID
    full_name: str
    email: str
    status: Optional[str] = None  # e.g., "active", "pending_invitation", "already_member"

    model_config = {
        "from_attributes": True
    }


class TeamCreateRequest(BaseModel):
    """Request to create a new team."""
    name: str
    description: Optional[str] = None


class TeamResponse(BaseModel):
    """Response containing team information."""
    id: UUID
    name: str
    description: Optional[str]
    manager_id: UUID
    manager_name: str
    member_count: int
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }


class TeamMemberResponse(BaseModel):
    """Response containing team member information."""
    profile_id: UUID
    user_id: UUID
    user_name: str
    user_email: str
    role: str
    joined_at: datetime
    is_current: bool  # True if left_at is NULL

    model_config = {
        "from_attributes": True
    }


class TeamInvitationCreateRequest(BaseModel):
    """Request to create/send a team invitation."""
    email: EmailStr
    role: str = "EMPLOYEE"  # Only EMPLOYEE allowed (invitations are employee-only)

    @field_validator('role')
    @classmethod
    def validate_role(cls, v):
        allowed_roles = {'EMPLOYEE'}
        if v.upper() not in allowed_roles:
            raise ValueError(f'Role must be one of {allowed_roles}')
        return v.upper()


class TeamInvitationResponse(BaseModel):
    """Response containing team invitation information."""
    id: UUID
    team_id: UUID
    team_name: str
    email: str
    invited_by: UUID
    inviter_name: str
    role: str
    status: str
    expires_at: datetime
    created_at: datetime
    accepted_at: Optional[datetime] = None
    declined_at: Optional[datetime] = None

    model_config = {
        "from_attributes": True
    }


class TeamInvitationListResponse(BaseModel):
    """Response containing a list of team invitations."""
    invitations: List[TeamInvitationResponse]
    total: int
    limit: int
    offset: int


class NotificationResponse(BaseModel):
    """Response containing notification information."""
    id: UUID
    type: str
    title: str
    message: str
    related_entity_id: Optional[UUID] = None
    is_read: bool
    is_actioned: bool
    created_at: datetime
    read_at: Optional[datetime] = None
    actioned_at: Optional[datetime] = None

    model_config = {
        "from_attributes": True
    }


class NotificationListResponse(BaseModel):
    """Response containing a list of notifications."""
    notifications: List[NotificationResponse]
    unread_count: int
    total: int
    limit: int
    offset: int


class NotificationMarkReadRequest(BaseModel):
    """Request to mark a notification as read."""
    pass


class InvitationValidationResponse(BaseModel):
    """Response containing validated invitation information for registration."""
    valid: bool
    invitation_id: Optional[UUID] = None
    email: Optional[str] = None
    team_name: Optional[str] = None
    role: Optional[str] = None
    expires_at: Optional[datetime] = None
    message: Optional[str] = None

    model_config = {
        "from_attributes": True
    }

