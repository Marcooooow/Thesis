"""add ml dashboard tables

Revision ID: 20261022000000
Revises: 20260923002000
Create Date: 2026-10-22 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20261022000000'
down_revision = '23defb539bc1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create ml_experiments table
    op.create_table('ml_experiments',
                    sa.Column('id', sa.UUID(), nullable=False),
                    sa.Column('version', sa.String(length=255), nullable=False),
                    sa.Column('algorithm', sa.String(length=50), nullable=False),
                    sa.Column('metrics', sa.JSON(), nullable=True),
                    sa.Column('dataset_hash', sa.String(length=64), nullable=True),
                    sa.Column('training_date', sa.DateTime(timezone=True),
                              server_default=sa.text('now()'), nullable=False),
                    sa.Column('artifact_path', sa.String(length=255), nullable=True),
                    sa.Column('is_baseline', sa.Boolean(), nullable=False,
                              server_default=sa.text('false')),
                    sa.PrimaryKeyConstraint('id')
                    )
    op.create_index(op.f('ix_ml_experiments_version'), 'ml_experiments',
                    ['version'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_ml_experiments_version'), table_name='ml_experiments')
    op.drop_table('ml_experiments')