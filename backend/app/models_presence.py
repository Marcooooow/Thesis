from sqlalchemy import Column, String, DateTime, Boolean, ForeignKey, func, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
import uuid
from .database import Base

class UserPresence(Base):
    __tablename__ = "user_presence"
    user_id = Column(PG_UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    is_online = Column(Boolean, nullable=False, server_default="false")
    last_heartbeat = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
    __table_args__ = (Index("ix_user_presence_user_id", "user_id"), Index("ix_user_presence_heartbeat", "last_heartbeat"))
