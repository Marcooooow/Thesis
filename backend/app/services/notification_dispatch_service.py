"""Centralized Notification Dispatch Service with DND evaluation and idempotency support."""

import uuid
from typing import Optional
from datetime import datetime
from zoneinfo import ZoneInfo
from sqlalchemy.orm import Session
from sqlalchemy import desc
from sqlalchemy.exc import IntegrityError

from ..models import User, Profile, WorkSession, UserSettings, Notification


class NotificationDispatchService:
    @staticmethod
    def dispatch(
        db: Session,
        recipient_user_id: uuid.UUID,
        title: str,
        message: str,
        notification_type: str,
        priority: str = "STANDARD",
        idempotency_key: Optional[str] = None,
        related_entity_id: Optional[uuid.UUID] = None
    ) -> Notification:
        """
        Dispatches a notification with category preferences, quiet hours, DND evaluation and idempotent creation.
        Uses a nested savepoint for idempotency conflicts without affecting the parent transaction.
        Never calls db.commit() or parent db.rollback().
        """
        # 1. Check idempotency if key provided
        if idempotency_key:
            existing = db.query(Notification).filter(
                Notification.recipient_user_id == recipient_user_id,
                Notification.idempotency_key == idempotency_key
            ).first()
            if existing:
                return existing

        # 2. Get user settings
        settings = db.query(UserSettings).filter(UserSettings.user_id == recipient_user_id).first()

        delivery_status = "AVAILABLE"

        if settings:
            # Check master toggle
            if not settings.notifications_enabled and priority != "CRITICAL":
                delivery_status = "SUPPRESSED_DISABLED"
            else:
                # Check category preferences
                category_allowed = True
                t = notification_type.upper()
                if "BREAK" in t and not settings.break_reminders:
                    category_allowed = False
                elif ("SHIFT" in t or "ATTENDANCE" in t) and not settings.shift_reminders:
                    category_allowed = False
                elif "TASK" in t and not settings.task_reminders:
                    category_allowed = False
                elif "FOCUS" in t and not settings.focus_reminders:
                    category_allowed = False
                elif "WELLNESS" in t and not settings.wellness_reminders:
                    category_allowed = False
                elif "DAILY_SUMMARY" in t and not settings.daily_summary:
                    category_allowed = False
                elif "WEEKLY_SUMMARY" in t and not settings.weekly_summary:
                    category_allowed = False

                if not category_allowed and priority != "CRITICAL":
                    delivery_status = "SUPPRESSED_PREFERENCE"
                else:
                    # Check Quiet Hours
                    in_quiet_hours = False
                    if settings.quiet_hours_enabled and settings.quiet_hours_start and settings.quiet_hours_end:
                        try:
                            tz_str = settings.timezone or "UTC"
                            user_tz = ZoneInfo(tz_str)
                            now_user = datetime.now(user_tz)
                            current_time_str = now_user.strftime("%H:%M")

                            start_str = settings.quiet_hours_start
                            end_str = settings.quiet_hours_end

                            if start_str <= end_str:
                                in_quiet_hours = start_str <= current_time_str <= end_str
                            else:
                                in_quiet_hours = current_time_str >= start_str or current_time_str <= end_str
                        except Exception:
                            pass

                    if in_quiet_hours and priority != "CRITICAL":
                        delivery_status = "SUPPRESSED_QUIET_HOURS"
                    else:
                        # Check DND (Automatic + Manual override)
                        profile = db.query(Profile).filter(Profile.user_id == recipient_user_id).first()
                        automatic_dnd = False
                        if profile:
                            latest_session = db.query(WorkSession).filter(
                                WorkSession.profile_id == profile.id
                            ).order_by(desc(WorkSession.started_at)).first()
                            if latest_session and latest_session.ended_at is not None:
                                automatic_dnd = True

                        manual_override = settings.manual_dnd_override
                        effective_dnd = manual_override if manual_override is not None else automatic_dnd

                        if priority == "CRITICAL":
                            effective_dnd = False

                        if effective_dnd:
                            delivery_status = "SUPPRESSED_DND"
        else:
            # Fallback to automatic DND if no settings row exists
            profile = db.query(Profile).filter(Profile.user_id == recipient_user_id).first()
            automatic_dnd = False
            if profile:
                latest_session = db.query(WorkSession).filter(
                    WorkSession.profile_id == profile.id
                ).order_by(desc(WorkSession.started_at)).first()
                if latest_session and latest_session.ended_at is not None:
                    automatic_dnd = True

            effective_dnd = automatic_dnd
            if priority == "CRITICAL":
                effective_dnd = False

            if effective_dnd:
                delivery_status = "SUPPRESSED_DND"

        # 7. Construct notification
        notification = Notification(
            recipient_user_id=recipient_user_id,
            type=notification_type,
            title=title,
            message=message,
            priority=priority,
            delivery_status=delivery_status,
            idempotency_key=idempotency_key,
            related_entity_id=related_entity_id,
            is_read=False,
            is_actioned=False,
        )

        if idempotency_key:
            try:
                with db.begin_nested():
                    db.add(notification)
                    db.flush()
            except IntegrityError:
                existing = db.query(Notification).filter(
                    Notification.recipient_user_id == recipient_user_id,
                    Notification.idempotency_key == idempotency_key
                ).first()
                if existing:
                    return existing
                raise
        else:
            db.add(notification)
            db.flush()

        return notification
