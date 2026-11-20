"""allow solo accounts to submit work-life balance surveys

Solo (non-organization) accounts have no organization membership, so the
survey's organization_id must be nullable.

Revision ID: 20261120000000
Revises: 20261118_import_manifests
Create Date: 2026-11-20 00:00:00.000000

"""
from alembic import op

# revision identifiers, used by Alembic.
revision = '20261120000000'
down_revision = '20261118_import_manifests'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('work_life_balance_surveys', 'organization_id', nullable=True)


def downgrade() -> None:
    # Rows submitted by solo accounts have no organization; drop them first.
    op.execute("DELETE FROM work_life_balance_surveys WHERE organization_id IS NULL")
    op.alter_column('work_life_balance_surveys', 'organization_id', nullable=False)
