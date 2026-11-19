"""alter stress factors to json

Revision ID: 20261107000002
Revises: 20261107000001
Create Date: 2026-11-07 02:30:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '20261107000002'
down_revision = '20261107000001'
branch_labels = None
depends_on = None

def upgrade() -> None:
    op.execute("ALTER TABLE session_wellbeing_checkins ALTER COLUMN stress_factors TYPE JSON USING to_json(stress_factors)")

def downgrade() -> None:
    op.execute("ALTER TABLE session_wellbeing_checkins ALTER COLUMN stress_factors TYPE VARCHAR[] USING ARRAY[stress_factors::text]")
