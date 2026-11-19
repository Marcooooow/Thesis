"""Schemas for manager provisioning requests and responses."""

from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional
from uuid import UUID


class ManagerCreateRequest(BaseModel):
    """Request to create a new manager by an admin."""
    email: EmailStr
    full_name: str
    organization_id: UUID

    @field_validator('email')
    @classmethod
    def normalize_email(cls, v: str) -> str:
        """Normalize email to lowercase."""
        return v.lower().strip()


class ManagerCreateResponse(BaseModel):
    """Response for manager creation, includes temporary password."""
    id: UUID
    email: str
    full_name: str
    is_active: bool
    role: str
    approval_status: str
    must_change_password: bool
    temporary_password: str

    # Organization info
    organization_id: UUID
    organization_name: str

    model_config = {
        "from_attributes": True
    }