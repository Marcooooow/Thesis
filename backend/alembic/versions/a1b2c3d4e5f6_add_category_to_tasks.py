"""Add category to tasks

Revision ID: a1b2c3d4e5f6
Revises: e5f6a7b8c9d0
Create Date: 2026-08-27

Add category column to tasks table to support task categorization.
Existing tasks without a category will receive the default value 'General'.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'e5f6a7b8c9d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add category column to tasks table with default 'General'
    op.add_column('tasks', sa.Column(
        'category',
        sa.String(length=100),
        nullable=True,
        server_default=sa.text("'General'"),
        comment="Task category for organization and filtering (e.g., 'Content Creation', 'Research')"
    ))


def downgrade() -> None:
    # Remove category column from tasks table
    op.drop_column('tasks', 'category')
