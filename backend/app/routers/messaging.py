from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User, OrganizationMembership, Conversation, ConversationParticipant, Message
from ..services import messaging_service as ms
from .presence import compute_user_presence_status
import uuid

router = APIRouter(prefix="/messages", tags=["messages"])


@router.get("", response_model=dict)
def list_conversations(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    org_ids = ms.get_user_organization_ids(db, current_user.id)
    if not org_ids:
        return {"conversations": [], "total": 0}
    query = db.query(Conversation).join(ConversationParticipant).filter(
        ConversationParticipant.user_id == current_user.id,
        Conversation.organization_id.in_(org_ids)
    ).order_by(Conversation.created_at.desc())
    total = query.count()
    results = query.offset(offset).limit(limit).all()
    out = []
    for conv in results:
        count = ms.get_unread_counts(db, conv.id, current_user.id)
        last_msg = db.query(Message).filter(Message.conversation_id == conv.id).order_by(Message.created_at.desc()).first()

        participants_out = []
        for p in conv.participants:
            u = p.user
            if u:
                p_status = compute_user_presence_status(db, u.id).get("status_mode", "OFFLINE").lower()
                participants_out.append({
                    "id": str(u.id),
                    "full_name": u.full_name,
                    "email": u.email,
                    "role": u.role,
                    "presence_status": p_status,
                })

        out.append({
            "id": str(conv.id),
            "organization_id": str(conv.organization_id),
            "is_group": conv.is_group,
            "title": conv.title,
            "created_at": conv.created_at,
            "participants": participants_out,
            "unread_count": count,
            "last_message": {
                "id": str(last_msg.id) if last_msg else None,
                "content": last_msg.content if last_msg else "",
                "sender_id": str(last_msg.sender_id) if last_msg else None,
                "created_at": last_msg.created_at if last_msg else None,
            } if last_msg else None,
        })
    return {"conversations": out, "total": total}


@router.post("/conversations", status_code=status.HTTP_201_CREATED, response_model=dict)
def create_direct_conversation(
    body: dict,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    recipient_uid = body.get("recipient_user_id")
    if not recipient_uid:
        raise HTTPException(status_code=400, detail="recipient_user_id required")
    try:
        recipient = db.query(User).filter(User.id == recipient_uid).first()
    except Exception:
        raise HTTPException(status_code=404, detail="User not found")
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    org_ids = ms.get_user_organization_ids(db, current_user.id)
    target_orgs = ms.get_user_organization_ids(db, recipient.id)
    shared_orgs = set(org_ids) & set(target_orgs)
    if not shared_orgs:
        raise HTTPException(status_code=403, detail="Users must belong to the same organization")
    org_id = sorted(shared_orgs, key=str)[0]

    try:
        conv = ms.get_or_create_direct_conversation(db, current_user.id, recipient.id, org_id)
    except IntegrityError:
        db.rollback()
        existing = db.query(Conversation).join(ConversationParticipant).filter(
            ConversationParticipant.user_id.in_([current_user.id, recipient.id]),
            Conversation.is_group == False,
        ).group_by(Conversation.id).having(
            __import__('sqlalchemy').func.count(ConversationParticipant.user_id) == 2
        ).first()
        if existing:
            count = ms.get_unread_counts(db, existing.id, current_user.id)
            return {"id": str(existing.id), "created": False, "unread_count": count}
        raise
    db.commit()
    count = ms.get_unread_counts(db, conv.id, current_user.id)
    return {"id": str(conv.id), "created": True, "unread_count": count}


@router.get("/conversations/{conversation_id}/messages", response_model=dict)
def list_messages(
    conversation_id: str,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    try:
        conv_id = uuid.UUID(conversation_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid conversation ID format")
    org_ids = ms.get_user_organization_ids(db, current_user.id)
    conv = db.query(Conversation).filter(
        Conversation.id == conv_id,
        Conversation.organization_id.in_(org_ids)
    ).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conv_id,
        ConversationParticipant.user_id == current_user.id
    ).first()
    if not participant:
        raise HTTPException(status_code=403, detail="Not a participant of this conversation")

    msgs, total = ms.get_messages_for_conversation(db, conv_id, current_user.id, limit, offset)
    return {
        "messages": [
            {
                "id": str(m.id),
                "conversation_id": str(m.conversation_id),
                "sender_id": str(m.sender_id),
                "content": m.content,
                "created_at": m.created_at,
            }
            for m in msgs
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.post("/conversations/{conversation_id}/messages", status_code=status.HTTP_201_CREATED, response_model=dict)
def send_message(
    conversation_id: str,
    body: dict,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    try:
        conv_id = uuid.UUID(conversation_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid conversation ID format")
    content = body.get("content")
    if not content or not isinstance(content, str) or len(content.strip()) < 1:
        raise HTTPException(status_code=400, detail="Content is required")

    org_ids = ms.get_user_organization_ids(db, current_user.id)
    conv = db.query(Conversation).filter(
        Conversation.id == conv_id,
        Conversation.organization_id.in_(org_ids)
    ).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conv_id,
        ConversationParticipant.user_id == current_user.id
    ).first()
    if not participant:
        raise HTTPException(status_code=403, detail="Not a participant of this conversation")

    msg = ms.create_message(db, conv_id, current_user.id, content)
    db.commit()
    return {
        "id": str(msg.id),
        "conversation_id": str(msg.conversation_id),
        "sender_id": str(msg.sender_id),
        "content": msg.content,
        "created_at": msg.created_at,
    }


@router.post("/conversations/{conversation_id}/read", response_model=dict)
def mark_conversation_read(
    conversation_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    try:
        conv_id = uuid.UUID(conversation_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid conversation ID format")
    org_ids = ms.get_user_organization_ids(db, current_user.id)
    conv = db.query(Conversation).filter(
        Conversation.id == conv_id,
        Conversation.organization_id.in_(org_ids)
    ).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    participant = db.query(ConversationParticipant).filter(
        ConversationParticipant.conversation_id == conv_id,
        ConversationParticipant.user_id == current_user.id
    ).first()
    if not participant:
        raise HTTPException(status_code=403, detail="Not a participant")

    ok = ms.mark_read(db, conv_id, current_user.id)
    db.commit()
    count = ms.get_unread_counts(db, conv_id, current_user.id)
    return {"marked_read": ok, "unread_count": count}


@router.get("/members", response_model=list)
def list_organization_members(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    org_ids = ms.get_user_organization_ids(db, current_user.id)
    if not org_ids:
        return []
    memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED"
    ).all()
    user_ids = [m.user_id for m in memberships if m.user_id != current_user.id]
    users = db.query(User).filter(User.id.in_(user_ids), User.is_active == True).all()
    return [{
        "id": str(u.id),
        "full_name": u.full_name,
        "email": u.email,
        "role": u.role,
        "presence_status": compute_user_presence_status(db, u.id).get("status_mode", "OFFLINE").lower()
    } for u in users]
