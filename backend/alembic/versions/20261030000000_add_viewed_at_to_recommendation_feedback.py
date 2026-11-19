"""add_viewed_at_to_recommendation_feedback

Revision ID: 20261030000000
Revises: 20261029000001
Create Date: 2026-10-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20261030000000'
down_revision: Union[str, Sequence[str], None] = '20261029000001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'recommendation_feedback',
        sa.Column('viewed_at', sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('recommendation_feedback', 'viewed_at')
