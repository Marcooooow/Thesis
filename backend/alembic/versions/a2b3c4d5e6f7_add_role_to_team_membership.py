"""Add role column to team_memberships table.

Revision ID: a2b3c4d5e6f7
Revises: add_profile_image_url
Create Date: 2026-09-17 04:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'a2b3c4d5e6f7'
down_revision: str | None = 'add_profile_image_url'
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Upgrade schema - add role column to team_memberships."""
    # Add role column with default value
    op.add_column(
        'team_memberships',
        sa.Column(
            'role',
            sa.String(length=20),
            nullable=False,
            server_default="'EMPLOYEE'",
            comment="Team-specific role: MANAGER or EMPLOYEE"
        )
    )

    # Add check constraint for role values
    op.create_check_constraint(
        'chk_team_membership_role',
        'team_memberships',
        "role IN ('MANAGER', 'EMPLOYEE')"
    )


def downgrade() -> None:
    """Downgrade schema - remove role column from team_memberships."""
    # Remove check constraint
    op.drop_constraint(
        'chk_team_membership_role',
        'team_memberships',
        type_='check'
    )

    # Remove column
    op.drop_column('team_memberships', 'role')
