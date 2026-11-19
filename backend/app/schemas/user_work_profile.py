from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List

class UserWorkProfileBase(BaseModel):
    schedule_type: Optional[str] = Field(None, max_length=50)
    typical_start_time: Optional[str] = None
    typical_end_time: Optional[str] = None
    working_days: Optional[List[str]] = None
    arrangement: Optional[str] = Field(None, max_length=50)
    typical_focus_duration: Optional[int] = Field(None, ge=5, le=480)
    preferred_focus_duration: Optional[int] = Field(None, ge=5, le=480)
    typical_break_frequency: Optional[int] = Field(None, ge=0, le=50)
    typical_break_duration: Optional[int] = Field(None, ge=1, le=120)
    lunch_start_time: Optional[str] = None
    lunch_duration: Optional[int] = Field(None, ge=5, le=180)
    lunch_consistency: Optional[str] = Field(None, max_length=50)
    responsibilities: Optional[List[str]] = None
    reminder_preference: Optional[str] = Field(None, max_length=50)
    recommendation_style: Optional[str] = Field(None, max_length=50)
    additional_preferences: Optional[str] = None
    profile_completed: Optional[bool] = False

class UserWorkProfileCreate(UserWorkProfileBase):
    pass

class UserWorkProfileUpdate(BaseModel):
    schedule_type: Optional[str] = Field(None, max_length=50)
    typical_start_time: Optional[str] = None
    typical_end_time: Optional[str] = None
    working_days: Optional[List[str]] = None
    arrangement: Optional[str] = Field(None, max_length=50)
    typical_focus_duration: Optional[int] = Field(None, ge=5, le=480)
    preferred_focus_duration: Optional[int] = Field(None, ge=5, le=480)
    typical_break_frequency: Optional[int] = Field(None, ge=0, le=50)
    typical_break_duration: Optional[int] = Field(None, ge=1, le=120)
    lunch_start_time: Optional[str] = None
    lunch_duration: Optional[int] = Field(None, ge=5, le=180)
    lunch_consistency: Optional[str] = Field(None, max_length=50)
    responsibilities: Optional[List[str]] = None
    reminder_preference: Optional[str] = Field(None, max_length=50)
    recommendation_style: Optional[str] = Field(None, max_length=50)
    additional_preferences: Optional[str] = None
    profile_completed: Optional[bool] = None

class UserWorkProfileResponse(BaseModel):
    id: str
    user_id: str
    schedule_type: Optional[str] = None
    typical_start_time: Optional[str] = None
    typical_end_time: Optional[str] = None
    working_days: Optional[List[str]] = None
    arrangement: Optional[str] = None
    typical_focus_duration: Optional[int] = None
    preferred_focus_duration: Optional[int] = None
    typical_break_frequency: Optional[int] = None
    typical_break_duration: Optional[int] = None
    lunch_start_time: Optional[str] = None
    lunch_duration: Optional[int] = None
    lunch_consistency: Optional[str] = None
    responsibilities: Optional[List[str]] = None
    reminder_preference: Optional[str] = None
    recommendation_style: Optional[str] = None
    additional_preferences: Optional[str] = None
    profile_completed: bool
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
