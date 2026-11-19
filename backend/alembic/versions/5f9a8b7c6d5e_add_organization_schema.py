"""Add Organization-related schema changes

Revision ID: 5f9a8b7c6d5e
Revises: ae6f10d29598
Create Date: 2026-09-20 12:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '5f9a8b7c6d5e'
down_revision: Union[str, Sequence[str], None] = 'ae6f10d29598'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

def upgrade() -> None:
    # 1. Create organizations
    op.create_table('organizations',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )

    # 2. Create organization_memberships
    op.create_table('organization_memberships',
        sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('organization_id', sa.UUID(), nullable=False),
        sa.Column('role', sa.String(length=20), server_default=sa.text("'EMPLOYEE'"), nullable=False),
        sa.Column('status', sa.String(length=20), server_default=sa.text("'PENDING'"), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'organization_id', name='uq_user_org')
    )
    op.create_index('ix_org_membership_user_id', 'organization_memberships', ['user_id'])
    op.create_index('ix_org_membership_organization_id', 'organization_memberships', ['organization_id'])

    # 3. Add to users
    op.add_column('users', sa.Column('must_change_password', sa.Boolean(), server_default=sa.text('false'), nullable=False))
    op.add_column('users', sa.Column('password_change_token_version', sa.Integer(), server_default=sa.text('0'), nullable=False))

    # 4. Add teams.organization_id (nullable)
    op.add_column('teams', sa.Column('organization_id', sa.UUID(), nullable=True))
    op.create_foreign_key('fk_teams_organization_id', 'teams', 'organizations', ['organization_id'], ['id'])
    op.create_index('ix_teams_organization_id', 'teams', ['organization_id'])

    # 5. Backfill organizations
    op.execute("""
        INSERT INTO organizations (name)
        SELECT DISTINCT organization_name
        FROM users
        WHERE organization_name IS NOT NULL AND organization_name != ''
        ON CONFLICT DO NOTHING;
    """)

    # 6. Backfill organization_memberships
    op.execute("""
        INSERT INTO organization_memberships (user_id, organization_id, role, status)
        SELECT u.id, o.id, u.role, u.approval_status
        FROM users u
        JOIN organizations o ON u.organization_name = o.name
        WHERE u.organization_name IS NOT NULL AND u.organization_name != '';
    """)

    # 7. Backfill remaining team using its manager membership
    op.execute("""
        UPDATE teams t
        SET organization_id = om.organization_id
        FROM organization_memberships om
        WHERE t.manager_user_id = om.user_id
          AND t.id = 'fc60f573-ba16-4e98-9b5a-5bcae3eaa3fb';
    """)

    # 8. Check team mapping where an organization mapping is expected.
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM teams t
                WHERE t.manager_user_id IS NOT NULL
                AND EXISTS (
                    SELECT 1
                    FROM organization_memberships om
                    WHERE om.user_id = t.manager_user_id
                )
                AND t.organization_id IS NULL
            ) THEN
                RAISE EXCEPTION
                    'Backfill failed: Some teams with organization memberships are still unmapped.';
            END IF;
        END $$;
    """)

        # Verification checks
    # Validate consistency without assuming a specific seed dataset.
    op.execute("""
        DO $$
        DECLARE
            duplicate_count INT;
            orphan_membership_count INT;
            unmapped_user_count INT;
        BEGIN
            -- No duplicate user/organization memberships.
            SELECT COUNT(*) INTO duplicate_count
            FROM (
                SELECT user_id, organization_id
                FROM organization_memberships
                GROUP BY user_id, organization_id
                HAVING COUNT(*) > 1
            ) AS duplicates;

            IF duplicate_count > 0 THEN
                RAISE EXCEPTION
                    'Migration verification failed: Duplicate memberships exist';
            END IF;

            -- Every membership must reference an existing organization and user.
            SELECT COUNT(*) INTO orphan_membership_count
            FROM organization_memberships om
            LEFT JOIN users u ON om.user_id = u.id
            LEFT JOIN organizations o ON om.organization_id = o.id
            WHERE u.id IS NULL OR o.id IS NULL;

            IF orphan_membership_count > 0 THEN
                RAISE EXCEPTION
                    'Migration verification failed: Orphan memberships exist';
            END IF;

            -- Every user with an organization name should have a membership.
            SELECT COUNT(*) INTO unmapped_user_count
            FROM users u
            WHERE u.organization_name IS NOT NULL
              AND u.organization_name != ''
              AND NOT EXISTS (
                  SELECT 1
                  FROM organization_memberships om
                  JOIN organizations o
                    ON om.organization_id = o.id
                  WHERE om.user_id = u.id
                    AND o.name = u.organization_name
              );

            IF unmapped_user_count > 0 THEN
                RAISE EXCEPTION
                    'Migration verification failed: Users with organization_name have no matching membership';
            END IF;
        END $$;
    """)

    # 9. Make teams.organization_id NOT NULL
    op.alter_column('teams', 'organization_id', nullable=False)

def downgrade() -> None:
    # Reverse 9 - make nullable
    op.alter_column('teams', 'organization_id', nullable=True)
    # Reverse 4
    op.drop_constraint('fk_teams_organization_id', 'teams', type_='foreignkey')
    op.drop_index('ix_teams_organization_id', 'teams')
    op.drop_column('teams', 'organization_id')
    # Reverse 3
    op.drop_column('users', 'password_change_token_version')
    op.drop_column('users', 'must_change_password')
    # Reverse 2
    op.drop_index('ix_org_membership_organization_id', 'organization_memberships')
    op.drop_index('ix_org_membership_user_id', 'organization_memberships')
    op.drop_table('organization_memberships')
    # Reverse 1
    op.drop_table('organizations')
