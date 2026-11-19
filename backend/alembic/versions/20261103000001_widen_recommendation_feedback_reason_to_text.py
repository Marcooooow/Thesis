"""widen recommendation_feedback reason to text

Revision ID: 20261103000001
Revises: 20261103000000
Create Date: 2026-11-03 01:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20261103000001'
down_revision = '20261103000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('recommendation_feedback', 'reason',
               existing_type=sa.String(length=255),
               type_=sa.Text(),
               existing_nullable=True)


def downgrade() -> None:
    op.alter_column('recommendation_feedback', 'reason',
               existing_type=sa.Text(),
               type_=sa.String(length=255),
               existing_nullable=True)
