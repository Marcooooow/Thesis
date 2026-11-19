revision = 'add_direct_conversation_unique'
down_revision = 'add_messaging_tables'
branch_labels = None
depends_on = None

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

def upgrade():
    op.add_column('conversations', sa.Column('direct_user_a', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.add_column('conversations', sa.Column('direct_user_b', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.create_unique_constraint('uq_direct_conversation', 'conversations', ['organization_id', 'direct_user_a', 'direct_user_b', 'is_group'])
    op.create_check_constraint('chk_direct_pair', 'conversations', '((is_group = true AND direct_user_a IS NULL AND direct_user_b IS NULL) OR (is_group = false AND direct_user_a IS NOT NULL AND direct_user_b IS NOT NULL))')

def downgrade():
    op.drop_constraint('chk_direct_pair', 'conversations', type_='check')
    op.drop_constraint('uq_direct_conversation', 'conversations', type_='unique')
    op.drop_column('conversations', 'direct_user_b')
    op.drop_column('conversations', 'direct_user_a')
