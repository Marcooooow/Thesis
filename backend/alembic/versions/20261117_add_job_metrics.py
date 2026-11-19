"""Add extracted_samples, positive_count, negative_count, duration_seconds to ml_training_jobs"""
from alembic import op
import sqlalchemy as sa

revision = '20261117_000001'
down_revision = '20261115_000001'
branch_labels = None
depends_on = None

def upgrade():
    op.add_column('ml_training_jobs', sa.Column('extracted_samples', sa.Integer(), server_default='0', nullable=True))
    op.add_column('ml_training_jobs', sa.Column('positive_count', sa.Integer(), server_default='0', nullable=True))
    op.add_column('ml_training_jobs', sa.Column('negative_count', sa.Integer(), server_default='0', nullable=True))
    op.add_column('ml_training_jobs', sa.Column('duration_seconds', sa.Float(), server_default='0.0', nullable=True))

def downgrade():
    op.drop_column('ml_training_jobs', 'duration_seconds')
    op.drop_column('ml_training_jobs', 'negative_count')
    op.drop_column('ml_training_jobs', 'positive_count')
    op.drop_column('ml_training_jobs', 'extracted_samples')
