"""add provenance to recommendation_feedback

Revision ID: 20261103000000
Revises: 20261031000000
Create Date: 2026-11-03 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20261103000000'
down_revision = '20261031000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('recommendation_feedback', sa.Column('provenance', sa.String(length=50), server_default='live', nullable=False))


def downgrade() -> None:
    op.drop_column('recommendation_feedback', 'provenance')
