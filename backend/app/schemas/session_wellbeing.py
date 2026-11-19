from pydantic import BaseModel, Field, model_validator, ConfigDict
from typing import Any, Optional, List
from datetime import datetime
import uuid

class SessionWellbeingCheckinBase(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    work_session_id: uuid.UUID
    overall_wellbeing: int = Field(..., ge=1, le=5)
    mental_fatigue: int = Field(..., ge=1, le=5)
    workload_manageability: int = Field(..., ge=1, le=5)
    perceived_focus: int = Field(..., ge=1, le=5)
    break_recovery: int = Field(..., ge=1, le=5)
    stress_factors: Optional[List[str]] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class SessionWellbeingCheckinCreate(BaseModel):
    work_session_id: uuid.UUID
    overall_wellbeing: int = Field(..., ge=1, le=5)
    mental_fatigue: int = Field(..., ge=1, le=5)
    workload_manageability: int = Field(..., ge=1, le=5)
    perceived_focus: int = Field(..., ge=1, le=5)
    break_recovery: int = Field(..., ge=1, le=5)
    stress_factors: Optional[List[str]] = None
    notes: Optional[str] = None

class SessionWellbeingCheckinRead(SessionWellbeingCheckinBase):
    pass