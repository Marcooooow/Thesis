import io
import os
import openpyxl
from datetime import datetime, timezone, date
from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func

from ..models import (
    User, Profile, WorkSession, Break, Task,
    RecommendationFeedback, SessionWellbeingCheckin, TeamMembership
)
from ..auth.security import should_include_test_data


class DatasetExportService:
    """
    Service for generating a comprehensive multi-sheet Excel workbook (.xlsx)
    combining IntelliBreak production/development records for ML thesis research.
    Sheets:
    1. Combined_Dataset: Employee-Session level observations with metrics, wellbeing, and ML features.
    2. Feature_Dictionary: Documentation of every exported column.
    3. Dataset_Summary: High-level dataset summary, missing values, class distribution, and record counts.
    """

    def __init__(self, db: Session):
        self.db = db

    def _sanitize(self, val: Any) -> Any:
        """Formula injection protection for Excel cells."""
        if val is None:
            return None
        s = str(val)
        if s and s[0] in ('=', '+', '-', '@'):
            return f"'{s}"
        return val

    def generate_excel_workbook(self, include_demo_data: bool = True) -> io.BytesIO:
        wb = openpyxl.Workbook()

        # Remove default sheet
        default_sheet = wb.active
        wb.remove(default_sheet)

        # 1. Combined_Dataset Sheet
        ws_combined = wb.create_sheet(title="Combined_Dataset")
        self._populate_combined_dataset(ws_combined, include_demo_data)

        # 2. Feature_Dictionary Sheet
        ws_dict = wb.create_sheet(title="Feature_Dictionary")
        self._populate_feature_dictionary(ws_dict)

        # 3. Dataset_Summary Sheet
        ws_summary = wb.create_sheet(title="Dataset_Summary")
        self._populate_dataset_summary(ws_summary, include_demo_data)

        # Save also to local exports/ directory as requested in deliverables
        try:
            os.makedirs("exports", exist_ok=True)
            wb.save("exports/intellibreak_ml_dataset.xlsx")
        except Exception as e:
            print(f"Warning: Could not save local export copy: {e}")

        buffer = io.BytesIO()
        wb.save(buffer)
        buffer.seek(0)
        return buffer

    def _populate_combined_dataset(self, ws, include_demo_data: bool):
        headers = [
            "Employee ID", "Role", "Team ID", "Work Session ID",
            "Session Start", "Session End", "Session Duration (min)",
            "Focus Rate", "Break Count", "Break Duration (min)", "Break Types",
            "Task Completion Count", "Task Rate",
            "Recommendation Type", "Recommendation Reason", "Recommendation Source",
            "Recommendation Response (User Action)",
            "Overall Wellbeing", "Mental Fatigue", "Workload Manageability",
            "Perceived Focus", "Break Recovery", "Stress Score", "Stress Factors",
            "session_len", "time_since_break", "task_rate", "current_focus_rate",
            "ML Target / Label"
        ]
        ws.append(headers)

        # Query work sessions with user and profile
        sessions_query = self.db.query(WorkSession).join(Profile, WorkSession.profile_id == Profile.id).join(User, Profile.user_id == User.id)

        sessions = sessions_query.all()

        for session in sessions:
            profile = session.profile
            if not profile or not profile.user:
                continue
            user = profile.user

            # Filter demo/test data if requested
            is_demo = should_include_test_data(self.db, user) or getattr(user, 'is_test_data', False) or getattr(profile, 'is_test_data', False)
            if not include_demo_data and is_demo:
                continue

            # Team ID from TeamMembership
            team_id = None
            team_mem = self.db.query(TeamMembership).filter(TeamMembership.profile_id == profile.id).first()
            if team_mem:
                team_id = team_mem.team_id

            # Session timing & duration
            started_at = session.started_at
            ended_at = session.ended_at
            duration_min = 0.0
            if started_at and ended_at:
                if started_at.tzinfo is None:
                    started_at = started_at.replace(tzinfo=timezone.utc)
                if ended_at.tzinfo is None:
                    ended_at = ended_at.replace(tzinfo=timezone.utc)
                duration_min = round((ended_at - started_at).total_seconds() / 60.0, 2)

            # Breaks aggregation
            breaks = self.db.query(Break).filter(Break.work_session_id == session.id).all()
            break_count = len(breaks)
            total_break_sec = 0.0
            break_types = []
            for b in breaks:
                if b.started_at and b.ended_at:
                    b_start = b.started_at.replace(tzinfo=timezone.utc) if b.started_at.tzinfo is None else b.started_at
                    b_end = b.ended_at.replace(tzinfo=timezone.utc) if b.ended_at.tzinfo is None else b.ended_at
                    total_break_sec += max(0.0, (b_end - b_start).total_seconds())
                if hasattr(b, 'break_type') and b.break_type:
                    break_types.append(str(b.break_type))
            break_duration_min = round(total_break_sec / 60.0, 2)
            break_types_str = ", ".join(sorted(list(set(break_types)))) if break_types else None

            # Tasks aggregation
            tasks = self.db.query(Task).filter(Task.work_session_id == session.id).all()
            task_count = len(tasks)
            completed_tasks = sum(1 for t in tasks if getattr(t, 'completed', False) or getattr(t, 'status', '') == 'completed')
            task_rate = round(completed_tasks / task_count, 2) if task_count > 0 else 0.0

            # Recommendation & Feedback linked to session or profile
            feedback = self.db.query(RecommendationFeedback).filter(
                RecommendationFeedback.work_session_id == session.id
            ).first()
            rec_type = feedback.recommendation_type if feedback else None
            rec_reason = getattr(feedback, 'reason', None)
            rec_source = getattr(feedback, 'source', 'heuristic')
            user_action = feedback.user_action if feedback else None

            # Wellbeing checkin linked to session
            wellbeing = self.db.query(SessionWellbeingCheckin).filter(
                SessionWellbeingCheckin.work_session_id == session.id
            ).first()
            overall_wb = wellbeing.overall_wellbeing if wellbeing else None
            fatigue = wellbeing.mental_fatigue if wellbeing else None
            workload = wellbeing.workload_manageability if wellbeing else None
            focus = wellbeing.perceived_focus if wellbeing else None
            recovery = wellbeing.break_recovery if wellbeing else None
            stress_factors = wellbeing.stress_factors if wellbeing else None
            stress_score = len(stress_factors) if isinstance(stress_factors, list) else (1 if stress_factors else 0)

            # ML Features
            session_len_feat = duration_min
            time_since_break = round(duration_min / max(1, break_count + 1), 2)
            task_rate_feat = task_rate
            focus_rate_feat = round(focus / 5.0, 2) if focus else 0.75

            # ML Target/Label: accepted -> 1, dismissed/ignored -> 0, else None
            ml_target = None
            if user_action == 'accepted':
                ml_target = 1
            elif user_action in ('dismissed', 'ignored'):
                ml_target = 0

            row = [
                self._sanitize(str(user.id)),
                self._sanitize(user.role),
                self._sanitize(str(team_id)) if team_id else None,
                self._sanitize(str(session.id)),
                started_at.isoformat() if started_at else None,
                ended_at.isoformat() if ended_at else None,
                duration_min,
                focus_rate_feat,
                break_count,
                break_duration_min,
                self._sanitize(break_types_str),
                completed_tasks,
                task_rate,
                self._sanitize(rec_type),
                self._sanitize(rec_reason),
                self._sanitize(rec_source),
                self._sanitize(user_action),
                overall_wb,
                fatigue,
                workload,
                focus,
                recovery,
                stress_score,
                self._sanitize(str(stress_factors)),
                session_len_feat,
                time_since_break,
                task_rate_feat,
                focus_rate_feat,
                ml_target
            ]
            ws.append(row)

    def _populate_feature_dictionary(self, ws):
        headers = [
            "Column Name", "Description", "Data Type",
            "Source Table", "Calculation Method", "Feature Type"
        ]
        ws.append(headers)

        dictionary_entries = [
            ("Employee ID", "Unique identifier for the employee/user", "String (UUID)", "users", "Original user record ID", "Original"),
            ("Role", "User role in the system (admin, manager, employee)", "String", "users", "Original user role attribute", "Original"),
            ("Team ID", "Unique identifier of the employee's team", "String (UUID)", "profiles", "Associated team foreign key", "Original"),
            ("Work Session ID", "Unique identifier for the work session", "String (UUID)", "work_sessions", "Original session record ID", "Original"),
            ("Session Start", "Timestamp when work session started", "DateTime", "work_sessions", "Session started_at timestamp", "Original"),
            ("Session End", "Timestamp when work session ended", "DateTime", "work_sessions", "Session ended_at timestamp", "Original"),
            ("Session Duration (min)", "Total duration of the work session in minutes", "Float", "work_sessions", "(ended_at - started_at) in minutes", "Derived"),
            ("Focus Rate", "Estimated focus proportion during session", "Float", "Derived", "Normalized perceived focus score", "Derived"),
            ("Break Count", "Total number of completed breaks during session", "Integer", "breaks", "Count of break records linked to session", "Derived"),
            ("Break Duration (min)", "Total duration of all breaks in minutes", "Float", "breaks", "Sum of break durations linked to session", "Derived"),
            ("Break Types", "Types of breaks taken during session", "String", "breaks", "Comma-separated unique break types", "Derived"),
            ("Task Completion Count", "Number of tasks completed during session", "Integer", "tasks", "Count of completed tasks linked to session", "Derived"),
            ("Task Rate", "Proportion of tasks completed", "Float", "tasks", "Completed tasks / Total tasks", "Derived"),
            ("Recommendation Type", "Type of recommendation suggested", "String", "recommendation_feedback", "Suggested break or wellness action type", "Original"),
            ("Recommendation Reason", "Explanation for the recommendation", "String", "recommendation_feedback", "Heuristic or ML reasoning text", "Original"),
            ("Recommendation Source", "Engine source of recommendation", "String", "recommendation_feedback", "heuristic or ml_model", "Original"),
            ("Recommendation Response", "User feedback action on recommendation", "String", "recommendation_feedback", "accepted, dismissed, ignored, etc.", "Original"),
            ("Overall Wellbeing", "Reported overall wellbeing score (1-5)", "Integer", "session_wellbeing_checkins", "Check-in overall_wellbeing rating", "Original"),
            ("Mental Fatigue", "Reported mental fatigue score (1-5)", "Integer", "session_wellbeing_checkins", "Check-in mental_fatigue rating", "Original"),
            ("Workload Manageability", "Reported workload score (1-5)", "Integer", "session_wellbeing_checkins", "Check-in workload_manageability rating", "Original"),
            ("Perceived Focus", "Reported perceived focus score (1-5)", "Integer", "session_wellbeing_checkins", "Check-in perceived_focus rating", "Original"),
            ("Break Recovery", "Reported break recovery score (1-5)", "Integer", "session_wellbeing_checkins", "Check-in break_recovery rating", "Original"),
            ("Stress Score", "Count of reported stress factors", "Integer", "session_wellbeing_checkins", "Length of stress factors list", "Derived"),
            ("Stress Factors", "Specific stress factors reported", "String (List)", "session_wellbeing_checkins", "Original check-in stress factors", "Original"),
            ("session_len", "Session length feature for ML pipeline", "Float", "Derived", "Session Duration in minutes", "Derived"),
            ("time_since_break", "Time since last break feature", "Float", "Derived", "Duration / (Break Count + 1)", "Derived"),
            ("task_rate", "Task completion rate feature for ML", "Float", "Derived", "Task completion rate ratio", "Derived"),
            ("current_focus_rate", "Current focus rate feature for ML", "Float", "Derived", "Normalized perceived focus", "Derived"),
            ("ML Target / Label", "Binary target for recommendation acceptance", "Integer", "recommendation_feedback", "1 if accepted, 0 if dismissed/ignored", "Derived"),
        ]

        for entry in dictionary_entries:
            ws.append([self._sanitize(e) for e in entry])

    def _populate_dataset_summary(self, ws, include_demo_data: bool):
        ws.append(["Metric Name", "Value"])

        # Compute summary stats
        sessions_query = self.db.query(WorkSession).join(Profile, WorkSession.profile_id == Profile.id).join(User, Profile.user_id == User.id)
        sessions = sessions_query.all()

        filtered_sessions = []
        employees = set()
        for s in sessions:
            if not s.profile or not s.profile.user:
                continue
            u = s.profile.user
            is_demo = should_include_test_data(self.db, u) or getattr(u, 'is_test_data', False) or getattr(s.profile, 'is_test_data', False)
            if not include_demo_data and is_demo:
                continue
            filtered_sessions.append(s)
            employees.add(str(u.id))

        total_sessions = len(filtered_sessions)
        total_employees = len(employees)

        total_recommendations = self.db.query(RecommendationFeedback).count()
        total_feedback = self.db.query(RecommendationFeedback).filter(RecommendationFeedback.user_action.isnot(None)).count()
        total_wellbeing = self.db.query(SessionWellbeingCheckin).count()

        accepted_count = self.db.query(RecommendationFeedback).filter(RecommendationFeedback.user_action == 'accepted').count()
        dismissed_ignored_count = self.db.query(RecommendationFeedback).filter(RecommendationFeedback.user_action.in_(['dismissed', 'ignored'])).count()

        dates = [s.started_at for s in filtered_sessions if s.started_at]
        date_range = f"{min(dates).date()} to {max(dates).date()}" if dates else "N/A"

        metrics = [
            ("Total Exported Work Sessions", total_sessions),
            ("Total Unique Employees Represented", total_employees),
            ("Total Recommendations Generated", total_recommendations),
            ("Total Feedback Responses Recorded", total_feedback),
            ("Total Wellbeing Check-ins Recorded", total_wellbeing),
            ("ML Accepted Labels (Class 1)", accepted_count),
            ("ML Dismissed/Ignored Labels (Class 0)", dismissed_ignored_count),
            ("Dataset Date Range Covered", date_range),
            ("Include Demo Data Flag", str(include_demo_data)),
        ]

        for m in metrics:
            ws.append([self._sanitize(m[0]), self._sanitize(m[1])])
