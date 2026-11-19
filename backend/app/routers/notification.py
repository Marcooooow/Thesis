"""Router for notification endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import List
from datetime import datetime

from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User, Notification
from ..services.break_reminder_service import BreakReminderService
from ..schemas.team import NotificationResponse, NotificationListResponse

router = APIRouter(
    prefix="/notifications",
    tags=["notifications"],
    responses={404: {"description": "Not found"}},
)


@router.get("", response_model=NotificationListResponse)
def get_notifications(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    filter_read: bool = Query(None),
):
    """
    Get user's notifications.
    Only returns notifications for the authenticated user.

    Query parameters:
    - limit: Max number of notifications to return (default 20, max 100)
    - offset: Number of notifications to skip (default 0)
    - filter_read: Optional - if True return only read, if False return only unread
    """
    # Build query - only show AVAILABLE notifications (suppressed ones are hidden)
    query = db.query(Notification).filter(
        Notification.recipient_user_id == current_user.id,
        Notification.delivery_status == 'AVAILABLE'
    )

    # Apply filter_read if provided
    if filter_read is not None:
        query = query.filter(Notification.is_read == filter_read)

    # Get total count (before pagination)
    total = query.count()

    # Get unread count for available notifications
    unread_count = db.query(Notification).filter(
        Notification.recipient_user_id == current_user.id,
        Notification.delivery_status == 'AVAILABLE',
        Notification.is_read == False
    ).count()

    # Order by newest first and apply pagination
    results = query.order_by(desc(Notification.created_at)).offset(offset).limit(limit).all()

    return NotificationListResponse(
        notifications=results,
        unread_count=unread_count,
        total=total,
        limit=limit,
        offset=offset,
    )


@router.patch("/{notification_id}/read", response_model=NotificationResponse)
def mark_notification_read(
    notification_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Mark a notification as read.
    Only the notification recipient can mark it as read.
    """
    # Parse UUID
    try:
        import uuid
        notif_id = uuid.UUID(notification_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid notification ID format",
        )

    # Get notification
    notification = db.query(Notification).filter(
        Notification.id == notif_id
    ).first()

    if not notification:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )

    # Check authorization - only recipient can read their own notification
    if notification.recipient_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this notification",
        )

    # Mark as read
    notification.is_read = True
    notification.read_at = datetime.utcnow()
    db.add(notification)
    db.commit()
    db.refresh(notification)

    return notification


@router.post("/read-all", response_model=dict)
def mark_all_notifications_read(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Mark all unread notifications as read for the current user.
    """
    notifications = db.query(Notification).filter(
        Notification.recipient_user_id == current_user.id,
        Notification.delivery_status == 'AVAILABLE',
        Notification.is_read == False
    ).all()

    now = datetime.utcnow()
    for notif in notifications:
        notif.is_read = True
        notif.read_at = now
        db.add(notif)

    db.commit()
    return {"message": "All notifications marked as read", "marked_count": len(notifications)}


@router.post("/evaluate-reminders", response_model=dict)
def evaluate_break_reminders(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Evaluate and dispatch smart break reminders for the authenticated user if thresholds are met.
    """
    notification = BreakReminderService.evaluate_and_dispatch_for_user(db, current_user.id)
    if notification:
        db.commit()
        return {"dispatched": True, "notification_id": str(notification.id), "title": notification.title}
    return {"dispatched": False}

