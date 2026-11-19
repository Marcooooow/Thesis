"""Expand notification delivery status and notification type check constraints.

Revision ID: 20261107000000
Revises: 20261106000000
Create Date: 2026-11-07 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20261107000000'
down_revision = '20261106000000'
branch_labels = None
depends_on = None


def upgrade():
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_delivery_status")
    op.create_check_constraint(
        'chk_notification_delivery_status',
        'notifications',
        "delivery_status IN ('AVAILABLE', 'SUPPRESSED_DND', 'SUPPRESSED_DISABLED', 'SUPPRESSED_PREFERENCE', 'SUPPRESSED_QUIET_HOURS')"
    )

    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type")
    op.create_check_constraint(
        'chk_notification_type',
        'notifications',
        "type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED', 'WORK_REMINDER', 'BREAK_COACH', 'SYSTEM_ALERT', 'TASK_NOTIFICATION', 'TASK_REMINDER', 'SHIFT_REMINDER', 'FOCUS_REMINDER', 'WELLNESS_REMINDER', 'DAILY_SUMMARY', 'WEEKLY_SUMMARY', 'ABSENCE_ALERT', 'LEAVE_REQUEST', 'LEAVE_APPROVED', 'LEAVE_REJECTED', 'RTW_CHECKIN_PROMPT', 'BREAK_REMINDER')"
    )


def downgrade():
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_delivery_status")
    op.create_check_constraint(
        'chk_notification_delivery_status',
        'notifications',
        "delivery_status IN ('AVAILABLE', 'SUPPRESSED_DND')"
    )

    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type")
    op.create_check_constraint(
        'chk_notification_type',
        'notifications',
        "type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED', 'WORK_REMINDER', 'BREAK_COACH', 'SYSTEM_ALERT', 'TASK_NOTIFICATION', 'ABSENCE_ALERT', 'LEAVE_REQUEST', 'LEAVE_APPROVED', 'LEAVE_REJECTED', 'RTW_CHECKIN_PROMPT', 'BREAK_REMINDER')"
    )
