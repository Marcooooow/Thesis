"""Pydantic schemas for user settings."""

from pydantic import BaseModel, Field, field_validator, ConfigDict
from typing import Optional
from datetime import datetime


class UserSettingsRead(BaseModel):
    """Settings response for GET /settings."""

    # Notification preferences
    notifications_enabled: bool = Field(default=True)
    break_reminders: bool = Field(default=True)
    shift_reminders: bool = Field(default=True)
    task_reminders: bool = Field(default=True)
    focus_reminders: bool = Field(default=True)
    wellness_reminders: bool = Field(default=True)
    daily_summary: bool = Field(default=False)
    weekly_summary: bool = Field(default=False)

    # Break and interval preferences
    break_interval_minutes: int = Field(default=30)
    break_duration_minutes: int = Field(default=10)

    # Break Coach preferences
    break_coach_enabled: bool = Field(default=True)
    break_coach_cooldown_minutes: int = Field(default=30)

    # Work and productivity preferences
    work_target_daily_hours: Optional[int] = Field(default=None)
    default_work_schedule: Optional[str] = Field(default=None)
    focus_target_percentage: Optional[int] = Field(default=None)
    idle_detection_sensitivity: Optional[str] = Field(default=None)

    # Timezone and regional preferences
    timezone: Optional[str] = Field(default=None)
    date_format: Optional[str] = Field(default=None)
    time_format: Optional[str] = Field(default=None)
    first_day_of_week: Optional[str] = Field(default=None)

    # Accessibility preferences
    reduce_motion: bool = Field(default=False)
    interface_density: Optional[str] = Field(default=None)

    # DND preferences
    manual_dnd_override: Optional[bool] = Field(default=None)
    quiet_hours_enabled: bool = Field(default=False)
    quiet_hours_start: Optional[str] = Field(default=None)
    quiet_hours_end: Optional[str] = Field(default=None)

    # Metadata
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserSettingsUpdate(BaseModel):
    """Settings update request for PATCH /settings."""

    # Notification preferences (optional on update)
    notifications_enabled: Optional[bool] = None
    break_reminders: Optional[bool] = None
    shift_reminders: Optional[bool] = None
    task_reminders: Optional[bool] = None
    focus_reminders: Optional[bool] = None
    wellness_reminders: Optional[bool] = None
    daily_summary: Optional[bool] = None
    weekly_summary: Optional[bool] = None

    # Break and interval preferences
    break_interval_minutes: Optional[int] = None
    break_duration_minutes: Optional[int] = None

    # Break Coach preferences
    break_coach_enabled: Optional[bool] = None
    break_coach_cooldown_minutes: Optional[int] = None

    # Work and productivity preferences
    work_target_daily_hours: Optional[int] = None
    default_work_schedule: Optional[str] = None
    focus_target_percentage: Optional[int] = None
    idle_detection_sensitivity: Optional[str] = None

    # Timezone and regional preferences
    timezone: Optional[str] = None
    date_format: Optional[str] = None
    time_format: Optional[str] = None
    first_day_of_week: Optional[str] = None

    # Accessibility preferences
    reduce_motion: Optional[bool] = None
    interface_density: Optional[str] = None
    manual_dnd_override: Optional[bool] = None
    quiet_hours_enabled: Optional[bool] = None
    quiet_hours_start: Optional[str] = None
    quiet_hours_end: Optional[str] = None

    @field_validator("break_interval_minutes")
    @classmethod
    def validate_break_interval(cls, v):
        if v is not None and v not in (15, 30, 45, 60, 90, 120):
            raise ValueError("break_interval_minutes must be one of: 15, 30, 45, 60, 90, 120")
        return v

    @field_validator("break_duration_minutes")
    @classmethod
    def validate_break_duration(cls, v):
        if v is not None and v not in (5, 10, 15, 20, 30):
            raise ValueError("break_duration_minutes must be one of: 5, 10, 15, 20, 30")
        return v

    @field_validator("break_coach_cooldown_minutes")
    @classmethod
    def validate_cooldown(cls, v):
        if v is not None and (v < 5 or v > 60):
            raise ValueError("break_coach_cooldown_minutes must be between 5 and 60")
        return v

    @field_validator("work_target_daily_hours")
    @classmethod
    def validate_daily_hours(cls, v):
        if v is not None and (v < 1 or v > 24):
            raise ValueError("work_target_daily_hours must be between 1 and 24")
        return v

    @field_validator("quiet_hours_start", "quiet_hours_end")
    @classmethod
    def validate_time_format(cls, v):
        if v is not None:
            import re
            if not re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", v):
                raise ValueError("Time must be in HH:mm format (00:00 to 23:59)")
        return v

    @field_validator("focus_target_percentage")
    @classmethod
    def validate_focus_percentage(cls, v):
        if v is not None and (v < 0 or v > 100):
            raise ValueError("focus_target_percentage must be between 0 and 100")
        return v

    @field_validator("idle_detection_sensitivity")
    @classmethod
    def validate_idle_sensitivity(cls, v):
        if v is not None and v not in ("LOW", "MEDIUM", "HIGH"):
            raise ValueError("idle_detection_sensitivity must be one of: LOW, MEDIUM, HIGH")
        return v

    @field_validator("time_format")
    @classmethod
    def validate_time_format_preference(cls, v):
        if v is not None and v not in ("12h", "24h"):
            raise ValueError("time_format must be '12h' or '24h'")
        return v

    @field_validator("interface_density")
    @classmethod
    def validate_interface_density(cls, v):
        if v is not None and v not in ("COMPACT", "COMFORTABLE", "SPACIOUS"):
            raise ValueError("interface_density must be one of: COMPACT, COMFORTABLE, SPACIOUS")
        return v
