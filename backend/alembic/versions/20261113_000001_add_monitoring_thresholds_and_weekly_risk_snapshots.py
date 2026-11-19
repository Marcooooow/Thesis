"""add monitoring thresholds and weekly risk snapshots tables

Revision ID: 20261113_000001
Revises: 20261112_000001
Create Date: 2026-11-13
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '20261113_000001'
down_revision = '20261112_000001'
branch_labels = None
depends_on = None

def upgrade() -> None:
    # 1. monitoring_thresholds
    op.create_table(
        'monitoring_thresholds',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('team_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('teams.id', ondelete='CASCADE'), nullable=True),
        sa.Column('organization_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('organizations.id', ondelete='CASCADE'), nullable=True),
        sa.Column('overtime_multiplier_amber', sa.Float(), nullable=False, server_default='1.1'),
        sa.Column('overtime_multiplier_red', sa.Float(), nullable=False, server_default='1.3'),
        sa.Column('break_compliance_amber', sa.Integer(), nullable=False, server_default='80'),
        sa.Column('break_compliance_red', sa.Integer(), nullable=False, server_default='60'),
        sa.Column('fatigue_amber', sa.Float(), nullable=False, server_default='2.5'),
        sa.Column('fatigue_red', sa.Float(), nullable=False, server_default='3.5'),
        sa.Column('pattern_count_amber', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('pattern_count_red', sa.Integer(), nullable=False, server_default='2'),
        sa.Column('min_employees_for_detail', sa.Integer(), nullable=False, server_default='3'),
        sa.Column('map_green_to_tier', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('map_amber_to_tier', sa.Integer(), nullable=False, server_default='2'),
        sa.Column('map_red_to_tier', sa.Integer(), nullable=False, server_default='4'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_by', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint('overtime_multiplier_amber < overtime_multiplier_red', name='ck_thresholds_overtime_order'),
        sa.CheckConstraint('break_compliance_red < break_compliance_amber', name='ck_thresholds_break_compliance_order'),
        sa.CheckConstraint('fatigue_amber < fatigue_red', name='ck_thresholds_fatigue_order'),
        sa.CheckConstraint('pattern_count_amber <= pattern_count_red', name='ck_thresholds_pattern_order'),
        sa.CheckConstraint('min_employees_for_detail >= 1', name='ck_thresholds_min_employees')
    )
    op.create_index('ix_monitoring_thresholds_team', 'monitoring_thresholds', ['team_id'])
    op.create_index('ix_monitoring_thresholds_org', 'monitoring_thresholds', ['organization_id'])

    # Unique partial indexes / constraints for active thresholds
    op.create_index(
        'uq_monitoring_thresholds_team_active_idx',
        'monitoring_thresholds',
        ['team_id'],
        unique=True,
        postgresql_where=sa.text('is_active = true AND team_id IS NOT NULL')
    )
    op.create_index(
        'uq_monitoring_thresholds_org_active_idx',
        'monitoring_thresholds',
        ['organization_id'],
        unique=True,
        postgresql_where=sa.text('is_active = true AND organization_id IS NOT NULL AND team_id IS NULL')
    )

    # 2. weekly_risk_snapshots
    op.create_table(
        'weekly_risk_snapshots',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('profile_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('week_start', sa.Date(), nullable=False),
        sa.Column('risk_tier_3tier', sa.String(10), nullable=False),
        sa.Column('risk_tier_5tier', sa.Integer(), nullable=False),
        sa.Column('weekly_aggregates', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('evidence_items', postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('detected_patterns', postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('data_quality', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('privacy_suppressed', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('profile_id', 'week_start', name='uq_weekly_risk_snapshot_profile_week')
    )
    op.create_index('ix_weekly_risk_snapshot_profile', 'weekly_risk_snapshots', ['profile_id'])
    op.create_index('ix_weekly_risk_snapshot_week', 'weekly_risk_snapshots', ['week_start'])
    op.create_index('ix_weekly_risk_snapshot_tier', 'weekly_risk_snapshots', ['risk_tier_3tier'])
    op.create_index(
        'ix_weekly_risk_snapshot_profile_week_desc',
        'weekly_risk_snapshots',
        ['profile_id', sa.text('week_start DESC')]
    )

def downgrade() -> None:
    op.drop_index('ix_weekly_risk_snapshot_profile_week_desc', table_name='weekly_risk_snapshots')
    op.drop_index('ix_weekly_risk_snapshot_tier', table_name='weekly_risk_snapshots')
    op.drop_index('ix_weekly_risk_snapshot_week', table_name='weekly_risk_snapshots')
    op.drop_index('ix_weekly_risk_snapshot_profile', table_name='weekly_risk_snapshots')
    op.drop_table('weekly_risk_snapshots')

    op.drop_index('uq_monitoring_thresholds_org_active_idx', table_name='monitoring_thresholds')
    op.drop_index('uq_monitoring_thresholds_team_active_idx', table_name='monitoring_thresholds')
    op.drop_index('ix_monitoring_thresholds_org', table_name='monitoring_thresholds')
    op.drop_index('ix_monitoring_thresholds_team', table_name='monitoring_thresholds')
    op.drop_table('monitoring_thresholds')
