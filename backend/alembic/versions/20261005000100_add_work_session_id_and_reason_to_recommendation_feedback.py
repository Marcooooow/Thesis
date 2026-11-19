"""add work_session_id and reason to recommendation_feedback

Revision ID: 20261005000100
Revises: 7d1bf5980fe6
Create Date: 2026-10-05 00:01:00.00

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '20261005000100'
down_revision = '20260929000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('recommendation_feedback', sa.Column('work_session_id', postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key('fk_recommendation_feedback_work_session', 'recommendation_feedback', 'work_sessions', ['work_session_id'], ['id'], ondelete='SET NULL')
    op.create_index('ix_recommendation_feedback_work_session_id', 'recommendation_feedback', ['work_session_id'], unique=False)
    op.add_column('recommendation_feedback', sa.Column('reason', sa.String(length=255), nullable=True))


def downgrade() -> None:
    op.drop_index('ix_recommendation_feedback_work_session_id', table_name='recommendation_feedback')
    op.drop_constraint('fk_recommendation_feedback_work_session', 'recommendation_feedback', type_='foreignkey')
    op.drop_column('recommendation_feedback', 'work_session_id')
    op.drop_column('recommendation_feedback', 'reason')
