"""
Add ML Training Job tracking and MLModel validation status.
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '20261115_000001'
down_revision = '20261113_000001'
branch_labels = None
depends_on = None

def upgrade():
    # 1. Create MLTrainingJob table
    op.create_table(
        'ml_training_jobs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('dataset', sa.String(50), nullable=False),
        sa.Column('status', sa.String(20), nullable=False),
        sa.Column('requested_by', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('error_message', sa.Text, nullable=True),
        sa.Column('model_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('ml_models.id'), nullable=True),
    )
    op.create_index('ix_ml_training_jobs_status', 'ml_training_jobs', ['status'])
    op.create_index('ix_ml_training_jobs_created_at', 'ml_training_jobs', ['created_at'])

    # 2. Add validation_status to MLModel
    op.add_column('ml_models', sa.Column('validation_status', sa.String(20), server_default='PENDING', nullable=False))

def downgrade():
    op.drop_column('ml_models', 'validation_status')
    op.drop_table('ml_training_jobs')
