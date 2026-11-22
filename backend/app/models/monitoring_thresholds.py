"""
Monitoring thresholds configuration model for configurable risk classification.
"""
from sqlalchemy import (
    UUID, String, Integer, Boolean, Date, Time, Text,
    Float, ForeignKey, CheckConstraint, UniqueConstraint, Index,
    text, func
)
from sqlalchemy.sql.sqltypes import DateTime as SADateTime
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
import uuid
from typing import Optional
from datetime import datetime, date

from ..database import Base


class MonitoringThresholds(Base):
    """
    Configurable risk classification thresholds per team or organization.
    Supports Green/Amber/Red (3-tier) classification mapped from 5-tier (0-4).
    """
    __tablename__ = "monitoring_thresholds"

    id: Mapped[uuid.UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        primary_key=True,
        server_default=text("gen_random_uuid()"),
    )
    team_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("teams.id", ondelete="CASCADE"),
        nullable=True,
        comment="Team-specific thresholds (NULL = org-wide or global default)",
    )
    organization_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=True,
        comment="Organization-wide thresholds (used when team_id is NULL)",
    )

    # Work hours thresholds (multipliers of target_daily_hours)
    overtime_multiplier_amber: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=1.1,
        comment="Weekly hours > target * this = Amber",
    )
    overtime_multiplier_red: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=1.3,
        comment="Weekly hours > target * this = Red",
    )

    # Break compliance thresholds (percentage)
    break_compliance_amber: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=80,
        comment="Break compliance < this = Amber",
    )
    break_compliance_red: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=60,
        comment="Break compliance < this = Red",
    )

    # Fatigue/mental health thresholds (1-5 scale from check-ins)
    fatigue_amber: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=2.5,
        comment="Average mental_fatigue > this = Amber",
    )
    fatigue_red: Mapped[float] = mapped_column(
        Float,
        nullable=False,
        default=3.5,
        comment="Average mental_fatigue > this = Red",
    )

    # Behavioral pattern count thresholds
    pattern_count_amber: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=1,
        comment="Number of MEDIUM/HIGH strength patterns for Amber",
    )
    pattern_count_red: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=2,
        comment="Number of MEDIUM/HIGH strength patterns for Red",
    )

    # Privacy: minimum employees for detailed aggregation
    min_employees_for_detail: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=5,
        comment="Minimum employees for non-suppressed team aggregates (minimum privacy floor: 5)",
    )

    # Five-tier compatibility (map 3-tier back to 5-tier for existing consumers)
    map_green_to_tier: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=1,  # RiskTier.LOW
        comment="5-tier value for Green classification",
    )
    map_amber_to_tier: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=2,  # RiskTier.MODERATE
        comment="5-tier value for Amber classification",
    )
    map_red_to_tier: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=4,  # RiskTier.CRITICAL
        comment="5-tier value for Red classification",
    )

    is_active: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
        comment="Whether this threshold config is active",
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        SADateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        SADateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    __table_args__ = (
        # Only one active config per team, one per org
        UniqueConstraint(
            "team_id", "is_active",
            name="uq_monitoring_thresholds_team_active",
            postgresql_where=text("is_active = true AND team_id IS NOT NULL")
        ),
        UniqueConstraint(
            "organization_id", "is_active",
            name="uq_monitoring_thresholds_org_active",
            postgresql_where=text("is_active = true AND organization_id IS NOT NULL AND team_id IS NULL")
        ),
        # Ensure valid threshold ordering
        CheckConstraint(
            "overtime_multiplier_amber < overtime_multiplier_red",
            name="ck_thresholds_overtime_order"
        ),
        CheckConstraint(
            "break_compliance_red < break_compliance_amber",
            name="ck_thresholds_break_compliance_order"
        ),
        CheckConstraint(
            "fatigue_amber < fatigue_red",
            name="ck_thresholds_fatigue_order"
        ),
        CheckConstraint(
            "pattern_count_amber <= pattern_count_red",
            name="ck_thresholds_pattern_order"
        ),
        CheckConstraint(
            "min_employees_for_detail >= 1",
            name="ck_thresholds_min_employees"
        ),
        Index("ix_monitoring_thresholds_team", "team_id"),
        Index("ix_monitoring_thresholds_org", "organization_id"),
    )
