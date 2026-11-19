"""Add DND override and notification governance fields.

Revision ID: 20261104_dnd_gov
Revises: add_direct_conversation_unique
Create Date: 2026-11-04 18:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20261104_dnd_gov'
down_revision = 'add_direct_conversation_unique'
branch_labels = None
depends_on = None


def upgrade():
    # 1. Add manual_dnd_override to user_settings if not exists
    op.add_column('user_settings', sa.Column('manual_dnd_override', sa.Boolean(), nullable=True, comment='Manual DND override: NULL=follow auto, TRUE=force on, FALSE=force off'))

    # 2. Add governance columns to notifications
    op.add_column('notifications', sa.Column('priority', sa.String(20), server_default='STANDARD', nullable=False, comment='Notification priority: CRITICAL, STANDARD, LOW'))
    op.add_column('notifications', sa.Column('delivery_status', sa.String(20), server_default='AVAILABLE', nullable=False, comment='Delivery status: AVAILABLE, SUPPRESSED_DND'))
    op.add_column('notifications', sa.Column('idempotency_key', sa.String(255), nullable=True, comment='Idempotency key for preventing duplicate dispatches'))

    # 3. Update notification type check constraint safely
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type")
    op.create_check_constraint(
        'chk_notification_type',
        'notifications',
        "type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED', 'WORK_REMINDER', 'BREAK_COACH', 'SYSTEM_ALERT', 'TASK_NOTIFICATION')"
    )

    # 4. Add priority and delivery status check constraints
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_priority")
    op.create_check_constraint(
        'chk_notification_priority',
        'notifications',
        "priority IN ('CRITICAL', 'STANDARD', 'LOW')"
    )

    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_delivery_status")
    op.create_check_constraint(
        'chk_notification_delivery_status',
        'notifications',
        "delivery_status IN ('AVAILABLE', 'SUPPRESSED_DND')"
    )

    # 5. Add unique index for recipient-scoped idempotency
    try:
        op.create_index(
            'uq_recipient_idempotency',
            'notifications',
            ['recipient_user_id', 'idempotency_key'],
            unique=True,
            postgresql_where=sa.text("idempotency_key IS NOT NULL")
        )
    except Exception:
        pass


def downgrade():
    op.execute("DROP INDEX IF EXISTS uq_recipient_idempotency")
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_delivery_status")
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_priority")
    op.execute("ALTER TABLE notifications DROP CONSTRAINT IF EXISTS chk_notification_type")
    op.create_check_constraint(
        'chk_notification_type',
        'notifications',
        "type IN ('TEAM_INVITATION', 'TEAM_INVITATION_ACCEPTED', 'TEAM_INVITATION_DECLINED')"
    )

    op.drop_column('notifications', 'idempotency_key')
    op.drop_column('notifications', 'delivery_status')
    op.drop_column('notifications', 'priority')
    op.drop_column('user_settings', 'manual_dnd_override')
