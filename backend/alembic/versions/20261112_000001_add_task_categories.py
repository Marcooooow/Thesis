"""Add task_categories table and default categories

Revision ID: 20261112_000001
Revises: 20261111_000001
Create Date: 2026-11-12
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = '20261112_000001'
down_revision = '20261111_000001'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        'task_categories',
        sa.Column('id', UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('name', sa.String(length=100), nullable=False, unique=True),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False)
    )
    op.create_index('ix_task_categories_name', 'task_categories', ['name'], unique=True)

    # Seed default categories
    op.execute("""
        INSERT INTO task_categories (name, is_active) VALUES
        ('General', true),
        ('Development', true),
        ('Review', true),
        ('Planning', true),
        ('Meeting', true),
        ('Support', true)
        ON CONFLICT (name) DO NOTHING
    """)

def downgrade():
    op.drop_index('ix_task_categories_name', table_name='task_categories')
    op.drop_table('task_categories')
