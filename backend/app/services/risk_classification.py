"""
Risk classification service with configurable thresholds.
Maps 3-tier (Green/Amber/Red) classification to 5-tier (0-4) for compatibility.
"""

from dataclasses import dataclass
from typing import Optional
from datetime import date
import uuid
from sqlalchemy.orm import Session

from ..models import MonitoringThresholds, Profile, TeamMembership, Team


@dataclass
class Thresholds:
    """Runtime threshold configuration for risk classification."""
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


DEFAULT_THRESHOLDS = Thresholds(
    overtime_multiplier_amber=1.1,
    overtime_multiplier_red=1.3,
    break_compliance_amber=80,
    break_compliance_red=60,
    fatigue_amber=2.5,
    fatigue_red=3.5,
    pattern_count_amber=1,
    pattern_count_red=2,
    min_employees_for_detail=3,
    map_green_to_tier=1,  # RiskTier.LOW
    map_amber_to_tier=2,  # RiskTier.MODERATE
    map_red_to_tier=4,    # RiskTier.CRITICAL
)


def get_default_thresholds() -> Thresholds:
    """Return the default threshold configuration."""
    return DEFAULT_THRESHOLDS


def get_thresholds_for_team(
    db: Session,
    team_id: uuid.UUID,
    organization_id: Optional[uuid.UUID] = None
) -> Thresholds:
    """
    Resolve monitoring thresholds for a team.
    Priority: team-specific > organization-wide > defaults.
    """
    # Try team-specific active thresholds
    team_thresholds = db.query(MonitoringThresholds).filter(
        MonitoringThresholds.team_id == team_id,
        MonitoringThresholds.is_active == True
    ).first()

    if team_thresholds:
        return _model_to_thresholds(team_thresholds)

    # Try organization-wide active thresholds
    if organization_id:
        org_thresholds = db.query(MonitoringThresholds).filter(
            MonitoringThresholds.organization_id == organization_id,
            MonitoringThresholds.team_id.is_(None),
            MonitoringThresholds.is_active == True
        ).first()

        if org_thresholds:
            return _model_to_thresholds(org_thresholds)

    return DEFAULT_THRESHOLDS


def _model_to_thresholds(model: MonitoringThresholds) -> Thresholds:
    """Convert MonitoringThresholds model to runtime Thresholds dataclass."""
    return Thresholds(
        overtime_multiplier_amber=model.overtime_multiplier_amber,
        overtime_multiplier_red=model.overtime_multiplier_red,
        break_compliance_amber=model.break_compliance_amber,
        break_compliance_red=model.break_compliance_red,
        fatigue_amber=model.fatigue_amber,
        fatigue_red=model.fatigue_red,
        pattern_count_amber=model.pattern_count_amber,
        pattern_count_red=model.pattern_count_red,
        min_employees_for_detail=model.min_employees_for_detail,
        map_green_to_tier=model.map_green_to_tier,
        map_amber_to_tier=model.map_amber_to_tier,
        map_red_to_tier=model.map_red_to_tier,
    )


def classify_risk_from_aggregates(
    weekly_aggregates: dict,
    evidence_items: list,
    detected_patterns: list,
    thresholds: Thresholds
) -> tuple[str, int]:
    """
    Classify risk tier from weekly aggregates and evidence.
    Returns (3tier_label, 5tier_value).

    3-tier: GREEN, AMBER, RED
    5-tier: 0-4 (INSUFFICIENT_DATA, LOW, MODERATE, HIGH, CRITICAL)
    """
    # Check if data quality indicates insufficient data
    data_quality = weekly_aggregates.get("data_quality") or {}
    if data_quality.get("data_limitation") == "insufficient_sessions_or_checkins":
        return "INSUFFICIENT_DATA", 0

    # Extract key metrics
    avg_worked_hours = weekly_aggregates.get("avg_worked_hours", 0)
    avg_break_compliance = weekly_aggregates.get("avg_break_compliance_pct", 100)
    avg_fatigue = weekly_aggregates.get("avg_stress_level")  # mental_fatigue avg

    # Count patterns with medium/high strength
    def is_detected(pattern: dict) -> bool:
        # Legacy records without a detected flag are not enough to establish a signal.
        return pattern.get("detected", False) is True

    medium_high_patterns = sum(
        1 for p in detected_patterns
        if is_detected(p) and str(p.get("evidence_strength", "low")).lower() in ("medium", "high")
    )

    # Check for critical patterns
    has_overwork = any(is_detected(p) and p.get("pattern_id") == "RECURRING_OVERWORK" for p in detected_patterns)
    has_skipped_breaks = any(is_detected(p) and p.get("pattern_id") == "REPEATED_SKIPPED_BREAKS" for p in detected_patterns)
    has_fatigue_stress = any(is_detected(p) and p.get("pattern_id") == "RECURRING_FATIGUE_STRESS" for p in detected_patterns)

    # RED classification
    is_red = (
        (avg_worked_hours > 0 and avg_worked_hours > thresholds.overtime_multiplier_red * 40) or  # weekly > 1.3x target
        (avg_break_compliance < thresholds.break_compliance_red) or
        (avg_fatigue and avg_fatigue > thresholds.fatigue_red) or
        (medium_high_patterns >= thresholds.pattern_count_red) or
        (has_overwork and has_fatigue_stress)  # Combined critical signal
    )

    if is_red:
        return "RED", thresholds.map_red_to_tier

    # AMBER classification
    is_amber = (
        (avg_worked_hours > 0 and avg_worked_hours > thresholds.overtime_multiplier_amber * 40) or  # weekly > 1.1x target
        (avg_break_compliance < thresholds.break_compliance_amber) or
        (avg_fatigue and avg_fatigue > thresholds.fatigue_amber) or
        (medium_high_patterns >= thresholds.pattern_count_amber) or
        has_overwork or
        has_skipped_breaks or
        has_fatigue_stress
    )

    if is_amber:
        return "AMBER", thresholds.map_amber_to_tier

    # GREEN
    return "GREEN", thresholds.map_green_to_tier


def should_suppress_detail(
    eligible_employee_count: int,
    thresholds: Thresholds
) -> bool:
    """
    Determine if team detail should be suppressed based on employee count.
    Returns True if suppression should apply.
    """
    return eligible_employee_count < thresholds.min_employees_for_detail
