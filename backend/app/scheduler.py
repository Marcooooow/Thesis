import logging
from datetime import datetime, timezone, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from .database import SQLALCHEMY_DATABASE_URL, SessionLocal
from .services.absence_detection import AbsenceDetectionService
from .models import RecommendationFeedback, WorkSession
from .auth.security import log_system_activity

from typing import Optional
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

def auto_close_stale_sessions(db: Optional[Session] = None) -> None:
    """
    Automatically close stale active work sessions exceeding the maximum shift duration threshold (16 hours).
    Idempotent, auditable, and system-generated.
    """
    close_db = False
    if db is None:
        db = SessionLocal()
        close_db = True
    try:
        now = datetime.now(timezone.utc)
        threshold = now - timedelta(hours=16)

        stale_sessions = db.query(WorkSession).filter(
            WorkSession.ended_at.is_(None),
            WorkSession.started_at < threshold
        ).all()

        closed_count = 0
        for session in stale_sessions:
            estimated_end = session.started_at + timedelta(hours=16)
            session.ended_at = estimated_end
            session.updated_at = now

            log_system_activity(
                db=db,
                user_id=session.profile.user_id if session.profile and session.profile.user_id else None,
                action_type="WORK_SESSION_SYSTEM_AUTO_CLOSED",
                action_details={
                    "work_session_id": str(session.id),
                    "started_at": session.started_at.isoformat(),
                    "system_ended_at": estimated_end.isoformat(),
                    "reason": "max_shift_duration_exceeded_16h"
                }
            )
            closed_count += 1

        if closed_count > 0:
            db.commit()
            logger.info(f"Auto-closed {closed_count} stale work session(s) exceeding 16 hours.")
    except Exception as e:
        logger.error(f"Failed to auto-close stale work sessions: {e}")
        db.rollback()
    finally:
        if close_db:
            db.close()

def run_absence_scan() -> None:
    """Execute scheduled absence detection scan."""
    db = SessionLocal()
    try:
        service = AbsenceDetectionService(db)
        result = service.scan_due_absences()
        logger.info(f"Scheduled absence scan completed successfully: {result}")
    except Exception as e:
        logger.error(f"Scheduled absence scan failed: {e}")
        db.rollback()
    finally:
        db.close()

def retry_pending_notifications() -> None:
    """Execute scheduled retry of pending/failed absence alert notifications."""
    db = SessionLocal()
    try:
        service = AbsenceDetectionService(db)
        count = service.retry_pending_notifications()
        logger.info(f"Scheduled notification retry completed successfully: {count} notifications processed")
    except Exception as e:
        logger.error(f"Scheduled notification retry failed: {e}")
        db.rollback()
    finally:
        db.close()

def expire_unanswered_recommendations() -> None:
    """
    Expire unanswered recommendations older than 24 hours.
    Sets user_action='expired' for recommendations with user_action IS NULL.
    Only affects non-WLB recommendations that are older than 24h and unanswered.
    """
    db = SessionLocal()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=24)

        # Update unanswered recommendations (user_action IS NULL) older than 24h
        # Exclude WLB recommendations (they are rule-based and handled differently)
        # Exclude already answered (accepted/dismissed/ignored/helpful/not_helpful)
        result = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_action.is_(None),
            RecommendationFeedback.timestamp < cutoff,
            RecommendationFeedback.recommendation_type.notlike('WLB_%')
        ).update({
            'user_action': 'expired',
            'updated_at': datetime.now(timezone.utc)
        }, synchronize_session=False)

        if result:
            db.commit()
            logger.info(f"Expired {result} unanswered recommendations")
        else:
            db.commit()
            logger.debug("No unanswered recommendations to expire")
    except Exception as e:
        logger.error(f"Recommendation expiration failed: {e}")
        db.rollback()
    finally:
        db.close()

def create_scheduler() -> BackgroundScheduler:
    """
    Create and configure APScheduler instance with SQLAlchemyJobStore.

    Deployment Notes:
    - SQLAlchemyJobStore provides persistent job storage across application restarts,
      NOT distributed locking.
    - Development: One scheduler instance runs within the FastAPI process.
    - Production: Must run exactly ONE dedicated scheduler process/service OR configure
      WEB_CONCURRENCY=1 to prevent concurrent duplicate job execution across multiple Uvicorn workers.
    """
    jobstores = {
        'default': SQLAlchemyJobStore(url=SQLALCHEMY_DATABASE_URL)
    }
    scheduler = BackgroundScheduler(jobstores=jobstores, timezone="UTC")
    return scheduler
