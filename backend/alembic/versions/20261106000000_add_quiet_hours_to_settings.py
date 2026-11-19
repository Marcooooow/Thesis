"""Add quiet hours fields to user_settings table.

Revision ID: 20261106000000
Revises: add_absence_awareness
Create Date: 2026-11-06 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20261106000000'
down_revision = 'add_absence_awareness'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('user_settings', sa.Column('quiet_hours_enabled', sa.Boolean(), server_default=sa.text('false'), nullable=False, comment='Enable/disable quiet hours'))
    op.add_column('user_settings', sa.Column('quiet_hours_start', sa.String(5), nullable=True, comment='Quiet hours start time HH:mm'))
    op.add_column('user_settings', sa.Column('quiet_hours_end', sa.String(5), nullable=True, comment='Quiet hours end time HH:mm'))


def downgrade():
    op.drop_column('user_settings', 'quiet_hours_end')
    op.drop_column('user_settings', 'quiet_hours_start')
    op.drop_column('user_settings', 'quiet_hours_enabled')
