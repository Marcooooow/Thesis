from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, and_
from sqlalchemy.exc import IntegrityError
from ..models import Conversation, ConversationParticipant, Message, User, OrganizationMembership
from ..database import get_db
import uuid

def get_user_organization_ids(db: Session, user_id: uuid.UUID) -> list:
    memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == user_id,
        OrganizationMembership.status == "APPROVED"
    ).all()
    return [m.organization_id for m in memberships]

def get_conversation_for_user(db: Session, user_id: uuid.UUID, conversation_id: uuid.UUID):
    org_ids = get_user_organization_ids(db, user_id)
    return db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.organization_id.in_(org_ids)
    ).first()

def get_or_create_direct_conversation(db: Session, user_a: uuid.UUID, user_b: uuid.UUID, org_id: uuid.UUID):
    # Sort pair deterministically for DB constraint
    sorted_pair = sorted([str(user_a), str(user_b)])
    user_a_str, user_b_str = sorted_pair
    user_a_uuid = uuid.UUID(user_a_str)
    user_b_uuid = uuid.UUID(user_b_str)

    # Check existing via DB-level unique constraint query
    existing = db.query(Conversation).filter(
        Conversation.organization_id == org_id,
        Conversation.is_group == False,
        Conversation.direct_user_a == user_a_uuid,
        Conversation.direct_user_b == user_b_uuid,
    ).first()
    if existing:
        return existing
    # Try reverse pair (should be covered by sorted, but defensive)
    existing_rev = db.query(Conversation).filter(
        Conversation.organization_id == org_id,
        Conversation.is_group == False,
        Conversation.direct_user_a == user_b_uuid,
        Conversation.direct_user_b == user_a_uuid,
    ).first()
    if existing_rev:
        return existing_rev

    # Create new with canonical pair
    conv = Conversation(
        organization_id=org_id,
        is_group=False,
        direct_user_a=user_a_uuid,
        direct_user_b=user_b_uuid,
    )
    db.add(conv)
    db.flush()
    for uid in [user_a, user_b]:
        db.add(ConversationParticipant(conversation_id=conv.id, user_id=uid))
    return conv

def get_user_conversations(db: Session, user_id: uuid.UUID, limit: int = 20, offset: int = 0):
    org_ids = get_user_organization_ids(db, user_id)
    # Get conversations where user participates and org matches
    query = db.query(Conversation).join(ConversationParticipant).filter(
        ConversationParticipant.user_id == user_id,
        Conversation.organization_id.in_(org_ids)
    ).order_by(desc(Conversation.created_at))
    total = query.count()
    results = query.offset(offset).limit(limit).all()
    return results, total

def get_messages_for_conversation(db: Session, conversation_id: uuid.UUID, user_id: uuid.UUID, limit: int = 20, offset: int = 0):
    # Verify access
    org_ids = get_user_organization_ids(db, user_id)
    conv = db.query(Conversation).filter(
        Conversation.id == conversation_id,
        Conversation.organization_id.in_(org_ids)
    ).first()
    if not conv:
        return [], 0
    # Check participant
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conversation_id,
        ConversationParticipant.user_id == user_id
    ).first()
    if not participant:
        return [], 0
    query = db.query(Message).filter(Message.conversation_id == conversation_id).order_by(Message.created_at.asc())
    total = query.count()
    results = query.offset(offset).limit(limit).all()
    return results, total

def create_message(db: Session, conversation_id: uuid.UUID, sender_id: uuid.UUID, content: str):
    msg = Message(conversation_id=conversation_id, sender_id=sender_id, content=content)
    db.add(msg)
    db.flush()
    return msg

def get_unread_counts(db: Session, conversation_id: uuid.UUID, user_id: uuid.UUID):
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conversation_id,
        ConversationParticipant.user_id == user_id
    ).first()
    if not participant or not participant.last_read_at:
        # All messages from others are unread
        count = db.query(Message).filter(
            Message.conversation_id == conversation_id,
            Message.sender_id != user_id
        ).count()
        return count
    # Deterministic read cursor: timestamp + message_id
    # Unread = messages with created_at > last_read_at OR (created_at = last_read_at AND id > last_read_message_id)
    # For simplicity in MVP: use timestamp comparison primarily, with message_id tie-breaker
    read_id = participant.last_read_message_id
    # Count messages created after last read timestamp
    count = db.query(Message).filter(
        Message.conversation_id == conversation_id,
        Message.created_at > participant.last_read_at,
        Message.sender_id != user_id
    ).count()
    # Tie-breaker: same timestamp, newer message id
    if read_id and participant.last_read_at:
        tie = db.query(Message).filter(
            Message.conversation_id == conversation_id,
            Message.created_at == participant.last_read_at,
            Message.id > read_id,
            Message.sender_id != user_id
        ).count()
        count += tie
    return count

def mark_read(db: Session, conversation_id: uuid.UUID, user_id: uuid.UUID, message_id: Optional[uuid.UUID] = None):
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conversation_id,
        ConversationParticipant.user_id == user_id
    ).first()
    if not participant:
        return False
    # Find latest message in conversation to set read cursor
    latest = db.query(Message).filter(Message.conversation_id == conversation_id).order_by(desc(Message.created_at)).first()
    if latest:
        participant.last_read_message_id = latest.id
        participant.last_read_at = latest.created_at
    else:
        participant.last_read_at = func.now()
    db.flush()
    return True
