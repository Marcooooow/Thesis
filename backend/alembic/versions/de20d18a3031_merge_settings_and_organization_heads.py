"""merge settings and organization heads

Revision ID: de20d18a3031
Revises: 5f9a8b7c6d5e, b7c8d9e0f1a2
Create Date: 2026-09-22 18:50:14.503390

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'de20d18a3031'
down_revision: Union[str, Sequence[str], None] = ('5f9a8b7c6d5e', 'b7c8d9e0f1a2')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
