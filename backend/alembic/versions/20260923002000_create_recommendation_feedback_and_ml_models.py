"""create recommendation_feedback and ml_models tables

Revision ID: 20260923002000
Revises: de20d18a3031
Create Date: 2026-09-23 00:20:00.00

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20260923002000'
down_revision = 'de20d18a3031'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create recommendation_feedback table
    op.create_table(
        'recommendation_feedback',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('recommendation_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('model_version', sa.String(length=255), nullable=False),
        sa.Column('recommendation_type', sa.String(length=50), nullable=False),
        sa.Column('recommendation_score', sa.Float(), nullable=False),
        sa.Column('context_features', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('timestamp', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('user_action', sa.String(length=20), nullable=True),
        sa.Column('break_started_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('break_ended_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('break_type', sa.String(length=20), nullable=True),
        sa.Column('break_duration', sa.Integer(), nullable=True),
        sa.Column('post_break_productivity_delta', sa.Float(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE')
    )
    op.create_index('ix_recommendation_feedback_user_id', 'recommendation_feedback', ['user_id'], unique=False)
    op.create_index('ix_recommendation_feedback_timestamp', 'recommendation_feedback', ['timestamp'], unique=False)
    op.create_index('ix_recommendation_feedback_recommendation_id', 'recommendation_feedback', ['recommendation_id'], unique=False)

    # Create ml_models table
    op.create_table(
        'ml_models',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('version', sa.String(length=255), nullable=False),
        sa.Column('artifact_path', sa.String(length=255), nullable=False),
        sa.Column('training_date', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('feature_set_version', sa.String(length=255), nullable=False),
        sa.Column('metrics', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('false'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_ml_models_version', 'ml_models', ['version'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_ml_models_version', table_name='ml_models')
    op.drop_table('ml_models')
    op.drop_index('ix_recommendation_feedback_recommendation_id', table_name='recommendation_feedback')
    op.drop_index('ix_recommendation_feedback_timestamp', table_name='recommendation_feedback')
    op.drop_index('ix_recommendation_feedback_user_id', table_name='recommendation_feedback')
    op.drop_table('recommendation_feedback')