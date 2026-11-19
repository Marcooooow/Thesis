"""add_account_type_and_organization_to_users

Revision ID: 54801ced6e4f
Revises: a1b2c3d4e5f6
Create Date: 2026-08-30 05:43:37.606191

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '54801ced6e4f'
down_revision: Union[str, Sequence[str], None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add account_type column to users table
    op.add_column('users', sa.Column('account_type', sa.String(length=20), nullable=False, server_default='solo'))
    # Add organization_name column to users table
    op.add_column('users', sa.Column('organization_name', sa.String(length=255), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    # Drop organization_name column
    op.drop_column('users', 'organization_name')
    # Drop account_type column
    op.drop_column('users', 'account_type')
