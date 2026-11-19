"""Schemas for organization-related requests and responses."""

from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from uuid import UUID


class OrganizationBase(BaseModel):
    """Base schema for organization."""
    name: str


class OrganizationCreate(OrganizationBase):
    """Schema for creating a new organization."""
    pass


class OrganizationResponse(OrganizationBase):
    """Schema for organization response."""
    id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }


class OrganizationMembershipBase(BaseModel):
    """Base schema for organization membership."""
    role: str
    status: str


class OrganizationMembershipCreate(OrganizationMembershipBase):
    """Schema for creating a new organization membership."""
    user_id: UUID
    organization_id: UUID


class OrganizationMembershipResponse(OrganizationMembershipBase):
    """Schema for organization membership response."""
    id: UUID
    user_id: UUID
    organization_id: UUID
    created_at: datetime
    updated_at: datetime

    model_config = {
        "from_attributes": True
    }


class OrganizationWithMemberships(OrganizationResponse):
    """Organization with its memberships."""
    memberships: List[OrganizationMembershipResponse] = []


class UserWithOrganizationMemberships(BaseModel):
    """User with their organization memberships."""
    id: UUID
    email: str
    full_name: str
    organization_memberships: List[OrganizationMembershipResponse] = []

    model_config = {
        "from_attributes": True
    }