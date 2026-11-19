"""Add task_type, scheduled_start_date, and blocked_reason to tasks

Revision ID: 20261111_000001
Revises: 20261110000001
Create Date: 2026-11-11
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20261111_000001'
down_revision = '20261110000001'
branch_labels = None
depends_on = None

def upgrade():
    # 1. Add new columns
    op.add_column('tasks', sa.Column('task_type', sa.String(length=20), nullable=True))
    op.add_column('tasks', sa.Column('scheduled_start_date', sa.DateTime(timezone=True), nullable=True))
    op.add_column('tasks', sa.Column('blocked_reason', sa.Text(), nullable=True))

    # 2. Backfill task_type based on assigned_by_user_id semantics (NULL -> PERSONAL, NOT NULL -> WORK)
    # updated_at is explicitly preserved and NOT touched.
    op.execute("""
        UPDATE tasks
        SET task_type = CASE WHEN assigned_by_user_id IS NULL THEN 'PERSONAL' ELSE 'WORK' END
    """)

    # 3. Alter task_type to NOT NULL with server default 'PERSONAL'
    op.alter_column('tasks', 'task_type',
               existing_type=sa.String(length=20),
               nullable=False,
               server_default='PERSONAL')

    # 4. Add CHECK constraint for task_type
    op.create_check_constraint(
        'chk_task_type',
        'tasks',
        sa.text("task_type IN ('PERSONAL', 'WORK')")
    )

    # 5. Add index on task_type for performance
    op.create_index('ix_tasks_task_type', 'tasks', ['task_type'], unique=False)


def downgrade():
    op.drop_index('ix_tasks_task_type', table_name='tasks')
    op.drop_constraint('chk_task_type', 'tasks', type_='check')
    op.drop_column('tasks', 'blocked_reason')
    op.drop_column('tasks', 'scheduled_start_date')
    op.drop_column('tasks', 'task_type')
