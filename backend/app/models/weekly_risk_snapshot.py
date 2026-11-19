"""
Weekly risk snapshot model for trend analysis and historical comparison.
"""
from sqlalchemy import (
    UUID, String, Integer, Boolean, Date, Time, Text,
    Float, ForeignKey, CheckConstraint, UniqueConstraint, Index,
    text, func, JSON
)
from sqlalchemy.sql.sqltypes import DateTime as SADateTime
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from typing import Optional
from datetime import datetime, date
import uuid

from ..database import Base


class WeeklyRiskSnapshot(Base):
    """
    Persisted weekly risk assessment for trend analysis.
    Stores computed metrics for each employee per week.
    """
    __tablename__ = "weekly_risk_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    profile_id: Mapped[uuid.UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("profiles.id", ondelete="CASCADE"),
        nullable=False,
        comment="Employee profile",
    )
    week_start: Mapped[date] = mapped_column(
        Date,
        nullable=False,
        comment="Monday of the reporting week",
    )

    # Risk classification
    risk_tier_3tier: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
        comment="GREEN, AMBER, or RED",
    )
    risk_tier_5tier: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        comment="Mapped 5-tier value (0-4) for compatibility",
    )

    # Weekly aggregates (stored as JSONB for flexibility)
    weekly_aggregates: Mapped[dict] = mapped_column(
        JSON,
        nullable=False,
        default=dict,
        comment="avg_worked_hours, avg_break_compliance_pct, avg_focus_rate_pct, total_checkins, avg_stress_level, avg_energy_level, overtime_hours, extended_sessions_count, missed_breaks_proxy",
    )

    # Evidence items that triggered the risk tier
    evidence_items: Mapped[list] = mapped_column(
        JSON,
        nullable=False,
        default=list,
        comment="Array of evidence items: type, description, metric_value, threshold, days_affected",
    )

    # Detected behavioral patterns
    detected_patterns: Mapped[list] = mapped_column(
        JSON,
        nullable=False,
        default=list,
        comment="Array of patterns: pattern_id, display_name, evidence_strength, measurement, days_triggered",
    )

    # Data quality indicators
    data_quality: Mapped[dict] = mapped_column(
        JSON,
        nullable=False,
        default=dict,
        comment="sessions_count, checkins_count, baseline_source, partial_week, data_limitation",
    )

    # Privacy flag
    privacy_suppressed: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        comment="True if team had < min_employees_for_detail and this was suppressed",
    )

    created_at: Mapped[datetime] = mapped_column(
        SADateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    __table_args__ = (
        UniqueConstraint(
            "profile_id", "week_start",
            name="uq_weekly_risk_snapshot_profile_week"
        ),
        Index("ix_weekly_risk_snapshot_profile", "profile_id"),
        Index("ix_weekly_risk_snapshot_week", "week_start"),
        Index("ix_weekly_risk_snapshot_tier", "risk_tier_3tier"),
        Index("ix_weekly_risk_snapshot_profile_week_desc", "profile_id", "week_start", postgresql_ops={"week_start": "DESC"}),
    )