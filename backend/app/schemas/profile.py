from pydantic import BaseModel, Field, model_validator, ConfigDict
from typing import Optional, List
from datetime import datetime, time
import re

class ProfileResponse(BaseModel):
    id: str
    full_name: str
    phone_number: Optional[str] = None
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
    hire_date: Optional[str] = None
    department: Optional[str] = None
    is_test_data: bool
    created_at: datetime
    updated_at: datetime
    profile_image_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=100)
    phone_number: Optional[str] = Field(None, max_length=20)
    job_role: Optional[str] = Field(None, max_length=100)
    industry: Optional[str] = Field(None, max_length=100)
    years_of_experience: Optional[int] = Field(None, ge=0)
    age: Optional[int] = Field(None, ge=18, le=100)
    gender: Optional[str] = Field(None, max_length=20)
    education_attainment: Optional[str] = Field(None, max_length=50)
    marital_status: Optional[str] = Field(None, max_length=20)
    target_daily_hours: Optional[int] = Field(None, ge=1, le=24)
    shift_start_time: Optional[str] = Field(None, pattern=r'^([0-1][0-9]|2[0-3]):[0-5][0-9]$')
    shift_end_time: Optional[str] = Field(None, pattern=r'^([0-1][0-9]|2[0-3]):[0-5][0-9]$')
    work_days: Optional[List[str]] = None
    hire_date: Optional[str] = Field(None, pattern=r'^\d{4}-\d{2}-\d{2}$')
    department: Optional[str] = Field(None, max_length=100)
    profile_image_url: Optional[str] = None

    @model_validator(mode='after')
    def validate_shift_times(self):
        if self.shift_start_time and self.shift_end_time:
            start_time = time.fromisoformat(self.shift_start_time)
            end_time = time.fromisoformat(self.shift_end_time)
            if start_time == end_time:
                raise ValueError('shift_start_time cannot equal shift_end_time')
        return self

    @model_validator(mode='after')
    def validate_work_days(self):
        if self.work_days is not None:
            valid_days = {'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'}
            for day in self.work_days:
                if day.lower() not in valid_days:
                    raise ValueError(f'Invalid work day: {day}. Must be one of {valid_days}')
        return self

    model_config = ConfigDict(from_attributes=True)
