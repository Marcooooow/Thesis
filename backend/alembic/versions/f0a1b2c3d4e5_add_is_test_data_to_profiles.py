"""add is_test_data to profiles

Revision ID: f0a1b2c3d4e5
Revises: d9f0e1a2b3c4
Create Date: 2026-09-01 06:28:00.000000

Add is_test_data flag to profiles table to explicitly mark test/demo accounts.
This prevents test data from being accidentally used as ML training data.
The flag defaults to false for existing profiles, and will be backfilled for
known test accounts based on email patterns.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f0a1b2c3d4e5'
down_revision: Union[str, Sequence[str], None] = 'd9f0e1a2b3c4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add is_test_data column and backfill known test accounts."""
    # Add the column with default false
    op.add_column('profiles',
        sa.Column('is_test_data', sa.Boolean(),
                  server_default=sa.text('false'),
                  nullable=False,
                  comment='Flag indicating if this is a test/demo profile - prevents test data from ML training')
    )

    # Create index for efficient filtering
    op.create_index('ix_profiles_is_test_data', 'profiles', ['is_test_data'], unique=False)

    # Backfill known test/demo accounts based on email patterns
    # Mark profiles whose users have emails containing test/demo/example/guest/fake/mock markers
    op.execute("""
        UPDATE profiles
        SET is_test_data = true
        WHERE user_id IN (
            SELECT id FROM users
            WHERE LOWER(email) LIKE '%demo%'
               OR LOWER(email) LIKE '%test%'
               OR LOWER(email) LIKE '%example%'
               OR LOWER(email) LIKE '%guest%'
               OR LOWER(email) LIKE '%fake%'
               OR LOWER(email) LIKE '%mock%'
        )
    """)


def downgrade() -> None:
    """Remove is_test_data column and index."""
    op.drop_index('ix_profiles_is_test_data', table_name='profiles')
    op.drop_column('profiles', 'is_test_data')
