"""Record registration notice consent.

Revision ID: 20261126_registration_consent
Revises: 20261124_alert_prefs
Create Date: 2026-11-26
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "20261126_registration_consent"
down_revision: Union[str, Sequence[str], None] = "20261124_alert_prefs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("terms_accepted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("terms_version", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("data_consent_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("privacy_notice_version", sa.String(length=32), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "privacy_notice_version")
    op.drop_column("users", "data_consent_at")
    op.drop_column("users", "terms_version")
    op.drop_column("users", "terms_accepted_at")
