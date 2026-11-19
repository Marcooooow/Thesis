"""add_unique_constraint_feedback_rec_user

Revision ID: 20261110000001
Revises: 20261107000002
Create Date: 2026-11-10 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20261110000001'
down_revision: Union[str, Sequence[str], None] = '20261107000002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # First, backup any duplicate records into a dedicated recovery/audit table before deletion
    op.execute("""
        CREATE TABLE IF NOT EXISTS recommendation_feedback_backup_20261110 AS
        WITH ranked_feedback AS (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY recommendation_id, user_id
                       ORDER BY timestamp ASC, created_at ASC, id ASC
                   ) as rn
            FROM recommendation_feedback
        )
        SELECT * FROM ranked_feedback WHERE rn > 1;
    """)

    # Next, identify duplicates and keep only one per (recommendation_id, user_id)
    # using a deterministic CTE with ROW_NUMBER()
    op.execute("""
        WITH ranked_feedback AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY recommendation_id, user_id
                       ORDER BY timestamp ASC, created_at ASC, id ASC
                   ) as rn
            FROM recommendation_feedback
        )
        DELETE FROM recommendation_feedback
        WHERE id IN (
            SELECT id FROM ranked_feedback WHERE rn > 1
        )
    """)

    # Now add the unique constraint
    op.create_unique_constraint(
        'uq_feedback_rec_user',
        'recommendation_feedback',
        ['recommendation_id', 'user_id']
    )


def downgrade() -> None:
    op.drop_constraint('uq_feedback_rec_user', 'recommendation_feedback', type_='unique')