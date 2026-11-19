"""merge_schema_branches

Revision ID: ae6f10d29598
Revises: add_group_model_20260918, c4d5e6f7g8h9
Create Date: 2026-09-19 18:14:43.508003

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ae6f10d29598'
down_revision: Union[str, Sequence[str], None] = ('add_group_model_20260918', 'c4d5e6f7g8h9')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
