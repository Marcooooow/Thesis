"""Schemas for employee provisioning requests and responses."""

from pydantic import BaseModel, EmailStr, field_validator
from typing import List, Optional
from datetime import datetime
from uuid import UUID


class EmployeeCreateRequest(BaseModel):
    """Request to create a new employee by a manager."""
    email: EmailStr
    full_name: str
    team_id: Optional[str] = None
    target_daily_hours: Optional[int] = None
    shift_start_time: Optional[str] = None
    shift_end_time: Optional[str] = None
    working_days: Optional[List[str]] = None

    # Personal Information
    age: Optional[int] = None
    gender: Optional[str] = None
    phone_number: Optional[str] = None
    education_attainment: Optional[str] = None
    marital_status: Optional[str] = None

    # Work Information
    job_role: Optional[str] = None
    department: Optional[str] = None
    industry: Optional[str] = None
    years_of_experience: Optional[int] = None
    hire_date: Optional[str] = None

    @field_validator('team_id')
    @classmethod
    def validate_team_id(cls, v):
        if v is not None and isinstance(v, str):
            try:
                UUID(v)
                return v
            except ValueError:
                raise ValueError('Invalid team ID format')
        return v

    @field_validator('email')
    @classmethod
    def normalize_email(cls, v: str) -> str:
        """Normalize email to lowercase."""
        return v.lower().strip()


class EmployeeListResponse(BaseModel):
    id: UUID
    full_name: str
    email: str
    is_active: bool
    team_id: Optional[UUID] = None
    team_name: Optional[str] = None

    model_config = {
        "from_attributes": True
    }


class EmployeeCreateResponse(BaseModel):
    """Response for employee creation, includes temporary password."""
    id: UUID
    email: str
    full_name: str
    is_active: bool
    role: str
    approval_status: str
    must_change_password: bool
    temporary_password: str

    # Optional organization and team info
    organization_id: Optional[UUID] = None
    organization_name: Optional[str] = None
    team_id: Optional[UUID] = None
    team_name: Optional[str] = None

    model_config = {
        "from_attributes": True
    }