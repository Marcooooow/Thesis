"""
Add composite indexes for wellbeing monitoring performance.
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20261031000000'
down_revision = '20261030000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Composite index on work_sessions for profile_id + started_at window queries
    op.create_index(
        'idx_work_sessions_profile_started',
        'work_sessions',
        ['profile_id', 'started_at'],
        unique=False
    )

    # Composite index on breaks for work_session_id + started_at window queries
    op.create_index(
        'idx_breaks_session_started',
        'breaks',
        ['work_session_id', 'started_at'],
        unique=False
    )

    # Composite index on session_wellbeing_checkins for work_session_id + created_at
    op.create_index(
        'idx_checkins_session_created',
        'session_wellbeing_checkins',
        ['work_session_id', 'created_at'],
        unique=False
    )


def downgrade() -> None:
    op.drop_index('idx_checkins_session_created', table_name='session_wellbeing_checkins')
    op.drop_index('idx_breaks_session_started', table_name='breaks')
    op.drop_index('idx_work_sessions_profile_started', table_name='work_sessions')
