"""Add user presence tracking

Revision ID: 23defb539bc1
Revises: add_coach_break_20261008
Create Date: 2026-10-11 17:01:28.810366

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '23defb539bc1'
down_revision: Union[str, Sequence[str], None] = '20260930_add_coach_break'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'user_presence',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('is_online', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('last_heartbeat', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()'), onupdate=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()'), onupdate=sa.text('now()')),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id')
    )
    op.create_index('ix_user_presence_user_id', 'user_presence', ['user_id'], unique=False)
    op.create_index('ix_user_presence_heartbeat', 'user_presence', ['last_heartbeat'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_user_presence_heartbeat', table_name='user_presence')
    op.drop_index('ix_user_presence_user_id', table_name='user_presence')
    op.drop_table('user_presence')
