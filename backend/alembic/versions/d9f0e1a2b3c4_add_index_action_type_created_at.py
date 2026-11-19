"""add_index_action_type_created_at

Revision ID: d9f0e1a2b3c4
Revises: 54801ced6e4f
Create Date: 2026-08-30 06:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd9f0e1a2b3c4'
down_revision: Union[str, Sequence[str], None] = '54801ced6e4f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Create index on action_type and created_at (descending) for audit logs query optimization
    op.create_index(
        'ix_system_activity_logs_action_type_created_at',
        'system_activity_logs',
        ['action_type', sa.text('created_at DESC')]
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_system_activity_logs_action_type_created_at', table_name='system_activity_logs')