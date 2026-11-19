"""Add TOTP 2FA fields and SystemActivityLog table

Revision ID: 7e2c99bf2544
Revises: 5ba09163fbdf
Create Date: 2026-08-17 23:16:38.765992

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '7e2c99bf2544'
down_revision: Union[str, Sequence[str], None] = '5ba09163fbdf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add TOTP 2FA columns to users table
    op.add_column('users', sa.Column('totp_secret', sa.String(length=32), nullable=True, comment='TOTP secret key for two-factor authentication'))
    op.add_column('users', sa.Column('is_2fa_enabled', sa.Boolean(), server_default=sa.text('false'), nullable=False, comment='Flag indicating if two-factor authentication is enabled'))
    op.add_column('users', sa.Column('pending_totp_secret', sa.String(length=32), nullable=True, comment='Temporary TOTP secret during setup process'))
    op.add_column('users', sa.Column('pending_totp_expires_at', sa.DateTime(timezone=True), nullable=True, comment='Expiration for pending TOTP setup'))

    # Create check constraints for role and approval_status if they don't exist
    op.create_check_constraint('check_role_values', 'users', "role IN ('ADMIN', 'MANAGER', 'EMPLOYEE')")
    op.create_check_constraint('check_approval_status_values', 'users', "approval_status IN ('PENDING', 'APPROVED', 'REJECTED')")


def downgrade() -> None:
    """Downgrade schema."""
    # Drop check constraints
    op.drop_constraint('check_approval_status_values', 'users', type_='check')
    op.drop_constraint('check_role_values', 'users', type_='check')

    # Remove TOTP 2FA columns from users table
    op.drop_column('users', 'pending_totp_expires_at')
    op.drop_column('users', 'pending_totp_secret')
    op.drop_column('users', 'is_2fa_enabled')
    op.drop_column('users', 'totp_secret')
