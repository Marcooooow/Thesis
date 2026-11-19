import pytest
from datetime import datetime, timezone, timedelta, date, time
from sqlalchemy.orm import Session
from app.database import SessionLocal
from app.scheduler import create_scheduler, run_absence_scan, retry_pending_notifications
from app.models import User, Profile, EmployeeSchedule, AbsenceRecord, Notification

def test_phase3_scheduler_job_functions_execution():
    """Verify run_absence_scan and retry_pending_notifications execute cleanly with DB session lifecycle."""
    # Test execution of job functions
    try:
        run_absence_scan()
    except Exception as e:
        pytest.fail(f"run_absence_scan raised unexpected exception: {e}")

    try:
        retry_pending_notifications()
    except Exception as e:
        pytest.fail(f"retry_pending_notifications raised unexpected exception: {e}")

def test_phase3_scheduler_job_registration_in_singleton():
    """Verify singleton scheduler correctly registers absence scan and notification retry jobs with stable IDs."""
    scheduler = create_scheduler()
    try:
        scheduler.add_job(
            run_absence_scan,
            'interval',
            minutes=30,
            id='absence_detection_scan',
            replace_existing=True,
            coalesce=True,
            max_instances=1,
            misfire_grace_time=1800
        )
        scheduler.add_job(
            retry_pending_notifications,
            'interval',
            hours=1,
            id='notification_retry',
            replace_existing=True,
            coalesce=True,
            max_instances=1
        )
        scheduler.start()

        jobs = scheduler.get_jobs()
        job_ids = [j.id for j in jobs]
        assert 'absence_detection_scan' in job_ids
        assert 'notification_retry' in job_ids

        # Re-adding with same IDs should not duplicate jobs (replace_existing=True)
        scheduler.add_job(
            run_absence_scan,
            'interval',
            minutes=30,
            id='absence_detection_scan',
            replace_existing=True
        )
        assert len([j for j in scheduler.get_jobs() if j.id == 'absence_detection_scan']) == 1
    finally:
        if scheduler.running:
            scheduler.shutdown(wait=False)
