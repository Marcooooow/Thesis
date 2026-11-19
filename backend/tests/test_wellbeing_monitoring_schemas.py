import pytest
from datetime import date, datetime
import uuid
from app.schemas.wellbeing_monitoring import (
    WeeklyOverviewRequest, WeeklyOverviewResponse,
    EmployeeRiskSummary, EmployeeDetailResponse,
    RiskTier, TrendDirection, EvidenceItem,
    EvidenceType, DailyBreakdown, WeeklyAggregates,
    DetectedPattern, DataQuality, TeamSummary, HealthResponse
)


def test_weekly_overview_request_defaults():
    req = WeeklyOverviewRequest()
    assert req.week_start is None
    assert req.team_id is None


def test_weekly_overview_request_explicit():
    req = WeeklyOverviewRequest(week_start=date(2026, 10, 26), team_id=uuid.uuid4())
    assert req.week_start == date(2026, 10, 26)
    assert req.team_id is not None


def test_risk_tier_enum_values():
    assert RiskTier.INSUFFICIENT_DATA == 0
    assert RiskTier.LOW == 1
    assert RiskTier.MODERATE == 2
    assert RiskTier.HIGH == 3
    assert RiskTier.CRITICAL == 4


def test_trend_direction_enum_values():
    assert TrendDirection.IMPROVING == "improving"
    assert TrendDirection.STABLE == "stable"
    assert TrendDirection.WORSENING == "worsening"
    assert TrendDirection.UNKNOWN == "unknown"


def test_evidence_type_enum_values():
    assert EvidenceType.WORKED_HOURS_EXCESS == "worked_hours_excess"
    assert EvidenceType.BREAK_COMPLIANCE_LOW == "break_compliance_low"
    assert EvidenceType.WELLBEING_DECLINING == "wellbeing_declining"
    assert EvidenceType.FOCUS_DECLINING == "focus_declining"
    assert EvidenceType.SKIPPED_BREAKS == "skipped_breaks"


def test_employee_risk_summary_serialization():
    emp_id = uuid.uuid4()
    summary = EmployeeRiskSummary(
        employee_id=emp_id,
        employee_name="Alex Chen",
        team_name="Engineering",
        risk_tier=RiskTier.HIGH,
        risk_label="High Risk",
        primary_concern="Recurring Overwork + Insufficient Recovery",
        evidence_count=3,
        top_evidence=["Worked 11.2h avg/day on 5 of 7 days", "Break compliance 40%"],
        trend=TrendDirection.WORSENING,
        has_active_shift=True,
        last_checkin_date=date(2026, 10, 30)
    )
    data = summary.model_dump()
    assert data["risk_tier"] == 3
    assert data["trend"] == "worsening"
    assert data["employee_id"] == emp_id  # Pydantic v2 keeps UUID as UUID object


def test_evidence_item_structure():
    evidence = EvidenceItem(
        type=EvidenceType.WORKED_HOURS_EXCESS,
        description="Worked 11.2h avg/day (target: 8h) on 5 of 7 days",
        metric_value=11.2,
        threshold=9.6,
        days_affected=5
    )
    assert evidence.type == EvidenceType.WORKED_HOURS_EXCESS
    assert evidence.metric_value == 11.2
    assert evidence.threshold == 9.6
    assert evidence.days_affected == 5


def test_weekly_overview_response_structure():
    emp_id = uuid.uuid4()
    team_id = uuid.uuid4()
    response = WeeklyOverviewResponse(
        week_start=date(2026, 10, 26),
        week_end=date(2026, 11, 1),
        generated_at=datetime(2026, 10, 31, 10, 15, 0),
        team_summary=TeamSummary(
            total_employees=12,
            by_tier={"insufficient_data": 2, "low": 5, "moderate": 3, "high": 1, "critical": 1}
        ),
        employees=[
            EmployeeRiskSummary(
                employee_id=emp_id,
                employee_name="Alex Chen",
                team_name="Engineering",
                risk_tier=RiskTier.HIGH,
                risk_label="High Risk",
                primary_concern="Recurring Overwork + Insufficient Recovery",
                evidence_count=3,
                top_evidence=["Worked 11.2h avg/day on 5 of 7 days", "Break compliance 40%"],
                trend=TrendDirection.WORSENING,
                has_active_shift=True,
                last_checkin_date=date(2026, 10, 30)
            )
        ]
    )
    data = response.model_dump()
    assert data["week_start"] == date(2026, 10, 26)  # Pydantic v2 keeps date objects
    assert data["team_summary"]["total_employees"] == 12
    assert len(data["employees"]) == 1


def test_employee_detail_response_structure():
    emp_id = uuid.uuid4()
    response = EmployeeDetailResponse(
        employee_id=emp_id,
        employee_name="Alex Chen",
        week_start=date(2026, 10, 26),
        week_end=date(2026, 11, 1),
        risk_tier=RiskTier.HIGH,
        risk_label="High Risk",
        daily_breakdown=[
            DailyBreakdown(
                date=date(2026, 10, 26),
                worked_hours=10.5,
                target_hours=8.0,
                break_compliance_pct=50,
                focus_rate_pct=68.0,
                checkin_count=1,
                avg_stress_level=4.0,
                avg_energy_level=2.0,
                patterns_detected=["RECURRING_OVERWORK", "INSUFFICIENT_RECOVERY"]
            )
        ],
        weekly_aggregates=WeeklyAggregates(
            avg_worked_hours=11.2,
            avg_break_compliance_pct=42,
            avg_focus_rate_pct=71.0,
            total_checkins=4,
            avg_stress_level=4.2,
            avg_energy_level=1.8,
            avg_workload_manageability=2.5
        ),
        detected_patterns=[
            DetectedPattern(
                pattern_id="RECURRING_OVERWORK",
                display_name="Recurring Overwork",
                evidence_strength="high",
                measurement="11.2h avg/day vs 8h target (140%)",
                data_limitations=None,
                days_triggered=5
            )
        ],
        evidence_items=[
            EvidenceItem(
                type=EvidenceType.WORKED_HOURS_EXCESS,
                description="Worked 11.2h avg/day (target: 8h) on 5 of 7 days",
                metric_value=11.2,
                threshold=9.6,
                days_affected=5
            )
        ],
        recommended_actions=[
            "Review workload allocation for this employee",
            "Encourage break compliance — consider scheduled break reminders",
            "Schedule 1:1 to discuss workload manageability"
        ],
        data_quality=DataQuality(
            sessions_count=6,
            checkins_count=4,
            baseline_source="personal_30d",
            partial_week=False
        )
    )
    data = response.model_dump()
    assert data["risk_tier"] == 3
    assert len(data["daily_breakdown"]) == 1
    assert len(data["detected_patterns"]) == 1
    assert len(data["evidence_items"]) == 1
    assert len(data["recommended_actions"]) == 3


def test_health_response_structure():
    health = HealthResponse(
        status="operational",
        data_freshness=datetime(2026, 10, 31, 10, 15, 0),
        employees_monitored=12,
        last_full_computation=datetime(2026, 10, 31, 6, 0, 0)
    )
    data = health.model_dump()
    assert data["status"] == "operational"
    assert data["employees_monitored"] == 12


if __name__ == "__main__":
    pytest.main([__file__, "-v"])