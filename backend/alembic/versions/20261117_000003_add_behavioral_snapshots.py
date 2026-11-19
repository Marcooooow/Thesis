"""add behavioral snapshots table for versioned behavioral observation

Revision ID: 20261117_000003
Revises: 20261117_000002
Create Date: 2026-11-17
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '20261117_000003'
down_revision = '20261117_000002'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'behavioral_snapshots',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('profile_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('snapshot_date', sa.Date(), nullable=False),
        sa.Column('window_start', sa.DateTime(timezone=True), nullable=False),
        sa.Column('window_end', sa.DateTime(timezone=True), nullable=False),
        sa.Column('observation_window_days', sa.Integer(), server_default='30', nullable=False),
        sa.Column('self_reported_context', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
        sa.Column('observed_baselines', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
        sa.Column('pattern_detections', postgresql.JSONB(astext_type=sa.Text()), server_default='{}', nullable=False),
        sa.Column('provenance', sa.String(length=50), server_default='derived_snapshot', nullable=False),
        sa.Column('schema_version', sa.String(length=50), server_default='v2_behavioral_snapshot_20261117', nullable=False),
        sa.Column('aggregation_version', sa.String(length=50), server_default='v2_median_robust', nullable=False),
        sa.Column('source_event_watermark', sa.DateTime(timezone=True), nullable=True),
        sa.Column('sample_count', sa.Integer(), server_default='0', nullable=False),
        sa.Column('data_quality', sa.Float(), server_default='1.0', nullable=False),
        sa.Column('generated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['profile_id'], ['profiles.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'snapshot_date', 'observation_window_days', 'schema_version', name='uq_behavioral_snapshot_idempotency')
    )
    op.create_index('ix_behavioral_snapshots_user', 'behavioral_snapshots', ['user_id'], unique=False)
    op.create_index('ix_behavioral_snapshots_date', 'behavioral_snapshots', ['snapshot_date'], unique=False)
    op.create_index('ix_behavioral_snapshots_window', 'behavioral_snapshots', ['observation_window_days'], unique=False)

def downgrade():
    op.drop_index('ix_behavioral_snapshots_window', table_name='behavioral_snapshots')
    op.drop_index('ix_behavioral_snapshots_date', table_name='behavioral_snapshots')
    op.drop_index('ix_behavioral_snapshots_user', table_name='behavioral_snapshots')
    op.drop_table('behavioral_snapshots')
