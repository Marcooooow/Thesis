"""add_coach_break_to_break_type_constraint

Revision ID: add_coach_break_20261008
Revises: 20261005175113
Create Date: 2026-10-08

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20260930_add_coach_break'
down_revision: Union[str, Sequence[str], None] = '20261005175113'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Update the break_type check constraint to include COACH_BREAK
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2', 'COACH_BREAK')"),
    )


def downgrade() -> None:
    # Revert the break_type check constraint to exclude COACH_BREAK
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2')"),
    )