from pydantic import BaseModel, Field, field_validator, ConfigDict
from typing import Optional, List
from datetime import date, datetime
import uuid

class WorkLifeBalanceSurveyCreate(BaseModel):
    week_start_date: date
    rating_disconnect: int = Field(..., description="Rating 1-5")
    rating_personal_time: int = Field(..., description="Rating 1-5")
    rating_responsibilities_balance: int = Field(..., description="Rating 1-5")
    rating_schedule_satisfaction: int = Field(..., description="Rating 1-5")
    rating_recovery: int = Field(..., description="Rating 1-5")

    @field_validator('rating_disconnect', 'rating_personal_time', 'rating_responsibilities_balance', 'rating_schedule_satisfaction', 'rating_recovery')
    @classmethod
    def validate_rating(cls, v: int) -> int:
        if not isinstance(v, int) or v < 1 or v > 5:
            raise ValueError("Ratings must be integers between 1 and 5 inclusive.")
        return v

    model_config = ConfigDict(from_attributes=True)

class WorkLifeBalanceSurveyResponse(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    organization_id: uuid.UUID
    week_start_date: date
    rating_disconnect: int
    rating_personal_time: int
    rating_responsibilities_balance: int
    rating_schedule_satisfaction: int
    rating_recovery: int
    score: float
    submitted_at: datetime

    model_config = ConfigDict(from_attributes=True)

class WorkLifeBalanceCheckResponse(BaseModel):
    week_start_date: date
    submitted: bool
    survey: Optional[WorkLifeBalanceSurveyResponse] = None

    model_config = ConfigDict(from_attributes=True)
