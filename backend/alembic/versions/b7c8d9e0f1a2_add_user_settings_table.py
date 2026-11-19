"""Add user_settings table for persistent application preferences

Revision ID: b7c8d9e0f1a2
Revises: merge_heads_20260918
Create Date: 2026-09-22 06:13:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b7c8d9e0f1a2'
down_revision: Union[str, Sequence[str], None] = 'merge_heads_20260918'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create user_settings table
    op.create_table('user_settings',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),

        # Notification preferences
        sa.Column('notifications_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('break_reminders', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('shift_reminders', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('task_reminders', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('focus_reminders', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('wellness_reminders', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('daily_summary', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('weekly_summary', sa.Boolean(), server_default=sa.text('false'), nullable=False),

        # Break and interval preferences
        sa.Column('break_interval_minutes', sa.Integer(), server_default=sa.text('30'), nullable=False),
        sa.Column('break_duration_minutes', sa.Integer(), server_default=sa.text('10'), nullable=False),

        # Break Coach preferences
        sa.Column('break_coach_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('break_coach_cooldown_minutes', sa.Integer(), server_default=sa.text('30'), nullable=False),

        # Work and productivity preferences
        sa.Column('work_target_daily_hours', sa.Integer(), nullable=True),
        sa.Column('default_work_schedule', sa.String(length=50), nullable=True),
        sa.Column('focus_target_percentage', sa.Integer(), nullable=True),
        sa.Column('idle_detection_sensitivity', sa.String(length=20), nullable=True),

        # Timezone and regional preferences
        sa.Column('timezone', sa.String(length=50), nullable=True),
        sa.Column('date_format', sa.String(length=20), nullable=True),
        sa.Column('time_format', sa.String(length=10), nullable=True),
        sa.Column('first_day_of_week', sa.String(length=10), nullable=True),

        # Accessibility preferences
        sa.Column('reduce_motion', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.Column('interface_density', sa.String(length=20), nullable=True),

        # Audit timestamps
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),

        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_user_settings_user_id'),

        # Check constraints
        sa.CheckConstraint("break_interval_minutes IN (15, 30, 45, 60, 90, 120)", name='chk_user_settings_break_interval'),
        sa.CheckConstraint("break_duration_minutes IN (5, 10, 15, 20, 30)", name='chk_user_settings_break_duration'),
        sa.CheckConstraint("break_coach_cooldown_minutes >= 5 AND break_coach_cooldown_minutes <= 60", name='chk_user_settings_cooldown_range'),
        sa.CheckConstraint("work_target_daily_hours IS NULL OR (work_target_daily_hours >= 1 AND work_target_daily_hours <= 24)", name='chk_user_settings_daily_hours_range'),
        sa.CheckConstraint("focus_target_percentage IS NULL OR (focus_target_percentage >= 0 AND focus_target_percentage <= 100)", name='chk_user_settings_focus_percentage_range'),
        sa.CheckConstraint("idle_detection_sensitivity IS NULL OR idle_detection_sensitivity IN ('LOW', 'MEDIUM', 'HIGH')", name='chk_user_settings_idle_sensitivity'),
        sa.CheckConstraint("time_format IS NULL OR time_format IN ('12h', '24h')", name='chk_user_settings_time_format'),
        sa.CheckConstraint("interface_density IS NULL OR interface_density IN ('COMPACT', 'COMFORTABLE', 'SPACIOUS')", name='chk_user_settings_density'),
    )

    # Create indexes
    op.create_index('ix_user_settings_user_id', 'user_settings', ['user_id'], unique=True)


def downgrade() -> None:
    # Drop indexes
    op.drop_index('ix_user_settings_user_id', table_name='user_settings')

    # Drop table
    op.drop_table('user_settings')
