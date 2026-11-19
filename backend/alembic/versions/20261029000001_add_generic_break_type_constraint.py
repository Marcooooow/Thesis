"""add_generic_break_type_constraint

Revision ID: 20261029000001
Revises: 20261029000000
Create Date: 2026-10-29 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text


# revision identifiers, used by Alembic.
revision: str = '20261029000001'
down_revision: Union[str, Sequence[str], None] = '20261029000000'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Update the break_type check constraint to include BREAK
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2', 'COACH_BREAK', 'MEAL', 'BREAK')"),
    )


def downgrade() -> None:
    conn = op.get_bind()
    break_count = conn.execute(text("SELECT count(*) FROM breaks WHERE break_type = 'BREAK'")).scalar()
    if break_count and break_count > 0:
        raise RuntimeError(
            f"Cannot downgrade migration: {break_count} records with break_type = 'BREAK' exist. "
            "Rolling back would violate the CHECK constraint. Manually reclassify or archive BREAK records before downgrading."
        )

    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2', 'COACH_BREAK', 'MEAL')"),
    )
