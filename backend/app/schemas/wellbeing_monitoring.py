from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import date, datetime
import uuid
from enum import IntEnum, StrEnum, Enum


class RiskTier(IntEnum):
    INSUFFICIENT_DATA = 0
    LOW = 1
    MODERATE = 2
    HIGH = 3
    CRITICAL = 4


class CIStr(str):
    def __eq__(self, other):
        if isinstance(other, str):
            return self.lower() == other.lower()
        return super().__eq__(other)

    def __hash__(self):
        return hash(self.lower())


class TrendDirection(CIStr, Enum):
    IMPROVING = CIStr("improving")
    STABLE = CIStr("stable")
    WORSENING = CIStr("worsening")
    UNKNOWN = CIStr("unknown")

    def __str__(self):
        return self.name

    @classmethod
    def _missing_(cls, value):
        if isinstance(value, str):
            for member in cls:
                if member.lower() == value.lower():
                    return member
        return None


class EvidenceType(StrEnum):
    WORKED_HOURS_EXCESS = "worked_hours_excess"
    BREAK_COMPLIANCE_LOW = "break_compliance_low"
    WELLBEING_DECLINING = "wellbeing_declining"
    FOCUS_DECLINING = "focus_declining"
    SKIPPED_BREAKS = "skipped_breaks"


class EvidenceItem(BaseModel):
    type: EvidenceType
    description: str
    metric_value: float
    threshold: float
    days_affected: int


class DataQuality(BaseModel):
    sessions_count: int
    checkins_count: int
    baseline_source: str  # "personal_30d", "config_fallback:Profile", "config_fallback:UserSettings", "config_fallback:policy", "documented_default"
    partial_week: bool
    data_limitation: Optional[str] = None  # e.g., "no_prior_week", "insufficient_sessions"


class DetectedPattern(BaseModel):
    pattern_id: str
    detected: bool = False
    display_name: str
    evidence_strength: str  # "low", "medium", "high"
    measurement: str
    data_limitations: Optional[str] = None
    days_triggered: int


class DailyBreakdown(BaseModel):
    date: date
    worked_hours: float
    target_hours: float
    break_compliance_pct: int
    focus_rate_pct: float
    checkin_count: int
    avg_stress_level: Optional[float] = None
    avg_energy_level: Optional[float] = None
    patterns_detected: List[str] = []


class WeeklyAggregates(BaseModel):
    avg_worked_hours: float
    avg_break_compliance_pct: int
    avg_focus_rate_pct: float
    total_checkins: int
    avg_stress_level: Optional[float] = None
    avg_energy_level: Optional[float] = None
    avg_workload_manageability: Optional[float] = None
    patterns_detected: List[str] = []
    data_quality: Optional[DataQuality] = None
    # Phase 2: Week-over-week comparison fields
    previous_week_avg_worked_hours: float = 0.0
    previous_week_avg_break_compliance_pct: int = 0
    previous_week_avg_focus_rate_pct: float = 0.0
    previous_week_total_checkins: int = 0
    trend_worked_hours: Optional[TrendDirection] = None
    trend_break_compliance: Optional[TrendDirection] = None
    trend_focus_rate: Optional[TrendDirection] = None
    privacy_suppressed: bool = False


class EmployeeRiskSummary(BaseModel):
    employee_id: uuid.UUID
    employee_name: str
    team_name: str
    risk_tier: RiskTier
    risk_label: str
    primary_concern: str
    evidence_count: int
    top_evidence: List[str]
    trend: TrendDirection
    has_active_shift: bool
    last_checkin_date: Optional[date] = None
    review_status: str = "PENDING"
    action_taken: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    reviewed_by_manager_id: Optional[uuid.UUID] = None
    avg_worked_hours: float = 0.0
    total_checkins: int = 0
    avg_stress_level: Optional[float] = None
    missed_breaks_count: int = 0
    # Phase 2: Week-over-week comparison fields
    previous_week_avg_worked_hours: float = 0.0
    previous_week_avg_break_compliance_pct: int = 0
    previous_week_avg_focus_rate_pct: float = 0.0
    previous_week_total_checkins: int = 0
    trend_direction: Optional[TrendDirection] = None  # per-metric trend direction
    is_first_week_data: bool = False  # no previous week to compare against


class ManagerAlertReviewRequest(BaseModel):
    employee_id: uuid.UUID
    week_start: date
    review_status: str = "REVIEWED"
    action_taken: str
    action_notes: Optional[str] = None


class ManagerAlertReviewResponse(BaseModel):
    id: uuid.UUID
    profile_id: uuid.UUID
    manager_id: uuid.UUID
    week_start: date
    risk_tier: int
    review_status: str
    action_taken: Optional[str] = None
    action_notes: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime


class TeamSummary(BaseModel):
    total_employees: int
    by_tier: dict  # {"insufficient_data": 2, "low": 5, "moderate": 3, "high": 1, "critical": 1} or {"green": 3, "amber": 2, "red": 1, "insufficient_data": 0}
    privacy_suppressed: bool = False


class WeeklyOverviewRequest(BaseModel):
    week_start: Optional[date] = None
    team_id: Optional[uuid.UUID] = None


class MonitoringThresholdsRead(BaseModel):
    id: uuid.UUID
    team_id: Optional[uuid.UUID] = None
    organization_id: Optional[uuid.UUID] = None
    overtime_multiplier_amber: float
    overtime_multiplier_red: float
    break_compliance_amber: int
    break_compliance_red: int
    fatigue_amber: float
    fatigue_red: float
    pattern_count_amber: int
    pattern_count_red: int
    min_employees_for_detail: int
    map_green_to_tier: int
    map_amber_to_tier: int
    map_red_to_tier: int
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MonitoringThresholdsUpdate(BaseModel):
    overtime_multiplier_amber: Optional[float] = None
    overtime_multiplier_red: Optional[float] = None
    break_compliance_amber: Optional[int] = None
    break_compliance_red: Optional[int] = None
    fatigue_amber: Optional[float] = None
    fatigue_red: Optional[float] = None
    pattern_count_amber: Optional[int] = None
    pattern_count_red: Optional[int] = None
    min_employees_for_detail: Optional[int] = None
    map_green_to_tier: Optional[int] = None
    map_amber_to_tier: Optional[int] = None
    map_red_to_tier: Optional[int] = None


class TeamWellnessAdvisorInsight(BaseModel):
    id: str
    category: str
    title: str
    severity: str
    description: str
    evidence: str
    measurement_period: str
    affected_employee_count: int
    trend_comparison: Optional[str] = None
    suggested_manager_action: str
    timestamp: str


class TeamWellnessManagerRecommendation(BaseModel):
    id: str
    priority: str
    action: str
    reason: str
    related_insight_id: str
    status: str


class TeamWellnessAdvisorResponse(BaseModel):
    analysis_period_start: str
    analysis_period_end: str
    team_data_coverage: dict
    overall_assessment: dict
    insights: List[TeamWellnessAdvisorInsight]
    recommendations: List[TeamWellnessManagerRecommendation]
    model_metadata: dict



class WeeklyOverviewResponse(BaseModel):
    week_start: date
    week_end: date
    generated_at: datetime
    team_summary: TeamSummary
    employees: List[EmployeeRiskSummary]


class TeamRiskDistribution(BaseModel):
    """Simplified team risk distribution for dashboard cards."""
    week_start: date
    week_end: date
    total_employees: int
    green_count: int
    amber_count: int
    red_count: int
    insufficient_data_count: int
    privacy_suppressed: bool = False


class EmployeeDetailResponse(BaseModel):
    employee_id: uuid.UUID
    employee_name: str
    week_start: date
    week_end: date
    risk_tier: RiskTier
    risk_label: str
    daily_breakdown: List[DailyBreakdown]
    weekly_aggregates: WeeklyAggregates
    detected_patterns: List[DetectedPattern]
    evidence_items: List[EvidenceItem]
    recommended_actions: List[str]
    data_quality: DataQuality


class HealthResponse(BaseModel):
    status: str
    data_freshness: datetime
    employees_monitored: int
    last_full_computation: datetime
