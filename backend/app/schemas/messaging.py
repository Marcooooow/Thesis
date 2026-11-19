from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
from datetime import datetime
import uuid

class UserPublic(BaseModel):
    id: uuid.UUID
    full_name: str
    email: str

    model_config = ConfigDict(from_attributes=True)

class MessageCreate(BaseModel):
    content: str = Field(..., min_after_trim=1 if hasattr(Field, 'min_after_trim') else 1, max_length=5000)

class MessageResponse(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    sender_id: uuid.UUID
    content: str
    created_at: datetime
    sender: Optional[UserPublic] = None

    model_config = ConfigDict(from_attributes=True)

class ConversationCreate(BaseModel):
    recipient_user_id: uuid.UUID

class ConversationResponse(BaseModel):
    id: uuid.UUID
    organization_id: uuid.UUID
    is_group: bool
    title: Optional[str] = None
    created_at: datetime
    participants: List[UserPublic] = []
    unread_count: int = 0
    last_message: Optional[MessageResponse] = None

    model_config = ConfigDict(from_attributes=True)

class ConversationListResponse(BaseModel):
    conversations: List[ConversationResponse]
    total: int

class MessageListResponse(BaseModel):
    messages: List[MessageResponse]
    total: int
    limit: int
    offset: int
