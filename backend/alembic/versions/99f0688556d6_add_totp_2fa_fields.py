"""Add TOTP 2FA fields

Revision ID: 99f0688556d6
Revises: 7e2c99bf2544
Create Date: 2026-08-17 23:49:01.900295

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '99f0688556d6'
down_revision: Union[str, Sequence[str], None] = '7e2c99bf2544'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass  # Columns already added by 7e2c99bf2544; this migration kept for chain continuity


def downgrade() -> None:
    """Downgrade schema."""
    # Remove TOTP 2FA columns from users table
    op.drop_column('users', 'pending_totp_expires_at')
    op.drop_column('users', 'pending_totp_secret')
    op.drop_column('users', 'is_2fa_enabled')
    op.drop_column('users', 'totp_secret')