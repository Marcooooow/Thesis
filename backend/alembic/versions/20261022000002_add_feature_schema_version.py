"""add feature_schema_version to recommendation_feedback and ml_models

Revision ID: 20261022000002
Revises: 20261022000000
Create Date: 2026-10-22 00:00:02.00

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20261022000002'
down_revision = '20261022000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add feature_schema_version to recommendation_feedback
    op.add_column('recommendation_feedback',
                  sa.Column('feature_schema_version', sa.String(length=50), nullable=False, server_default='v1-base'))
    # Add feature_schema_version to ml_models
    op.add_column('ml_models',
                  sa.Column('feature_schema_version', sa.String(length=50), nullable=False, server_default='v1-base'))

    # Create check constraints for allowed versions
    op.create_check_constraint(
        'ck_recommendation_feedback_feature_schema_version',
        'recommendation_feedback',
        "feature_schema_version IN ('v1-base', 'v2-wellbeing')"
    )
    op.create_check_constraint(
        'ck_ml_models_feature_schema_version',
        'ml_models',
        "feature_schema_version IN ('v1-base', 'v2-wellbeing')"
    )


def downgrade() -> None:
    # Drop check constraints
    op.drop_constraint('ck_recommendation_feedback_feature_schema_version', 'recommendation_feedback', type_='check')
    op.drop_constraint('ck_ml_models_feature_schema_version', 'ml_models', type_='check')
    # Drop columns
    op.drop_column('recommendation_feedback', 'feature_schema_version')
    op.drop_column('ml_models', 'feature_schema_version')