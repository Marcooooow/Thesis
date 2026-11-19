"""Add Group model and group_id to team_memberships.

Revision ID: add_group_model_20260918
Revises: merge_heads_20260918
Create Date: 2026-09-18 18:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'add_group_model_20260918'
down_revision: str | None = 'merge_heads_20260918'
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Create groups table and add group_id FK to team_memberships."""
    # Create groups table
    op.create_table(
        'groups',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('team_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(['team_id'], ['teams.id'], ondelete='CASCADE', name='fk_groups_team_id'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('team_id', 'name', name='uq_group_team_name'),
    )
    op.create_index('ix_group_team_id', 'groups', ['team_id'])

    # Add group_id column to team_memberships
    op.add_column(
        'team_memberships',
        sa.Column('group_id', postgresql.UUID(as_uuid=True), nullable=True, comment='Foreign key to groups - optional group assignment within team')
    )
    
    # Add foreign key constraint
    op.create_foreign_key(
        'fk_team_memberships_group_id',
        'team_memberships',
        'groups',
        ['group_id'],
        ['id'],
        ondelete='SET NULL'
    )


def downgrade() -> None:
    """Remove group_id from team_memberships and drop groups table."""
    op.drop_constraint('fk_team_memberships_group_id', 'team_memberships', type_='foreignkey')
    op.drop_column('team_memberships', 'group_id')
    op.drop_index('ix_group_team_id', table_name='groups')
    op.drop_table('groups')
