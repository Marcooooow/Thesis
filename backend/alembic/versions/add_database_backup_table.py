"""Add database backup table

Revision ID: add_database_backup_table
Revises: cf62d38db873_initial_migration_for_intellibreak_
Create Date: 2024-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'add_database_backup_table'
down_revision = 'd5e6f7g8h9i0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create database backup table."""
    # Create a simple backup tracking table
    op.create_table(
        'database_backups',
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('backup_name', sa.String(255), nullable=False),
        sa.Column('backup_path', sa.String(500), nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.text('now()')),
        sa.Column('description', sa.Text, nullable=True),
    )


def downgrade() -> None:
    """Drop database backup table."""
    op.drop_table('database_backups')