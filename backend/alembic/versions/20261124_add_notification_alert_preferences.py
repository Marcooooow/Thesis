"""Add per-user browser alert preferences.

Revision ID: 20261124_alert_prefs
Revises: all current target heads
Create Date: 2026-11-24
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "20261124_alert_prefs"
down_revision: Union[str, Sequence[str], None] = (
    "20260923002000",
    "20261005175113",
    "20261022000002",
    "20261103000001",
    "20261107000002",
    "20261120000000",
    "add_database_backup_table",
    "add_profile_image_url",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    for column in (
        "browser_notifications_enabled",
        "notification_sounds_enabled",
        "tab_attention_enabled",
    ):
        op.execute(
            sa.text(
                f"""DO $$ BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND table_name = 'user_settings'
                          AND column_name = '{column}'
                    ) THEN
                        ALTER TABLE user_settings
                            ADD COLUMN {column} BOOLEAN NOT NULL DEFAULT TRUE;
                    END IF;
                END $$;"""
            )
        )


def downgrade() -> None:
    # Preferences are retained to avoid dropping user choices during rollback.
    pass
