"""add recommendation lifecycle events and tracking fields

Revision ID: 20261117_000004
Revises: 20261117_000003
Create Date: 2026-11-17
"""
from alembic import op
import sqlalchemy as sa

revision = '20261117_000004'
down_revision = '20261117_000003'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('recommendation_feedback', sa.Column('displayed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('recommendation_feedback', sa.Column('lifecycle_status', sa.String(length=50), server_default='generated', nullable=False))
    op.add_column('recommendation_feedback', sa.Column('usefulness_rating', sa.String(length=50), nullable=True))

def downgrade():
    op.drop_column('recommendation_feedback', 'usefulness_rating')
    op.drop_column('recommendation_feedback', 'lifecycle_status')
    op.drop_column('recommendation_feedback', 'displayed_at')
