from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date, datetime, timezone
import uuid

from ..models import LeaveRequest, LeaveType, Profile, User, AbsenceRecord, TeamMembership, Team
from .notification_dispatch_service import NotificationDispatchService

class LeaveService:
    def __init__(self, db: Session):
        self.db = db

    def submit_request(self, profile_id: uuid.UUID, leave_type_id: uuid.UUID, start_date: date, end_date: date, reason: Optional[str]) -> LeaveRequest:
        if start_date > end_date:
            raise ValueError("start_date cannot be after end_date")

        leave_req = LeaveRequest(
            profile_id=profile_id,
            leave_type_id=leave_type_id,
            start_date=start_date,
            end_date=end_date,
            reason=reason,
            status='PENDING'
        )
        self.db.add(leave_req)
        self.db.flush()

        profile = self.db.query(Profile).filter(Profile.id == profile_id).first()
        if profile and profile.team_memberships:
            for tm in profile.team_memberships:
                if tm.team and tm.team.manager_user_id and tm.left_at is None:
                    manager_user = self.db.query(User).filter(User.id == tm.team.manager_user_id).first()
                    if manager_user:
                        NotificationDispatchService.dispatch(
                            db=self.db,
                            recipient_user_id=manager_user.id,
                            title="New Leave Request",
                            message=f"A leave request has been submitted from {start_date} to {end_date}.",
                            notification_type="LEAVE_REQUEST",
                            idempotency_key=f"leave-req-{leave_req.id}-{manager_user.id}",
                            related_entity_id=leave_req.id
                        )

        self.db.commit()
        self.db.refresh(leave_req)
        return leave_req

    def get_for_profile(self, profile_id: uuid.UUID) -> List[LeaveRequest]:
        return self.db.query(LeaveRequest).filter(LeaveRequest.profile_id == profile_id).all()

    def get_pending_for_manager(self, manager_user_id: uuid.UUID) -> List[LeaveRequest]:
        managed_teams = self.db.query(Team.id).filter(Team.manager_user_id == manager_user_id).all()
        team_ids = [t[0] for t in managed_teams]
        if not team_ids:
            return []

        profile_ids = self.db.query(TeamMembership.profile_id).filter(
            TeamMembership.team_id.in_(team_ids),
            TeamMembership.left_at.is_(None)
        ).all()
        p_ids = [p[0] for p in profile_ids]
        if not p_ids:
            return []

        return self.db.query(LeaveRequest).filter(
            LeaveRequest.profile_id.in_(p_ids),
            LeaveRequest.status == 'PENDING'
        ).all()

    def review_request(self, request_id: uuid.UUID, reviewer_user_id: uuid.UUID, approve: bool, reviewer_note: Optional[str]) -> LeaveRequest:
        leave_req = self.db.query(LeaveRequest).filter(LeaveRequest.id == request_id).first()
        if not leave_req:
            raise ValueError("Leave request not found")

        employee_profile = self.db.query(Profile).filter(Profile.id == leave_req.profile_id).first()
        if employee_profile and employee_profile.user_id == reviewer_user_id:
            raise ValueError("Employees cannot approve or reject their own leave requests")

        reviewer_user = self.db.query(User).filter(User.id == reviewer_user_id).first()
        if not reviewer_user:
            raise ValueError("Reviewer user not found")

        leave_req.status = 'APPROVED' if approve else 'REJECTED'
        leave_req.reviewed_by = reviewer_user_id
        leave_req.reviewed_at = datetime.now(timezone.utc)
        leave_req.reviewer_note = reviewer_note
        leave_req.updated_at = datetime.now(timezone.utc)

        if approve:
            self._suppress_absences_for_approved_leave(leave_req)

        if employee_profile:
            notif_type = "LEAVE_APPROVED" if approve else "LEAVE_REJECTED"
            NotificationDispatchService.dispatch(
                db=self.db,
                recipient_user_id=employee_profile.user_id,
                title=f"Leave Request {'Approved' if approve else 'Rejected'}",
                message=f"Your leave request from {leave_req.start_date} to {leave_req.end_date} has been {leave_req.status.lower()}.",
                notification_type=notif_type,
                idempotency_key=f"leave-review-{leave_req.id}",
                related_entity_id=leave_req.id
            )

        self.db.commit()
        self.db.refresh(leave_req)
        return leave_req

    def cancel_request(self, request_id: uuid.UUID, profile_id: uuid.UUID) -> LeaveRequest:
        leave_req = self.db.query(LeaveRequest).filter(
            LeaveRequest.id == request_id,
            LeaveRequest.profile_id == profile_id
        ).first()
        if not leave_req:
            raise ValueError("Leave request not found or unauthorized")

        if leave_req.status != 'PENDING':
            raise ValueError("Only pending leave requests can be cancelled")

        leave_req.status = 'CANCELLED'
        leave_req.updated_at = datetime.now(timezone.utc)
        self.db.commit()
        self.db.refresh(leave_req)
        return leave_req

    def _suppress_absences_for_approved_leave(self, leave_request: LeaveRequest) -> None:
        absences = self.db.query(AbsenceRecord).filter(
            AbsenceRecord.profile_id == leave_request.profile_id,
            AbsenceRecord.absence_date >= leave_request.start_date,
            AbsenceRecord.absence_date <= leave_request.end_date
        ).all()

        for abs_rec in absences:
            abs_rec.classification = 'LEAVE_APPROVED'
            abs_rec.leave_request_id = leave_request.id
            abs_rec.updated_at = datetime.now(timezone.utc)
        self.db.flush()
