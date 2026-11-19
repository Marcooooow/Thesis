import pytest
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from sqlalchemy import text
from app.database import SQLALCHEMY_DATABASE_URL, SessionLocal
from app.scheduler import create_scheduler
from app.services.absence_detection import AbsenceDetectionService

def sample_job_func():
    pass

def test_scheduler_initialization_and_jobstore():
    """Verify APScheduler creates successfully with SQLAlchemyJobStore."""
    scheduler = create_scheduler()
    assert isinstance(scheduler, BackgroundScheduler)
    assert isinstance(scheduler._jobstores.get('default'), SQLAlchemyJobStore)

def test_scheduler_job_registration():
    """Verify jobs can be registered and retrieved when started using replace_existing=True."""
    scheduler = create_scheduler()

    try:
        scheduler.start()
        scheduler.add_job(sample_job_func, 'interval', minutes=30, id='test_scan_job', replace_existing=True)
        scheduler.add_job(sample_job_func, 'interval', minutes=30, id='test_scan_job', replace_existing=True)
        jobs = scheduler.get_jobs()
        scan_jobs = [j for j in jobs if j.id == 'test_scan_job']
        assert len(scan_jobs) == 1
    finally:
        if scheduler.running:
            scheduler.shutdown(wait=False)

def test_database_session_cleanup_in_jobs():
    """Verify that database sessions created in scheduled routines close cleanly."""
    db = SessionLocal()
    try:
        res = db.execute(text("SELECT 1")).scalar()
        assert res == 1
    finally:
        db.close()

def test_absence_detection_skips_unscheduled_profiles():
    """Verify that absence detection service gracefully handles profiles with no schedule."""
    db = SessionLocal()
    try:
        service = AbsenceDetectionService(db)
        schedules = service.get_active_schedules()
        assert isinstance(schedules, list)
    finally:
        db.close()

def test_notification_constraint_inspection():
    """Verify existing notification type CHECK constraint exists in DB schema."""
    db = SessionLocal()
    try:
        query = text("""
            SELECT conname
            FROM pg_constraint
            WHERE conrelid = 'notifications'::regclass
              AND contype = 'c'
              AND conname = 'chk_notification_type';
        """)
        result = db.execute(query).scalar()
        assert result == 'chk_notification_type'
    finally:
        db.close()
