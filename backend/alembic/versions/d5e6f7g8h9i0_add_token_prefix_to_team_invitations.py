"""Add token_prefix to team_invitations table for efficient token lookup.

Revision ID: d5e6f7g8h9i0
Revises: b3c4d5e6f7g8
Create Date: 2026-09-17 13:57:50.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'd5e6f7g8h9i0'
down_revision: str | None = 'b3c4d5e6f7g8'
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Upgrade schema - add token_prefix column to team_invitations."""
    # Add token_prefix column with default value for existing rows
    op.add_column(
        'team_invitations',
        sa.Column(
            'token_prefix',
            sa.String(length=12),
            nullable=True,
            comment='First 12 chars of invitation token (non-secret, for efficient lookup)'
        )
    )

    # Set default values for existing rows (use a safe placeholder)
    op.execute("UPDATE team_invitations SET token_prefix = 'legacy' WHERE token_prefix IS NULL")

    # Make the column NOT NULL after setting defaults
    op.alter_column('team_invitations', 'token_prefix', nullable=False)

    # Create index on token_prefix for efficient lookups
    op.create_index(
        'ix_team_invitation_token_prefix',
        'team_invitations',
        ['token_prefix']
    )


def downgrade() -> None:
    """Downgrade schema - remove token_prefix column from team_invitations."""
    op.drop_index('ix_team_invitation_token_prefix', table_name='team_invitations')
    op.drop_column('team_invitations', 'token_prefix')
