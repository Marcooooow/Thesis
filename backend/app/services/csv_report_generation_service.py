import io
import zipfile
import csv
import uuid
from typing import Optional
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from ..models import (
    User, Profile, TeamMembership, Team, WorkSession, Break,
    Task, SessionWellbeingCheckin, RecommendationFeedback
)
from ..auth.security import should_include_test_data
from .team_analytics_service import compute_team_analytics


class CsvReportGenerationService:
    """
    Reusable CSV report generation service producing a ZIP archive containing
    multiple section-specific CSV files (Executive Summary, Productivity,
    Work Sessions, Break Analysis, Wellbeing, and Recommendations).
    Enforces RBAC, profile isolation, employee privacy thresholds, and formula injection safety.
    """

    def __init__(self, db: Session):
        self.db = db

    def _sanitize(self, val):
        if val is None:
            return ""
        s = str(val)
        # Formula injection protection: prepend single quote if starts with dangerous chars
        if s and s[0] in ('=', '+', '-', '@'):
            return f"'{s}"
        return s

    def generate_csv_zip(
        self,
        current_user: User,
        team_id: Optional[uuid.UUID] = None,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
        report_type: Optional[str] = None
    ) -> bytes:
        role_report_type = {"EMPLOYEE": "employee", "MANAGER": "manager", "ADMIN": "admin"}.get(current_user.role)
        if role_report_type is None:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unsupported report role")
        if report_type is not None and report_type != role_report_type:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this report type")
        target_report_type = role_report_type

        is_employee_report = (target_report_type == "employee")
        is_manager_report = (target_report_type == "manager")
        is_admin_report = (target_report_type == "admin")
        is_manager_or_admin = current_user.role in ["MANAGER", "ADMIN"]

        analytics = compute_team_analytics(self.db, current_user, team_id=team_id, start_date=start_date, end_date=end_date)
        profile_ids = analytics["profile_ids"]
        if is_manager_or_admin and len(profile_ids) < 5:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not enough people to show this safely. Team exports require at least 5 authorized employees.")
        total_employees = analytics["total_employees"]
        sessions = analytics["sessions"]
        total_work_hours = analytics["total_work_hours"]
        total_break_hours = analytics["total_break_hours"]
        avg_hours_per_emp = analytics["avg_hours_per_emp"]
        tasks = analytics["tasks"]
        total_tasks = analytics["total_tasks"]
        completed_tasks = analytics["completed_tasks"]
        completion_rate = analytics["completion_rate"]
        feedback = analytics["feedback"]
        total_recs = analytics["total_recs"]
        accepted_recs = analytics["accepted_recs"]
        dismissed_recs = analytics["dismissed_recs"]
        acceptance_rate = analytics["acceptance_rate"]
        start_date = analytics["start_date"] or (date.today() - timedelta(days=30))
        end_date = analytics["end_date"]
        start_dt = datetime.combine(start_date, datetime.min.time(), tzinfo=timezone.utc)
        end_dt = datetime.combine(end_date, datetime.max.time(), tzinfo=timezone.utc)

        # Gather metrics
        total_employees = len(profile_ids)
        sessions = self.db.query(WorkSession).filter(
            WorkSession.profile_id.in_(profile_ids),
            WorkSession.started_at >= start_dt,
            WorkSession.started_at <= end_dt
        ).all() if profile_ids else []

        total_work_secs = 0.0
        total_break_secs = 0.0
        session_count = len(sessions)
        for s in sessions:
            s_end = s.ended_at or datetime.now(timezone.utc)
            total_work_secs += max(0, (s_end - s.started_at).total_seconds())
            breaks = self.db.query(Break).filter(Break.work_session_id == s.id, Break.ended_at.isnot(None)).all()
            for b in breaks:
                total_break_secs += max(0, (b.ended_at - b.started_at).total_seconds())

        total_work_hours = round(total_work_secs / 3600.0, 2)
        total_break_hours = round(total_break_secs / 3600.0, 2)
        avg_hours_per_emp = round(total_work_hours / max(1, total_employees), 2)

        tasks = self.db.query(Task).filter(
            Task.profile_id.in_(profile_ids),
            Task.created_at >= start_dt,
            Task.created_at <= end_dt
        ).all() if profile_ids else []
        total_tasks = len(tasks)
        completed_tasks = len([t for t in tasks if t.status == 'DONE'])
        completion_rate = round((completed_tasks / total_tasks * 100.0) if total_tasks > 0 else 0.0, 1)

        feedback = self.db.query(RecommendationFeedback).join(User, RecommendationFeedback.user_id == User.id).join(Profile, User.id == Profile.user_id).filter(
            Profile.id.in_(profile_ids),
            RecommendationFeedback.timestamp >= start_dt,
            RecommendationFeedback.timestamp <= end_dt
        ).all() if profile_ids else []
        total_recs = len(feedback)
        accepted_recs = len([f for f in feedback if f.user_action == 'accepted'])
        acceptance_rate = round((accepted_recs / total_recs * 100.0) if total_recs > 0 else 0.0, 1)

        # Wellbeing check-ins (privacy threshold >= 5)
        user_ids_from_profiles = [p.user_id for p in self.db.query(Profile).filter(Profile.id.in_(profile_ids)).all()] if profile_ids else []
        checkins = []
        if total_employees >= 5 or not is_manager_or_admin:
            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.user_id.in_(user_ids_from_profiles),
                SessionWellbeingCheckin.created_at >= start_dt,
                SessionWellbeingCheckin.created_at <= end_dt
            ).all() if user_ids_from_profiles else []

        avg_ow = round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2) if checkins else 0.0
        avg_mf = round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2) if checkins else 0.0
        avg_wm = round(sum(c.workload_manageability for c in checkins) / len(checkins), 2) if checkins else 0.0
        avg_pf = round(sum(c.perceived_focus for c in checkins) / len(checkins), 2) if checkins else 0.0
        avg_br = round(sum(c.break_recovery for c in checkins) / len(checkins), 2) if checkins else 0.0

        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
            # 1. Executive Summary CSV
            exec_io = io.StringIO()
            exec_writer = csv.writer(exec_io)
            exec_writer.writerow(["Metric", "Value"])
            exec_writer.writerow(["Monitored Employees", total_employees])
            exec_writer.writerow(["Total Work Sessions", session_count])
            exec_writer.writerow(["Total Work Hours", total_work_hours])
            exec_writer.writerow(["Total Break Hours", total_break_hours])
            exec_writer.writerow(["Average Work Hours / Employee", avg_hours_per_emp])
            exec_writer.writerow(["Total Tasks Created", total_tasks])
            exec_writer.writerow(["Completed Tasks", completed_tasks])
            exec_writer.writerow(["Task Completion Rate (%)", completion_rate])
            exec_writer.writerow(["Recommendation Feedback Count", total_recs])
            exec_writer.writerow(["Recommendation Acceptance Rate (%)", acceptance_rate])
            zip_file.writestr("executive_summary.csv", exec_io.getvalue().encode('utf-8-sig'))

            # 2. Productivity CSV
            prod_io = io.StringIO()
            prod_writer = csv.writer(prod_io)
            prod_writer.writerow(["Task ID", "Profile ID", "Title", "Status", "Priority", "Category", "Est. Minutes", "Actual Minutes", "Deadline"])
            for t in tasks:
                prod_writer.writerow([
                    str(t.id), str(t.profile_id), self._sanitize(t.title), t.status, t.priority,
                    self._sanitize(t.category or 'General'), t.estimated_minutes or 0, t.actual_minutes or 0,
                    str(t.deadline) if t.deadline else 'None'
                ])
            zip_file.writestr("productivity.csv", prod_io.getvalue().encode('utf-8-sig'))

            # 3. Work Sessions CSV
            sess_io = io.StringIO()
            sess_writer = csv.writer(sess_io)
            sess_writer.writerow(["Session ID", "Profile ID", "Started At", "Ended At", "Duration (Hours)", "Status"])
            for s in sessions:
                s_end = s.ended_at or datetime.now(timezone.utc)
                duration_hrs = round((s_end - s.started_at).total_seconds() / 3600.0, 2)
                status_str = "Completed" if s.ended_at else "Active"
                sess_writer.writerow([
                    str(s.id), str(s.profile_id), str(s.started_at),
                    str(s.ended_at) if s.ended_at else "Ongoing", duration_hrs, status_str
                ])
            zip_file.writestr("work_sessions.csv", sess_io.getvalue().encode('utf-8-sig'))

            # 4. Break Analysis CSV
            break_io = io.StringIO()
            break_writer = csv.writer(break_io)
            break_writer.writerow(["Break ID", "Session ID", "Break Type", "Started At", "Ended At", "Duration (Minutes)", "Notes"])
            all_breaks = []
            if sessions:
                session_ids = [s.id for s in sessions]
                all_breaks = self.db.query(Break).filter(Break.work_session_id.in_(session_ids)).all()
            for b in all_breaks:
                b_end = b.ended_at or datetime.now(timezone.utc)
                duration_mins = round((b_end - b.started_at).total_seconds() / 60.0, 1)
                break_writer.writerow([
                    str(b.id), str(b.work_session_id), b.break_type, str(b.started_at),
                    str(b.ended_at) if b.ended_at else "Ongoing", duration_mins, self._sanitize(b.notes or "")
                ])
            zip_file.writestr("break_analysis.csv", break_io.getvalue().encode('utf-8-sig'))

            # 5. Wellbeing CSV
            wb_io = io.StringIO()
            wb_writer = csv.writer(wb_io)
            if is_manager_or_admin and total_employees < 5:
                wb_writer.writerow(["Notice", "Team analytics withheld: not enough people to show this safely; at least 5 non-test employees are required."])
            else:
                wb_writer.writerow(["Wellbeing Metric", "Average Score (1-5 Scale)", "Total Check-ins"])
                wb_writer.writerow(["Overall Wellbeing", avg_ow, len(checkins)])
                wb_writer.writerow(["Mental Fatigue", avg_mf, len(checkins)])
                wb_writer.writerow(["Workload Manageability", avg_wm, len(checkins)])
                wb_writer.writerow(["Perceived Focus", avg_pf, len(checkins)])
                wb_writer.writerow(["Break Recovery", avg_br, len(checkins)])
            zip_file.writestr("wellbeing.csv", wb_io.getvalue().encode('utf-8-sig'))

            # 6. Recommendations CSV
            rec_io = io.StringIO()
            rec_writer = csv.writer(rec_io)
            rec_writer.writerow(["Timestamp", "Recommendation Type", "Model Version", "Score", "User Action", "Post-Break Delta"])
            for f in feedback:
                rec_writer.writerow([
                    str(f.timestamp), f.recommendation_type, f.model_version,
                    f.recommendation_score, f.user_action or "No Action",
                    f.post_break_productivity_delta if f.post_break_productivity_delta is not None else "N/A"
                ])
            zip_file.writestr("recommendations.csv", rec_io.getvalue().encode('utf-8-sig'))

        zip_buffer.seek(0)
        return zip_buffer.getvalue()
