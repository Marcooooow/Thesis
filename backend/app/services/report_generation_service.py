import io
import uuid
from typing import Optional
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from fastapi import HTTPException, status
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

from ..models import (
    User, Profile, TeamMembership, Team, WorkSession, Break,
    Task, SessionWellbeingCheckin, RecommendationFeedback
)
from ..auth.security import should_include_test_data
from .team_analytics_service import compute_team_analytics

class ReportGenerationService:
    """
    Reusable Excel report generation service using openpyxl.
    Produces multi-sheet workbooks with Executive Summary, Productivity,
    Work Sessions, Break Analysis, Wellbeing, and Recommendations sheets.
    Enforces RBAC, is_test_data isolation, and employee privacy thresholds.
    """

    def __init__(self, db: Session):
        self.db = db

    def generate_excel_report(
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

        wb = openpyxl.Workbook()
        # Remove default sheet
        default_sheet = wb.active

        # Styling constants
        header_fill = PatternFill(start_color="1E293B", end_color="1E293B", fill_type="solid")
        header_font = Font(name="Segoe UI", size=11, bold=True, color="FFFFFF")
        title_font = Font(name="Segoe UI", size=16, bold=True, color="1E293B")
        subtitle_font = Font(name="Segoe UI", size=11, italic=True, color="64748B")
        regular_font = Font(name="Segoe UI", size=10)
        bold_font = Font(name="Segoe UI", size=10, bold=True)
        zebra_fill = PatternFill(start_color="F8FAFC", end_color="F8FAFC", fill_type="solid")
        thin_border = Border(
            left=Side(style='thin', color='CBD5E1'),
            right=Side(style='thin', color='CBD5E1'),
            top=Side(style='thin', color='CBD5E1'),
            bottom=Side(style='thin', color='CBD5E1')
        )

        def style_header_row(ws, row_idx, headers):
            for col_idx, h in enumerate(headers, 1):
                cell = ws.cell(row=row_idx, column=col_idx, value=h)
                cell.fill = header_fill
                cell.font = header_font
                cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
                cell.border = thin_border
            ws.row_dimensions[row_idx].height = 24

        def auto_fit_columns(ws):
            ws.views.sheetView[0].showGridLines = True
            for col in ws.columns:
                max_len = 0
                col_letter = get_column_letter(col[0].column)
                for cell in col:
                    val_str = str(cell.value or '')
                    if len(val_str) > max_len:
                        max_len = len(val_str)
                ws.column_dimensions[col_letter].width = max(max_len + 4, 12)

        # ----------------------------------------------------
        # 1. Executive Summary Sheet
        # ----------------------------------------------------
        ws_exec = wb.create_sheet(title="Executive Summary")
        excel_title = (
            "IntelliBreak Employee Analytics Report" if is_employee_report else
            ("IntelliBreak Manager Analytics Report" if is_manager_report else "IntelliBreak Executive Analytics Report")
        )
        ws_exec.cell(row=1, column=1, value=excel_title).font = title_font
        ws_exec.cell(row=2, column=1, value=f"Period: {start_date} to {end_date} | Generated: {date.today()}").font = subtitle_font

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

        summary_rows = [
            ("Monitored Employees", total_employees),
            ("Total Work Sessions", session_count),
            ("Total Work Hours", total_work_hours),
            ("Total Break Hours", total_break_hours),
            ("Average Work Hours / Employee", avg_hours_per_emp),
            ("Total Tasks Created", total_tasks),
            ("Completed Tasks", completed_tasks),
            ("Task Completion Rate (%)", completion_rate),
            ("Recommendation Feedback Count", total_recs),
            ("Recommendation Acceptance Rate (%)", acceptance_rate),
        ]

        style_header_row(ws_exec, 4, ["Metric", "Value"])
        for idx, (metric, val) in enumerate(summary_rows, 5):
            c1 = ws_exec.cell(row=idx, column=1, value=metric)
            c2 = ws_exec.cell(row=idx, column=2, value=val)
            c1.font = regular_font
            c2.font = bold_font
            c1.border = thin_border
            c2.border = thin_border
            if idx % 2 == 0:
                c1.fill = zebra_fill
                c2.fill = zebra_fill
        auto_fit_columns(ws_exec)

        # ----------------------------------------------------
        # 2. Productivity Sheet
        # ----------------------------------------------------
        ws_prod = wb.create_sheet(title="Productivity")
        ws_prod.cell(row=1, column=1, value="Task Productivity Breakdown").font = title_font
        style_header_row(ws_prod, 3, ["Task ID", "Profile ID", "Title", "Status", "Priority", "Category", "Est. Minutes", "Actual Minutes", "Deadline"])

        for idx, t in enumerate(tasks, 4):
            row_vals = [
                str(t.id), str(t.profile_id), t.title, t.status, t.priority,
                t.category or 'General', t.estimated_minutes or 0, t.actual_minutes or 0,
                str(t.deadline) if t.deadline else 'None'
            ]
            for col_idx, val in enumerate(row_vals, 1):
                cell = ws_prod.cell(row=idx, column=col_idx, value=val)
                cell.font = regular_font
                cell.border = thin_border
                if idx % 2 == 0:
                    cell.fill = zebra_fill
        ws_prod.freeze_panes = 'A4'
        auto_fit_columns(ws_prod)

        # ----------------------------------------------------
        # 3. Work Sessions Sheet
        # ----------------------------------------------------
        ws_sessions = wb.create_sheet(title="Work Sessions")
        ws_sessions.cell(row=1, column=1, value="Work Sessions & Shifts").font = title_font
        style_header_row(ws_sessions, 3, ["Session ID", "Profile ID", "Started At", "Ended At", "Duration (Hours)", "Status"])

        for idx, s in enumerate(sessions, 4):
            s_end = s.ended_at or datetime.now(timezone.utc)
            duration_hrs = round((s_end - s.started_at).total_seconds() / 3600.0, 2)
            status_str = "Completed" if s.ended_at else "Active"
            row_vals = [
                str(s.id), str(s.profile_id), str(s.started_at),
                str(s.ended_at) if s.ended_at else "Ongoing", duration_hrs, status_str
            ]
            for col_idx, val in enumerate(row_vals, 1):
                cell = ws_sessions.cell(row=idx, column=col_idx, value=val)
                cell.font = regular_font
                cell.border = thin_border
                if idx % 2 == 0:
                    cell.fill = zebra_fill
        ws_sessions.freeze_panes = 'A4'
        auto_fit_columns(ws_sessions)

        # ----------------------------------------------------
        # 4. Break Analysis Sheet
        # ----------------------------------------------------
        ws_breaks = wb.create_sheet(title="Break Analysis")
        ws_breaks.cell(row=1, column=1, value="Break & Recovery Analysis").font = title_font
        style_header_row(ws_breaks, 3, ["Break ID", "Session ID", "Break Type", "Started At", "Ended At", "Duration (Minutes)", "Notes"])

        all_breaks = []
        if sessions:
            session_ids = [s.id for s in sessions]
            all_breaks = self.db.query(Break).filter(Break.work_session_id.in_(session_ids)).all()

        for idx, b in enumerate(all_breaks, 4):
            b_end = b.ended_at or datetime.now(timezone.utc)
            duration_mins = round((b_end - b.started_at).total_seconds() / 60.0, 1)
            row_vals = [
                str(b.id), str(b.work_session_id), b.break_type, str(b.started_at),
                str(b.ended_at) if b.ended_at else "Ongoing", duration_mins, b.notes or ""
            ]
            for col_idx, val in enumerate(row_vals, 1):
                cell = ws_breaks.cell(row=idx, column=col_idx, value=val)
                cell.font = regular_font
                cell.border = thin_border
                if idx % 2 == 0:
                    cell.fill = zebra_fill
        ws_breaks.freeze_panes = 'A4'
        auto_fit_columns(ws_breaks)

        # ----------------------------------------------------
        # 5. Wellbeing Sheet (Enforcing >=3 employees privacy threshold)
        # ----------------------------------------------------
        ws_wellbeing = wb.create_sheet(title="Wellbeing")
        ws_wellbeing.cell(row=1, column=1, value="Wellbeing Monitoring Aggregates").font = title_font

        user_ids_from_profiles = [p.user_id for p in self.db.query(Profile).filter(Profile.id.in_(profile_ids)).all()] if profile_ids else []

        if len(profile_ids) < 5 and is_manager_or_admin:
            ws_wellbeing.cell(row=3, column=1, value="Team analytics withheld: not enough people to show this safely; at least 5 non-test employees are required.").font = subtitle_font
        else:
            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.user_id.in_(user_ids_from_profiles),
                SessionWellbeingCheckin.created_at >= start_dt,
                SessionWellbeingCheckin.created_at <= end_dt
            ).all() if user_ids_from_profiles else []

            if checkins:
                avg_ow = round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2)
                avg_mf = round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2)
                avg_wm = round(sum(c.workload_manageability for c in checkins) / len(checkins), 2)
                avg_pf = round(sum(c.perceived_focus for c in checkins) / len(checkins), 2)
                avg_br = round(sum(c.break_recovery for c in checkins) / len(checkins), 2)
            else:
                avg_ow = avg_mf = avg_wm = avg_pf = avg_br = 0.0

            style_header_row(ws_wellbeing, 3, ["Wellbeing Metric", "Average Score (1-5 Scale)", "Total Check-ins"])
            wb_metrics = [
                ("Overall Wellbeing", avg_ow),
                ("Mental Fatigue", avg_mf),
                ("Workload Manageability", avg_wm),
                ("Perceived Focus", avg_pf),
                ("Break Recovery", avg_br),
            ]
            for idx, (m_name, m_val) in enumerate(wb_metrics, 4):
                c1 = ws_wellbeing.cell(row=idx, column=1, value=m_name)
                c2 = ws_wellbeing.cell(row=idx, column=2, value=m_val)
                c3 = ws_wellbeing.cell(row=idx, column=3, value=len(checkins))
                c1.font = regular_font
                c2.font = bold_font
                c3.font = regular_font
                c1.border = thin_border
                c2.border = thin_border
                c3.border = thin_border
                if idx % 2 == 0:
                    c1.fill = zebra_fill
                    c2.fill = zebra_fill
                    c3.fill = zebra_fill
        auto_fit_columns(ws_wellbeing)

        # ----------------------------------------------------
        # 6. Recommendations Sheet
        # ----------------------------------------------------
        ws_recs = wb.create_sheet(title="Recommendations")
        ws_recs.cell(row=1, column=1, value="Recommendation & Feedback Audit Log").font = title_font
        style_header_row(ws_recs, 3, ["Timestamp", "Recommendation Type", "Model Version", "Score", "User Action", "Post-Break Delta"])

        for idx, f in enumerate(feedback, 4):
            row_vals = [
                str(f.timestamp), f.recommendation_type, f.model_version,
                f.recommendation_score, f.user_action or "No Action",
                f.post_break_productivity_delta if f.post_break_productivity_delta is not None else "N/A"
            ]
            for col_idx, val in enumerate(row_vals, 1):
                cell = ws_recs.cell(row=idx, column=col_idx, value=val)
                cell.font = regular_font
                cell.border = thin_border
                if idx % 2 == 0:
                    cell.fill = zebra_fill
        ws_recs.freeze_panes = 'A4'
        auto_fit_columns(ws_recs)

        # Save to bytes buffer
        buffer = io.BytesIO()
        wb.save(buffer)
        buffer.seek(0)
        return buffer.getvalue()
