"""add user work profiles table for onboarding questionnaire

Revision ID: 20261117_000002
Revises: 20261117_000001
Create Date: 2026-11-17
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '20261117_000002'
down_revision = '20261117_000001'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'user_work_profiles',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('schedule_type', sa.String(length=50), nullable=True),
        sa.Column('typical_start_time', sa.Time(), nullable=True),
        sa.Column('typical_end_time', sa.Time(), nullable=True),
        sa.Column('working_days', postgresql.JSON(astext_type=sa.Text()), nullable=True),
        sa.Column('arrangement', sa.String(length=50), nullable=True),
        sa.Column('typical_focus_duration', sa.Integer(), nullable=True),
        sa.Column('preferred_focus_duration', sa.Integer(), nullable=True),
        sa.Column('typical_break_frequency', sa.Integer(), nullable=True),
        sa.Column('typical_break_duration', sa.Integer(), nullable=True),
        sa.Column('lunch_start_time', sa.Time(), nullable=True),
        sa.Column('lunch_duration', sa.Integer(), nullable=True),
        sa.Column('lunch_consistency', sa.String(length=50), nullable=True),
        sa.Column('responsibilities', postgresql.JSON(astext_type=sa.Text()), nullable=True),
        sa.Column('reminder_preference', sa.String(length=50), nullable=True),
        sa.Column('recommendation_style', sa.String(length=50), nullable=True),
        sa.Column('additional_preferences', sa.Text(), nullable=True),
        sa.Column('profile_completed', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_user_work_profiles_user_id')
    )
    op.create_index('ix_user_work_profile_user_id', 'user_work_profiles', ['user_id'], unique=True)

def downgrade():
    op.drop_index('ix_user_work_profile_user_id', table_name='user_work_profiles')
    op.drop_table('user_work_profiles')
