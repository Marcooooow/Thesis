"""add server_default to recommendation_feedback.id

Revision ID: 7d1bf5980fe6
Revises: 20260923002000
Create Date: 2026-09-23 14:42:21.403336

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '7d1bf5980fe6'
down_revision: Union[str, Sequence[str], None] = '20260923002000'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.alter_column('recommendation_feedback', 'id',
                    existing_type=postgresql.UUID(as_uuid=True),
                    server_default=sa.text('gen_random_uuid()'),
                    existing_nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('recommendation_feedback', 'id',
                    existing_type=postgresql.UUID(as_uuid=True),
                    server_default=None,
                    existing_nullable=False)
