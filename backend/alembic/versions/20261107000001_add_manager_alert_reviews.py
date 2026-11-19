"""add manager alert reviews table

Revision ID: 20261107000001
Revises: 20261107000000
Create Date: 2026-11-07 02:25:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20261107000001'
down_revision = '20261107000000'
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.create_table(
        'manager_alert_reviews',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('profile_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('profiles.id', ondelete='CASCADE'), nullable=False),
        sa.Column('manager_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('week_start', sa.Date(), nullable=False),
        sa.Column('risk_tier', sa.Integer(), nullable=False, default=0),
        sa.Column('review_status', sa.String(50), nullable=False, server_default='PENDING'),
        sa.Column('action_taken', sa.String(100), nullable=True),
        sa.Column('action_notes', sa.Text(), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.UniqueConstraint('profile_id', 'week_start', name='uq_profile_week_review')
    )
    op.create_index('ix_manager_alert_reviews_profile_id', 'manager_alert_reviews', ['profile_id'])
    op.create_index('ix_manager_alert_reviews_week_start', 'manager_alert_reviews', ['week_start'])

def downgrade() -> None:
    op.drop_index('ix_manager_alert_reviews_week_start', table_name='manager_alert_reviews')
    op.drop_index('ix_manager_alert_reviews_profile_id', table_name='manager_alert_reviews')
    op.drop_table('manager_alert_reviews')
