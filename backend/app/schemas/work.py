from pydantic import BaseModel, Field, model_validator, ConfigDict
from typing import Any, Optional
from datetime import datetime
from enum import Enum
import uuid

class WorkloadWarning(BaseModel):
    code: str
    message: str
    details: dict[str, Any] = {}
    severity: str

class WorkloadRecommendation(BaseModel):
    action: str
    label: str
    description: str

class ShiftPolicyStatus(BaseModel):
    session_id: str
    elapsed_minutes: int
    actual_work_minutes: int
    total_break_minutes: int
    continuous_work_minutes: int
    continuous_work_warning: bool
    approaching_shift_end: bool
    is_overtime: bool
    overtime_minutes: int
    warnings: list[WorkloadWarning] = []

    model_config = ConfigDict(from_attributes=True)

class WorkSessionBase(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    started_at: datetime
    ended_at: Optional[datetime] = None
    shift_status: Optional[ShiftPolicyStatus] = None

    model_config = ConfigDict(from_attributes=True)

class WorkSessionStartResponse(WorkSessionBase):
    pass

class WorkSessionEndResponse(WorkSessionBase):
    duration_minutes: Optional[int] = None

class TaskType(str, Enum):
    PERSONAL = "PERSONAL"
    WORK = "WORK"

class TaskBase(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    work_session_id: Optional[uuid.UUID] = None
    assigned_by_user_id: Optional[uuid.UUID] = None
    task_type: TaskType = TaskType.PERSONAL
    title: str
    description: Optional[str] = None
    status: str
    category: Optional[str] = None
    priority: Optional[str] = None
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    blocked_reason: Optional[str] = None
    estimated_minutes: Optional[int] = None
    actual_minutes: Optional[int] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class TaskCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT)$")
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, gt=0)

    @model_validator(mode="before")
    @classmethod
    def reject_restricted_fields(cls, data: Any) -> Any:
        if isinstance(data, dict):
            forbidden = {"started_at", "ended_at", "assigned_by_user_id", "task_type"}
            supplied = forbidden & data.keys()
            if supplied:
                raise ValueError(
                    f"Fields {sorted(supplied)} cannot be set at task creation."
                )
        return data

    @model_validator(mode="after")
    def validate_dates(self) -> 'TaskCreateRequest':
        if self.scheduled_start_date and self.deadline and self.scheduled_start_date > self.deadline:
            raise ValueError("scheduled_start_date cannot be after deadline.")
        return self

class ManagerTaskAssignRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT)$")
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, gt=0)
    profile_id: uuid.UUID

    @model_validator(mode="after")
    def validate_dates(self) -> 'ManagerTaskAssignRequest':
        if self.scheduled_start_date and self.deadline and self.scheduled_start_date > self.deadline:
            raise ValueError("scheduled_start_date cannot be after deadline.")
        return self

class TaskUpdateRequest(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT|MEDIUM)$")
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, gt=0)

class TaskGroupUpdateRequest(BaseModel):
    old_title: str
    old_category: Optional[str] = None
    old_deadline: Optional[datetime] = None
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT|MEDIUM)$")
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, gt=0)

class AssigneeManageRequest(BaseModel):
    profile_id: uuid.UUID
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    category: Optional[str] = Field(None, max_length=100)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|URGENT|MEDIUM)$")
    deadline: Optional[datetime] = None
    scheduled_start_date: Optional[datetime] = None
    estimated_minutes: Optional[int] = Field(None, gt=0)

class TaskResponse(TaskBase):
    pass

class TaskStatusUpdateRequest(BaseModel):
    status: str = Field(..., pattern="^(TODO|IN_PROGRESS|DONE|BLOCKED)$")
    blocked_reason: Optional[str] = Field(None, max_length=500)

    @model_validator(mode="after")
    def validate_blocked_reason(self) -> 'TaskStatusUpdateRequest':
        if self.status == 'BLOCKED' and not self.blocked_reason:
            raise ValueError("blocked_reason is required when setting task status to BLOCKED.")
        return self

class BreakBase(BaseModel):
    id: uuid.UUID
    work_session_id: uuid.UUID
    break_type: str
    started_at: datetime
    ended_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class BreakResponse(BreakBase):
    duration_minutes: Optional[int] = None

class BreakStartRequest(BaseModel):
    break_type: str = Field(..., pattern="^(BREAK|BREAK_1|BREAK_2|LUNCH|MEAL|COACH_BREAK|OTHER|SHORT_BREAK)$")
    notes: Optional[str] = Field(None, max_length=500)
    recommendation_id: Optional[uuid.UUID] = None

class BreakExtendRequest(BaseModel):
    extension_minutes: Optional[int] = Field(15, gt=0, le=120)
    reason: Optional[str] = Field(None, max_length=500)

class SessionHistoryBreak(BaseModel):
    id: uuid.UUID
    break_type: str
    started_at: datetime
    ended_at: Optional[datetime]
    duration_minutes: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)

class SessionHistoryTask(BaseModel):
    id: uuid.UUID
    title: str
    description: Optional[str] = None
    category: Optional[str] = None
    status: str
    priority: Optional[str] = None
    estimated_minutes: Optional[int] = None
    actual_minutes: Optional[int] = None
    started_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class RecommendationHistoryItem(BaseModel):
    recommendation_id: uuid.UUID
    recommendation_type: str
    recommendation_text: Optional[str] = None
    reason: Optional[str] = None
    recommendation_score: float
    timestamp: datetime
    user_action: Optional[str] = None
    model_version: str
    work_session_id: Optional[uuid.UUID] = None
    provenance: Optional[str] = 'live'

    model_config = ConfigDict(from_attributes=True)

class RecommendationHistoryResponse(BaseModel):
    session_id: uuid.UUID
    items: list[RecommendationHistoryItem] = []

    model_config = ConfigDict(from_attributes=True)

class SessionHistoryResponse(BaseModel):
    id: uuid.UUID
    started_at: datetime
    ended_at: Optional[datetime]
    duration_minutes: Optional[int] = None
    breaks: list[SessionHistoryBreak] = []
    tasks: list[SessionHistoryTask] = []

    model_config = ConfigDict(from_attributes=True)

class TaskCategoryResponse(BaseModel):
    id: uuid.UUID
    name: str
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class TaskCategoryCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)

class TaskCategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    is_active: Optional[bool] = None

class ManagerWorkloadResponse(BaseModel):
    profile_id: str
    analysis_date: str
    horizon_days: int
    available_minutes: int
    available_hours: float
    existing_workload: dict[str, Any]
    new_task_estimated_minutes: Optional[int] = None
    new_total_minutes: Optional[int] = None
    new_total_hours: Optional[float] = None
    utilization_pct: float
    status: str
    severity: str
    warnings: list[WorkloadWarning] = []
    recommendations: list[WorkloadRecommendation] = []

    model_config = ConfigDict(from_attributes=True)

class ManagerTaskAssignResponse(TaskResponse):
    workload_analysis: Optional[ManagerWorkloadResponse] = None

    model_config = ConfigDict(from_attributes=True)
