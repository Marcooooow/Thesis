import io
import uuid
from typing import Optional
from datetime import date, datetime, timezone, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

from ..models import (
    User, Profile, TeamMembership, Team, WorkSession, Break,
    Task, SessionWellbeingCheckin, RecommendationFeedback
)
from ..auth.security import should_include_test_data
from .team_analytics_service import compute_team_analytics
from .analytics_service import AnalyticsEngine


class NumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and render total page numbers
    along with professional running headers and footers.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_header_footer(num_pages)
            super().showPage()
        super().save()

    def draw_header_footer(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#64748B"))

        # Header
        self.drawString(54, letter[1] - 36, "IntelliBreak — Professional Analytics & Wellbeing Report")
        self.setStrokeColor(colors.HexColor("#CBD5E1"))
        self.setLineWidth(0.5)
        self.line(54, letter[1] - 42, letter[0] - 54, letter[1] - 42)

        # Footer
        self.line(54, 45, letter[0] - 54, 45)
        page_str = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(letter[0] - 54, 32, page_str)
        self.drawString(54, 32, "Confidential — IntelliBreak Sustainable Work Platform")
        self.restoreState()


class PdfReportGenerationService:
    """
    Reusable PDF report generation service using ReportLab.
    Mirrors the data scope, date filtering, RBAC, is_test_data isolation,
    and wellbeing privacy thresholds of the Excel report.
    """

    def __init__(self, db: Session):
        self.db = db

    def generate_pdf_report(
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
        session_count = analytics["session_count"]
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

        # Build PDF Document
        buffer = io.BytesIO()
        doc = SimpleDocTemplate(
            buffer,
            pagesize=letter,
            leftMargin=54,
            rightMargin=54,
            topMargin=54,
            bottomMargin=54
        )

        styles = getSampleStyleSheet()
        title_style = ParagraphStyle(
            'ReportTitle',
            parent=styles['Heading1'],
            fontName='Helvetica-Bold',
            fontSize=22,
            textColor=colors.HexColor('#1E293B'),
            spaceAfter=4
        )
        subtitle_style = ParagraphStyle(
            'ReportSubtitle',
            parent=styles['Normal'],
            fontName='Helvetica-Oblique',
            fontSize=10,
            textColor=colors.HexColor('#64748B'),
            spaceAfter=14
        )
        section_style = ParagraphStyle(
            'SectionHeading',
            parent=styles['Heading2'],
            fontName='Helvetica-Bold',
            fontSize=14,
            textColor=colors.HexColor('#0F172A'),
            spaceBefore=14,
            spaceAfter=6
        )
        body_style = ParagraphStyle(
            'ReportBody',
            parent=styles['Normal'],
            fontName='Helvetica',
            fontSize=10,
            textColor=colors.HexColor('#334155'),
            spaceAfter=6
        )
        table_cell_style = ParagraphStyle(
            'TableCell',
            parent=styles['Normal'],
            fontName='Helvetica',
            fontSize=9,
            textColor=colors.HexColor('#1E293B')
        )
        table_header_style = ParagraphStyle(
            'TableHeader',
            parent=styles['Normal'],
            fontName='Helvetica-Bold',
            fontSize=9,
            textColor=colors.white
        )

        story = []

        if is_employee_report:
            # Employee Analytics Report Generation
            profile = self.db.query(Profile).filter(Profile.user_id == current_user.id).first()
            profile_id = profile.id if profile else None

            sessions = self.db.query(WorkSession).filter(
                WorkSession.profile_id == profile_id,
                WorkSession.started_at >= start_dt,
                WorkSession.started_at <= end_dt
            ).order_by(WorkSession.started_at.desc()).all() if profile_id else []

            break_analysis = AnalyticsEngine.calculate_break_analysis(self.db, profile_id, start_dt, end_dt) if profile_id else {}

            total_worked_secs = 0.0
            total_focused_secs = 0.0
            total_shift_secs = 0.0
            for s in sessions:
                m = AnalyticsEngine.calculate_session_metrics(self.db, s)
                total_worked_secs += m["worked_seconds"]
                total_focused_secs += m["focused_seconds"]
                total_shift_secs += m["shift_duration_seconds"]

            overall_focus_rate = (total_focused_secs / total_worked_secs * 100.0) if total_worked_secs > 0 else 0.0
            worked_hours = round(total_worked_secs / 3600.0, 2)
            shift_hours = round(total_shift_secs / 3600.0, 2)
            break_hours = round(break_analysis.get("totalBreakSeconds", 0.0) / 3600.0, 2)

            tasks = self.db.query(Task).filter(
                Task.profile_id == profile_id,
                Task.created_at >= start_dt,
                Task.created_at <= end_dt
            ).all() if profile_id else []
            total_tasks = len(tasks)
            completed_tasks = len([t for t in tasks if t.status == 'DONE'])
            completion_rate = round((completed_tasks / total_tasks * 100.0) if total_tasks > 0 else 0.0, 1)

            checkins = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.user_id == current_user.id,
                SessionWellbeingCheckin.created_at >= start_dt,
                SessionWellbeingCheckin.created_at <= end_dt
            ).all()
            avg_ow = round(sum(c.overall_wellbeing for c in checkins) / len(checkins), 2) if checkins else 0.0
            avg_mf = round(sum(c.mental_fatigue for c in checkins) / len(checkins), 2) if checkins else 0.0
            avg_wm = round(sum(c.workload_manageability for c in checkins) / len(checkins), 2) if checkins else 0.0

            feedback = self.db.query(RecommendationFeedback).filter(
                RecommendationFeedback.user_id == current_user.id,
                RecommendationFeedback.timestamp >= start_dt,
                RecommendationFeedback.timestamp <= end_dt
            ).all()
            total_recs = len(feedback)
            accepted_recs = len([f for f in feedback if f.user_action == 'accepted'])
            dismissed_recs = len([f for f in feedback if f.user_action == 'dismissed'])
            acceptance_rate = round((accepted_recs / total_recs * 100.0) if total_recs > 0 else 0.0, 1)

            # Title & Subtitle
            story.append(Paragraph("IntelliBreak Employee Analytics Report", title_style))
            story.append(Paragraph(f"Employee: {current_user.email} | Reporting Period: {start_date} to {end_date} | Generated: {date.today()}", subtitle_style))
            story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#1E293B'), spaceAfter=12))

            # 1. Employee Information
            story.append(Paragraph("1. Employee Information", section_style))
            emp_info_data = [
                [Paragraph("<b>Attribute</b>", table_header_style), Paragraph("<b>Details</b>", table_header_style)],
                [Paragraph("Email / User", table_cell_style), Paragraph(current_user.email, table_cell_style)],
                [Paragraph("Role", table_cell_style), Paragraph(current_user.role, table_cell_style)],
                [Paragraph("Reporting Period", table_cell_style), Paragraph(f"{start_date} to {end_date}", table_cell_style)],
                [Paragraph("Target Daily Hours", table_cell_style), Paragraph(f"{profile.target_daily_hours if profile else 8.0} hrs", table_cell_style)],
            ]
            t_emp = Table(emp_info_data, colWidths=[200, 304])
            t_emp.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
            ]))
            story.append(t_emp)
            story.append(Spacer(1, 10))

            # 2. Personal Performance Summary
            story.append(Paragraph("2. Personal Performance Summary", section_style))
            perf_data = [
                [Paragraph("<b>Metric</b>", table_header_style), Paragraph("<b>Value</b>", table_header_style)],
                [Paragraph("Total Completed Sessions", table_cell_style), Paragraph(str(len(sessions)), table_cell_style)],
                [Paragraph("Total Worked Hours", table_cell_style), Paragraph(f"{worked_hours} hrs", table_cell_style)],
                [Paragraph("Total Break Hours", table_cell_style), Paragraph(f"{break_hours} hrs", table_cell_style)],
                [Paragraph("Shift Duration Hours", table_cell_style), Paragraph(f"{shift_hours} hrs", table_cell_style)],
                [Paragraph("Overall Focus Rate", table_cell_style), Paragraph(f"{overall_focus_rate:.1f}%", table_cell_style)],
                [Paragraph("Task Completion Rate", table_cell_style), Paragraph(f"{completion_rate}% ({completed_tasks}/{total_tasks})", table_cell_style)],
            ]
            t_perf = Table(perf_data, colWidths=[250, 254])
            t_perf.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
            ]))
            story.append(t_perf)
            story.append(Spacer(1, 10))

            # 3. Work Session History
            story.append(Paragraph("3. Work Session History", section_style))
            if not sessions:
                story.append(Paragraph("<i>No work sessions recorded for this period.</i>", body_style))
            else:
                sess_table_data = [
                    [Paragraph("<b>Date / Started</b>", table_header_style), Paragraph("<b>Duration</b>", table_header_style), Paragraph("<b>Worked</b>", table_header_style), Paragraph("<b>Focus Rate</b>", table_header_style)]
                ]
                for s in sessions[:15]:
                    m = AnalyticsEngine.calculate_session_metrics(self.db, s)
                    st_str = s.started_at.strftime('%Y-%m-%d %H:%M') if s.started_at else 'N/A'
                    dur_str = f"{m['shift_duration_seconds'] / 3600.0:.1f}h"
                    wrk_str = f"{m['worked_seconds'] / 3600.0:.1f}h"
                    fr_str = f"{m['focus_rate']:.0f}%"
                    sess_table_data.append([
                        Paragraph(st_str, table_cell_style),
                        Paragraph(dur_str, table_cell_style),
                        Paragraph(wrk_str, table_cell_style),
                        Paragraph(fr_str, table_cell_style),
                    ])
                t_sess = Table(sess_table_data, colWidths=[150, 100, 100, 154])
                t_sess.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
                ]))
                story.append(t_sess)
            story.append(Spacer(1, 10))

            # 4. Break Analytics
            story.append(Paragraph("4. Break Analytics", section_style))
            break_count = break_analysis.get("totalBreaks", 0)
            break_total_secs = break_analysis.get("totalBreakSeconds", 0.0)
            avg_break_secs = break_analysis.get("avgBreakDurationSeconds", 0.0)
            break_text = f"Recorded <b>{break_count}</b> total breaks totaling <b>{break_total_secs / 60.0:.1f} minutes</b> (average duration: <b>{avg_break_secs / 60.0:.1f} min</b> per break)."
            story.append(Paragraph(break_text, body_style))
            by_type = break_analysis.get("byType", {})
            if by_type:
                bt_data = [[Paragraph("<b>Break Type</b>", table_header_style), Paragraph("<b>Count</b>", table_header_style), Paragraph("<b>Total Duration</b>", table_header_style)]]
                for k, v in by_type.items():
                    bt_data.append([
                        Paragraph(k, table_cell_style),
                        Paragraph(str(v["count"]), table_cell_style),
                        Paragraph(f"{v['totalSeconds'] / 60.0:.1f} min", table_cell_style)
                    ])
                t_bt = Table(bt_data, colWidths=[200, 100, 204])
                t_bt.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
                ]))
                story.append(Spacer(1, 4))
                story.append(t_bt)
            story.append(Spacer(1, 10))

            # 5. Focus and Productivity Analysis
            story.append(Paragraph("5. Focus and Productivity Analysis", section_style))
            story.append(Paragraph(f"Your overall focus efficiency is <b>{overall_focus_rate:.1f}%</b> across active work sessions. Task completion rate stands at <b>{completion_rate}%</b> ({completed_tasks} of {total_tasks} completed).", body_style))
            story.append(Spacer(1, 10))

            # 6. Personal Wellbeing
            story.append(Paragraph("6. Personal Wellbeing Summary", section_style))
            if not checkins:
                story.append(Paragraph("<i>No personal wellbeing check-in records found for this period.</i>", body_style))
            else:
                wb_data = [
                    [Paragraph("<b>Wellbeing Indicator</b>", table_header_style), Paragraph("<b>Your Average Score (1–5 Scale)</b>", table_header_style)],
                    [Paragraph("Overall Wellbeing", table_cell_style), Paragraph(str(avg_ow), table_cell_style)],
                    [Paragraph("Mental Fatigue", table_cell_style), Paragraph(str(avg_mf), table_cell_style)],
                    [Paragraph("Workload Manageability", table_cell_style), Paragraph(str(avg_wm), table_cell_style)],
                ]
                t_wb = Table(wb_data, colWidths=[250, 254])
                t_wb.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
                ]))
                story.append(t_wb)
            story.append(Spacer(1, 10))

            # 7. Personal Recommendation History
            story.append(Paragraph("7. Personal Recommendation History", section_style))
            rec_text = f"Received <b>{total_recs}</b> break/wellness recommendations, with <b>{accepted_recs}</b> accepted and <b>{dismissed_recs}</b> dismissed (<b>{acceptance_rate}%</b> acceptance rate)."
            story.append(Paragraph(rec_text, body_style))

        else:
            # Manager / Admin Report Generation
            mgr_report_title = "IntelliBreak Manager Analytics Report" if is_manager_report else "IntelliBreak Executive Analytics Report"
            story.append(Paragraph(mgr_report_title, title_style))
            story.append(Paragraph(f"Reporting Period: {start_date} to {end_date} | Generated: {date.today()}", subtitle_style))
            story.append(HRFlowable(width="100%", thickness=1.5, color=colors.HexColor('#1E293B'), spaceAfter=12))

            # Executive Summary Section
            story.append(Paragraph("1. Executive Summary", section_style))
            summary_data = [
                [Paragraph("<b>Metric</b>", table_header_style), Paragraph("<b>Value</b>", table_header_style)],
                [Paragraph("Monitored Employees", table_cell_style), Paragraph(str(total_employees), table_cell_style)],
                [Paragraph("Total Work Sessions", table_cell_style), Paragraph(str(session_count), table_cell_style)],
                [Paragraph("Total Work Hours", table_cell_style), Paragraph(f"{total_work_hours} hrs", table_cell_style)],
                [Paragraph("Total Break Hours", table_cell_style), Paragraph(f"{total_break_hours} hrs", table_cell_style)],
                [Paragraph("Average Work Hours / Employee", table_cell_style), Paragraph(f"{avg_hours_per_emp} hrs", table_cell_style)],
                [Paragraph("Task Completion Rate", table_cell_style), Paragraph(f"{completion_rate}% ({completed_tasks}/{total_tasks})", table_cell_style)],
                [Paragraph("Recommendation Acceptance Rate", table_cell_style), Paragraph(f"{acceptance_rate}% ({accepted_recs}/{total_recs})", table_cell_style)],
            ]
            t_summary = Table(summary_data, colWidths=[250, 254])
            t_summary.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
                ('TOPPADDING', (0, 0), (-1, -1), 5),
                ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
            ]))
            story.append(t_summary)
            story.append(Spacer(1, 10))

            # Productivity Section
            story.append(Paragraph("2. Productivity & Task Analysis", section_style))
            story.append(Paragraph(f"Total tasks created during period: <b>{total_tasks}</b>, with <b>{completed_tasks}</b> successfully completed (<b>{completion_rate}%</b> completion rate).", body_style))
            story.append(Spacer(1, 6))

            # Work Sessions Section
            story.append(Paragraph("3. Work Session Summary", section_style))
            story.append(Paragraph(f"Recorded <b>{session_count}</b> work sessions totaling <b>{total_work_hours}</b> active work hours and <b>{total_break_hours}</b> break hours.", body_style))
            story.append(Spacer(1, 6))

            # Wellbeing Section
            story.append(Paragraph("4. Wellbeing Monitoring Aggregates", section_style))
            if is_manager_or_admin and total_employees < 5:
                story.append(Paragraph("<i>Team analytics withheld: not enough people to show this safely; at least 5 non-test employees are required.</i>", body_style))
            elif not checkins:
                story.append(Paragraph("<i>No wellbeing check-in records found for this period.</i>", body_style))
            else:
                wb_data = [
                    [Paragraph("<b>Wellbeing Metric</b>", table_header_style), Paragraph("<b>Average Score (1–5 Scale)</b>", table_header_style)],
                    [Paragraph("Overall Wellbeing", table_cell_style), Paragraph(str(avg_ow), table_cell_style)],
                    [Paragraph("Mental Fatigue", table_cell_style), Paragraph(str(avg_mf), table_cell_style)],
                    [Paragraph("Workload Manageability", table_cell_style), Paragraph(str(avg_wm), table_cell_style)],
                    [Paragraph("Perceived Focus", table_cell_style), Paragraph(str(avg_pf), table_cell_style)],
                    [Paragraph("Break Recovery", table_cell_style), Paragraph(str(avg_br), table_cell_style)],
                ]
                t_wb = Table(wb_data, colWidths=[250, 254])
                t_wb.setStyle(TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
                    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')])
                ]))
                story.append(t_wb)
            story.append(Spacer(1, 10))

            # Recommendation Effectiveness Section
            story.append(Paragraph("5. Recommendation Effectiveness", section_style))
            story.append(Paragraph(f"Generated <b>{total_recs}</b> recommendation feedback events with an acceptance rate of <b>{acceptance_rate}%</b>.", body_style))

        doc.build(story, canvasmaker=NumberedCanvas)
        buffer.seek(0)
        return buffer.getvalue()
