"""Service for evaluating and dispatching smart break reminders."""

import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import desc

from ..models import User, Profile, WorkSession, Break, UserSettings, Notification
from .notification_dispatch_service import NotificationDispatchService


class BreakReminderService:
    @staticmethod
    def evaluate_and_dispatch_for_user(db: Session, user_id: uuid.UUID) -> Optional[Notification]:
        """
        Evaluates whether an active user needs a break reminder based on continuous work duration,
        completed breaks, user settings, DND, and idempotency cooldowns.
        If conditions are met, dispatches a break reminder notification.
        """
        # 1. Check user settings / preferences
        settings = db.query(UserSettings).filter(UserSettings.user_id == user_id).first()
        if settings:
            if not settings.notifications_enabled or not settings.break_reminders:
                return None
            interval_minutes = settings.break_interval_minutes or 30
        else:
            interval_minutes = 30

        # 2. Get user profile
        profile = db.query(Profile).filter(Profile.user_id == user_id).first()
        if not profile:
            return None

        # 3. Check for active work session
        active_session = db.query(WorkSession).filter(
            WorkSession.profile_id == profile.id,
            WorkSession.ended_at.is_(None)
        ).first()
        if not active_session:
            return None

        # 4. Check if an active break currently exists in this session
        active_break = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.ended_at.is_(None)
        ).first()
        if active_break:
            return None  # User is currently on a break

        # 5. Calculate continuous work duration since last completed break or session start
        now = datetime.now(timezone.utc)

        # Find the latest completed break in this session
        latest_completed_break = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.ended_at.isnot(None)
        ).order_by(desc(Break.ended_at)).first()

        reference_time = latest_completed_break.ended_at if latest_completed_break else active_session.started_at

        # Ensure timezone awareness for comparison
        if reference_time.tzinfo is None:
            reference_time = reference_time.replace(tzinfo=timezone.utc)
        if now.tzinfo is None:
            now = now.replace(tzinfo=timezone.utc)

        elapsed_minutes = (now - reference_time).total_seconds() / 60.0

        if elapsed_minutes < interval_minutes:
            return None  # Threshold not yet reached

        # 6. Construct stable idempotency key for this work session and interval window
        # Window bucket ensures we don't spam reminders for the same continuous block
        window_bucket = int(elapsed_minutes / interval_minutes)
        idempotency_key = f"break_reminder_{user_id}_{active_session.id}_{window_bucket}"

        # 7. Check if reminder already dispatched for this idempotency key
        existing_notif = db.query(Notification).filter(
            Notification.recipient_user_id == user_id,
            Notification.idempotency_key == idempotency_key
        ).first()
        if existing_notif:
            return existing_notif  # Already dispatched for this window

        # 8. Dispatch notification via NotificationDispatchService
        title = "Time for a Break!"
        message = f"You've been working continuously for over {int(elapsed_minutes)} minutes. Take a short break to recharge and maintain your wellbeing."

        notification = NotificationDispatchService.dispatch(
            db=db,
            recipient_user_id=user_id,
            title=title,
            message=message,
            notification_type="BREAK_REMINDER",
            priority="STANDARD",
            idempotency_key=idempotency_key,
            related_entity_id=active_session.id
        )

        return notification
