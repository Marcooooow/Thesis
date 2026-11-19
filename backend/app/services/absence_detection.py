from sqlalchemy.orm import Session
from sqlalchemy import text, and_, or_, desc
from typing import List, Optional, Dict, Any
from datetime import date, time, datetime, timezone, timedelta
from zoneinfo import ZoneInfo
import uuid

from ..models import EmployeeSchedule, LeaveRequest, AbsenceRecord, Profile, UserSettings, User, WorkSession
from .notification_dispatch_service import NotificationDispatchService

class AbsenceDetectionService:
    def __init__(self, db: Session):
        self.db = db

    def get_active_schedules(self, target_date: Optional[date] = None) -> List[EmployeeSchedule]:
        if target_date is None:
            target_date = date.today()
        return self.db.query(EmployeeSchedule).filter(
            EmployeeSchedule.effective_from <= target_date,
            or_(
                EmployeeSchedule.effective_until.is_(None),
                target_date < EmployeeSchedule.effective_until
            )
        ).all()

    def get_grace_minutes(self, profile_id: uuid.UUID) -> int:
        profile = self.db.query(Profile).filter(Profile.id == profile_id).first()
        if not profile:
            return 120
        settings = self.db.query(UserSettings).filter(UserSettings.user_id == profile.user_id).first()
        return settings.absence_grace_minutes if settings and settings.absence_grace_minutes is not None else 120

    def calculate_grace_deadline_utc(self, schedule: EmployeeSchedule, local_date: date, grace_minutes: int) -> datetime:
        tz = ZoneInfo(schedule.timezone)
        shift_start_local = datetime.combine(local_date, schedule.shift_start, tzinfo=tz)
        grace_local = shift_start_local + timedelta(minutes=grace_minutes)
        return grace_local.astimezone(timezone.utc)

    def has_session_in_local_day(self, profile_id: uuid.UUID, local_date: date, schedule: EmployeeSchedule) -> bool:
        tz = ZoneInfo(schedule.timezone)
        local_start = datetime.combine(local_date, time.min, tzinfo=tz)
        local_end = datetime.combine(local_date, time.max, tzinfo=tz)
        utc_start = local_start.astimezone(timezone.utc)
        utc_end = local_end.astimezone(timezone.utc)

        session = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            WorkSession.started_at >= utc_start,
            WorkSession.started_at < utc_end
        ).first()
        return session is not None

    def has_approved_leave(self, profile_id: uuid.UUID, local_date: date) -> Optional[LeaveRequest]:
        return self.db.query(LeaveRequest).filter(
            LeaveRequest.profile_id == profile_id,
            LeaveRequest.status == 'APPROVED',
            LeaveRequest.start_date <= local_date,
            LeaveRequest.end_date >= local_date
        ).first()

    def scan_due_absences(self, now_utc: datetime = None) -> Dict[str, Any]:
        if now_utc is None:
            now_utc = datetime.now(timezone.utc)

        scanned_count = 0
        detected_count = 0
        today_utc = now_utc.date()

        for days_ago in [1, 0]:
            check_date = today_utc - timedelta(days=days_ago)
            schedules = self.get_active_schedules(check_date)

            for sched in schedules:
                scanned_count += 1
                tz = ZoneInfo(sched.timezone)
                day_name = check_date.strftime('%A').lower()
                if sched.work_days and day_name not in [d.lower() for d in sched.work_days]:
                    continue

                grace_minutes = self.get_grace_minutes(sched.profile_id)
                grace_deadline = self.calculate_grace_deadline_utc(sched, check_date, grace_minutes)

                if now_utc < grace_deadline:
                    continue

                has_session = self.has_session_in_local_day(sched.profile_id, check_date, sched)
                if has_session:
                    continue

                leave = self.has_approved_leave(sched.profile_id, check_date)
                classification = 'LEAVE_APPROVED' if leave else 'UNREPORTED'
                leave_id = leave.id if leave else None

                absence = self.upsert_absence_record(
                    profile_id=sched.profile_id,
                    absence_date=check_date,
                    schedule_id=sched.id,
                    classification=classification,
                    leave_request_id=leave_id,
                    grace_minutes=grace_minutes,
                    detection_run_at=now_utc
                )

                if classification == 'UNREPORTED' and absence.notification_status == 'PENDING':
                    self._dispatch_absence_alert(absence)
                    detected_count += 1

        self.db.commit()
        return {"scanned": scanned_count, "detected": detected_count}

    def upsert_absence_record(self, profile_id: uuid.UUID, absence_date: date, schedule_id: uuid.UUID, classification: str, leave_request_id: Optional[uuid.UUID], grace_minutes: int, detection_run_at: datetime) -> AbsenceRecord:
        existing = self.db.query(AbsenceRecord).filter(
            AbsenceRecord.profile_id == profile_id,
            AbsenceRecord.absence_date == absence_date
        ).first()

        if existing:
            if existing.classification != classification:
                existing.classification = classification
                existing.leave_request_id = leave_request_id
                existing.updated_at = datetime.now(timezone.utc)
            return existing

        absence = AbsenceRecord(
            profile_id=profile_id,
            absence_date=absence_date,
            schedule_id=schedule_id,
            classification=classification,
            leave_request_id=leave_request_id,
            detection_run_at=detection_run_at,
            grace_period_minutes=grace_minutes,
            notification_status='PENDING'
        )
        self.db.add(absence)
        self.db.flush()
        return absence

    def _dispatch_absence_alert(self, absence: AbsenceRecord) -> bool:
        profile = self.db.query(Profile).filter(Profile.id == absence.profile_id).first()
        if not profile:
            return False

        user_id = profile.user_id
        success = NotificationDispatchService.dispatch(
            db=self.db,
            recipient_user_id=user_id,
            title="Unreported Absence Alert",
            message=f"An unreported absence has been logged for your shift on {absence.absence_date}.",
            notification_type="ABSENCE_ALERT",
            priority="STANDARD",
            idempotency_key=f"absence-{absence.profile_id}-{absence.absence_date}",
            related_entity_id=absence.id
        )
        if success:
            absence.notification_status = 'DISPATCHED'
        else:
            absence.notification_status = 'FAILED'
        self.db.flush()
        return success

    def retry_pending_notifications(self) -> int:
        pending = self.db.query(AbsenceRecord).filter(
            AbsenceRecord.notification_status.in_(['PENDING', 'FAILED']),
            AbsenceRecord.classification == 'UNREPORTED'
        ).all()

        count = 0
        for absence in pending:
            if self._dispatch_absence_alert(absence):
                count += 1
        self.db.commit()
        return count
