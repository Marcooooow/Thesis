"""Widen break_type to allow BREAK_1 and BREAK_2

Revision ID: e5f6a7b8c9d0
Revises: 99f0688556d6
Create Date: 2026-08-19

The break workflow requires Break 1, Break 2, and Lunch to be
distinguishable in persisted data. The existing chk_break_type CHECK
constraint only permitted SHORT_BREAK/LUNCH/OTHER, so Break 1 and Break 2
were both stored as SHORT_BREAK and could not be told apart or sequenced.
This widens the constraint to also accept BREAK_1 and BREAK_2. No column
type change is needed (already String(20)); existing SHORT_BREAK/LUNCH/OTHER
rows remain valid.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e5f6a7b8c9d0'
down_revision: Union[str, Sequence[str], None] = '99f0688556d6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER', 'BREAK_1', 'BREAK_2')"),
    )


def downgrade() -> None:
    op.drop_constraint('chk_break_type', 'breaks', type_='check')
    op.create_check_constraint(
        'chk_break_type',
        'breaks',
        sa.text("break_type IN ('SHORT_BREAK', 'LUNCH', 'OTHER')"),
    )
