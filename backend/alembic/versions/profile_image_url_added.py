"""Add profile_image_url to profiles table

Revision ID: add_profile_image_url
Revises: f0a1b2c3d4e5_add_is_test_data_to_profiles
Create Date: 2026-09-03 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'add_profile_image_url'
down_revision = 'f0a1b2c3d4e5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add profile_image_url column to profiles table
    op.add_column('profiles', sa.Column('profile_image_url', sa.String(255), nullable=True))


def downgrade() -> None:
    # Remove profile_image_url column from profiles table
    op.drop_column('profiles', 'profile_image_url')