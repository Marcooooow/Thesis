"""add_meal_break_type_constraint

Revision ID: 20261029000000
Revises: 20261022000002
Create Date: 2026-10-29 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text


# revision identifiers, used by Alembic.
revision: str = '20261029000000'
down_revision: Union[str, Sequence[str], None] = '20261022000002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Update the break_type check constraint to include MEAL
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2', 'COACH_BREAK', 'MEAL')"),
    )


def downgrade() -> None:
    # Guarded downgrade: refuse to downgrade if MEAL records exist to prevent silent data loss or constraint violation
    conn = op.get_bind()
    meal_count = conn.execute(text("SELECT count(*) FROM breaks WHERE break_type = 'MEAL'")).scalar()
    if meal_count and meal_count > 0:
        raise RuntimeError(
            f"Cannot downgrade migration: {meal_count} records with break_type = 'MEAL' exist. "
            "Rolling back would violate the CHECK constraint. Manually reclassify or archive MEAL records before downgrading."
        )

    # Revert the break_type check constraint to exclude MEAL
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2', 'COACH_BREAK')"),
    )
