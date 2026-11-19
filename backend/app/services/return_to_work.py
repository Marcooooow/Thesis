from sqlalchemy.orm import Session
from typing import Optional, Dict, Any
from datetime import datetime, timezone, timedelta
import uuid

from ..models import ReturnToWorkCheckin, AbsenceRecord, WorkSession, Profile, User, TeamMembership, Team
from ..schemas.absence import ReturnToWorkSubmit

class ReturnToWorkService:
    def __init__(self, db: Session):
        self.db = db

    def check_pending_rtw(self, profile_id: uuid.UUID) -> Optional[Dict[str, Any]]:
        latest_session = self.db.query(WorkSession).filter(
            WorkSession.profile_id == profile_id,
            WorkSession.ended_at.isnot(None)
        ).order_by(WorkSession.ended_at.desc()).first()

        if not latest_session:
            return None

        existing_rtw = self.db.query(ReturnToWorkCheckin).filter(
            ReturnToWorkCheckin.work_session_id == latest_session.id
        ).first()

        if existing_rtw:
            return None

        absence = self.db.query(AbsenceRecord).filter(
            AbsenceRecord.profile_id == profile_id,
            AbsenceRecord.absence_date <= latest_session.ended_at.date()
        ).order_by(AbsenceRecord.absence_date.desc()).first()

        return {
            "work_session_id": latest_session.id,
            "absence_record_id": absence.id if absence else None,
            "session_ended_at": latest_session.ended_at
        }

    def submit_rtw(self, profile_id: uuid.UUID, work_session_id: uuid.UUID, data: ReturnToWorkSubmit) -> ReturnToWorkCheckin:
        session = self.db.query(WorkSession).filter(
            WorkSession.id == work_session_id,
            WorkSession.profile_id == profile_id
        ).first()
        if not session:
            raise ValueError("Work session not found or unauthorized")

        existing = self.db.query(ReturnToWorkCheckin).filter(
            ReturnToWorkCheckin.work_session_id == work_session_id
        ).first()
        if existing:
            raise ValueError("Return to work check-in already submitted for this session")

        rtw = ReturnToWorkCheckin(
            profile_id=profile_id,
            work_session_id=work_session_id,
            absence_record_id=data.absence_record_id,
            absence_reason_category=data.absence_reason_category,
            overall_feeling=data.overall_feeling,
            workload_concern=data.workload_concern,
            stress_concern=data.stress_concern,
            work_contributed_to_absence=data.work_contributed_to_absence,
            wants_manager_support=data.wants_manager_support,
            additional_comments=data.additional_comments,
            is_manager_visible=data.is_manager_visible
        )
        self.db.add(rtw)
        self.db.commit()
        self.db.refresh(rtw)
        return rtw

    def get_rtw_for_employee(self, profile_id: uuid.UUID) -> Optional[ReturnToWorkCheckin]:
        return self.db.query(ReturnToWorkCheckin).filter(
            ReturnToWorkCheckin.profile_id == profile_id
        ).order_by(ReturnToWorkCheckin.submitted_at.desc()).first()

    def get_rtw_for_manager(self, manager_user_id: uuid.UUID, checkin_id: uuid.UUID) -> Optional[Dict[str, Any]]:
        checkin = self.db.query(ReturnToWorkCheckin).filter(ReturnToWorkCheckin.id == checkin_id).first()
        if not checkin:
            return None

        if not self._verify_manager_access(manager_user_id, checkin.profile_id):
            raise ValueError("Unauthorized access to return-to-work wellbeing response")

        return {
            "id": checkin.id,
            "profile_id": checkin.profile_id,
            "absence_reason_category": checkin.absence_reason_category if checkin.is_manager_visible else None,
            "wants_manager_support": checkin.wants_manager_support,
            "submitted_at": checkin.submitted_at
        }

    def get_rtw_for_admin(self, admin_user_id: uuid.UUID, checkin_id: uuid.UUID) -> Optional[Dict[str, Any]]:
        checkin = self.db.query(ReturnToWorkCheckin).filter(ReturnToWorkCheckin.id == checkin_id).first()
        if not checkin:
            return None

        admin_user = self.db.query(User).filter(User.id == admin_user_id).first()
        if not admin_user or (admin_user.role != 'ADMIN' and admin_user.account_type != 'enterprise_admin'):
            raise ValueError("Unauthorized admin access")

        return {
            "id": checkin.id,
            "profile_id": checkin.profile_id,
            "absence_reason_category": checkin.absence_reason_category if checkin.is_manager_visible else None,
            "wants_manager_support": checkin.wants_manager_support,
            "submitted_at": checkin.submitted_at
        }

    def _verify_manager_access(self, manager_user_id: uuid.UUID, profile_id: uuid.UUID) -> bool:
        managed_teams = self.db.query(Team.id).filter(Team.manager_user_id == manager_user_id).all()
        team_ids = [t[0] for t in managed_teams]
        if not team_ids:
            return False

        membership = self.db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(team_ids),
            TeamMembership.profile_id == profile_id,
            TeamMembership.left_at.is_(None)
        ).first()

        return membership is not None
