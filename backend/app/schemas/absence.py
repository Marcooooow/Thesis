from pydantic import BaseModel, Field, model_validator, ConfigDict
from typing import Optional, List
from datetime import date, time, datetime
import uuid

class EmployeeScheduleBase(BaseModel):
    effective_from: date
    effective_until: Optional[date] = None
    work_days: List[str]
    shift_start: time
    shift_end: time
    timezone: str = "Asia/Manila"

    @model_validator(mode='after')
    def validate_shift(self):
        if self.shift_start >= self.shift_end:
            raise ValueError("shift_start must be earlier than shift_end")
        if self.effective_until and self.effective_from > self.effective_until:
            raise ValueError("effective_from cannot be after effective_until")
        return self

class EmployeeScheduleCreate(EmployeeScheduleBase):
    pass

class EmployeeScheduleResponse(EmployeeScheduleBase):
    id: uuid.UUID
    profile_id: uuid.UUID
    created_by: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class LeaveTypeBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    requires_documentation: bool = False
    is_active: bool = True
    sort_order: int = 0

class LeaveTypeCreate(LeaveTypeBase):
    pass

class LeaveTypeUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    requires_documentation: Optional[bool] = None
    is_active: Optional[bool] = None
    sort_order: Optional[int] = None

class LeaveTypeResponse(LeaveTypeBase):
    id: uuid.UUID
    organization_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class LeaveRequestCreate(BaseModel):
    leave_type_id: uuid.UUID
    start_date: date
    end_date: date
    reason: Optional[str] = None

    @model_validator(mode='after')
    def validate_dates(self):
        if self.start_date > self.end_date:
            raise ValueError("start_date cannot be after end_date")
        return self

class LeaveRequestReview(BaseModel):
    approve: bool
    reviewer_note: Optional[str] = None

class LeaveRequestResponse(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    leave_type_id: uuid.UUID
    start_date: date
    end_date: date
    reason: Optional[str] = None
    status: str
    reviewed_by: Optional[uuid.UUID] = None
    reviewed_at: Optional[datetime] = None
    reviewer_note: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class AbsenceRecordResponse(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    absence_date: date
    schedule_id: uuid.UUID
    classification: str
    leave_request_id: Optional[uuid.UUID] = None
    detection_run_at: datetime
    grace_period_minutes: int
    notification_status: str
    manager_acknowledged_at: Optional[datetime] = None
    acknowledged_by: Optional[uuid.UUID] = None
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    employee_name: Optional[str] = None
    department: Optional[str] = None
    shift_start: Optional[time] = None
    shift_end: Optional[time] = None

    model_config = ConfigDict(from_attributes=True)

class AbsenceAcknowledgment(BaseModel):
    classification: str = Field(..., pattern="^(EXCUSED|DISMISSED)$")
    notes: Optional[str] = None

class ReturnToWorkSubmit(BaseModel):
    work_session_id: uuid.UUID
    absence_record_id: Optional[uuid.UUID] = None
    absence_reason_category: Optional[str] = Field(None, max_length=50)
    overall_feeling: Optional[int] = Field(None, ge=1, le=5)
    workload_concern: Optional[int] = Field(None, ge=1, le=5)
    stress_concern: Optional[int] = Field(None, ge=1, le=5)
    work_contributed_to_absence: Optional[bool] = None
    wants_manager_support: Optional[bool] = None
    additional_comments: Optional[str] = None
    is_manager_visible: bool = False

class ReturnToWorkResponse(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    work_session_id: uuid.UUID
    absence_record_id: Optional[uuid.UUID] = None
    absence_reason_category: Optional[str] = None
    overall_feeling: Optional[int] = None
    workload_concern: Optional[int] = None
    stress_concern: Optional[int] = None
    work_contributed_to_absence: Optional[bool] = None
    wants_manager_support: Optional[bool] = None
    additional_comments: Optional[str] = None
    is_manager_visible: bool
    submitted_at: datetime

    model_config = ConfigDict(from_attributes=True)

class ReturnToWorkManagerView(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    absence_reason_category: Optional[str] = None
    wants_manager_support: Optional[bool] = None
    submitted_at: datetime

    model_config = ConfigDict(from_attributes=True)
