"""Merge parallel branches: notifications and token_prefix.

Revision ID: merge_heads_20260918
Revises: add_database_backup_table, d5e6f7g8h9i0
Create Date: 2026-09-18 17:59:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'merge_heads_20260918'
down_revision: str | tuple[str, ...] = ('add_database_backup_table',)
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """No schema changes - this is a merge point."""
    pass


def downgrade() -> None:
    """No schema changes to downgrade."""
    pass
