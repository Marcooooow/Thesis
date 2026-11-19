"""create import_manifests table for resumable dataset import

Revision ID: 20261118_import_manifests
Revises: 20261117_000004
Create Date: 2026-11-18 12:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

revision = '20261118_import_manifests'
down_revision = '20261117_000004'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'import_manifests',
        sa.Column('import_run_id', sa.String(length=36), primary_key=True, nullable=False),
        sa.Column('dataset_hash', sa.String(length=64), nullable=False),
        sa.Column('entity_name', sa.String(length=100), primary_key=True, nullable=False),
        sa.Column('status', sa.String(length=20), server_default='pending', nullable=False),
        sa.Column('records_processed', sa.Integer(), server_default='0', nullable=False),
        sa.Column('records_inserted', sa.Integer(), server_default='0', nullable=False),
        sa.Column('records_skipped', sa.Integer(), server_default='0', nullable=False),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('error_details', sa.Text(), nullable=True),
        sa.Column('runner_id', sa.String(length=36), nullable=True),
        sa.Column('heartbeat_at', sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('pending', 'running', 'completed', 'failed')",
            name='chk_import_manifests_status'
        )
    )

def downgrade():
    op.drop_table('import_manifests')
