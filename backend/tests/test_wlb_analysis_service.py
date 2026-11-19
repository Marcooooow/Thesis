"""
Tests for WLB Analysis Service
"""
import pytest
from datetime import date, datetime, timezone, timedelta
import uuid

from app.services.wlb_analysis_service import WLBAnalysisService


class TestWLBAnalysisService:
    """Test WLB Analysis Service functionality"""

    def test_calculate_wlb_score(self, test_db):
        """Test WLB score calculation from 5-question Likert survey."""
        service = WLBAnalysisService(test_db)

        # Create mock survey object
        class MockSurvey:
            def __init__(self, ratings):
                self.rating_disconnect = ratings[0]
                self.rating_personal_time = ratings[1]
                self.rating_responsibilities_balance = ratings[2]
                self.rating_schedule_satisfaction = ratings[3]
                self.rating_recovery = ratings[4]

        # Test extremes
        survey = MockSurvey([5, 5, 5, 5, 5])  # All 5s -> 100
        assert service._calculate_wlb_score(survey) == 100.0

        survey = MockSurvey([1, 1, 1, 1, 1])  # All 1s -> 0
        assert service._calculate_wlb_score(survey) == 0.0

        # Test middle values
        survey = MockSurvey([3, 3, 3, 3, 3])  # All 3s -> 50
        assert service._calculate_wlb_score(survey) == 50.0

        # Test mixed
        survey = MockSurvey([4, 4, 3, 2, 3])  # Sum = 16 -> ((16-5)/20)*100 = 55
        assert service._calculate_wlb_score(survey) == 55.0

    def test_wlb_score_labels(self, test_db):
        """Test WLB score label mapping."""
        service = WLBAnalysisService(test_db)

        assert service._get_wlb_score_label(90) == "Excellent"
        assert service._get_wlb_score_label(75) == "Good"
        assert service._get_wlb_score_label(60) == "Fair"
        assert service._get_wlb_score_label(40) == "Poor"
        assert service._get_wlb_score_label(20) == "Critical"

    def test_wlb_risk_tier(self, test_db):
        """Test combined risk tier calculation."""
        service = WLBAnalysisService(test_db)

        # Survey score with behavioral concerns
        assert service._get_wlb_risk_tier(30, True) == "CRITICAL"
        assert service._get_wlb_risk_tier(30, False) == "CRITICAL"
        assert service._get_wlb_risk_tier(45, True) == "CRITICAL"
        assert service._get_wlb_risk_tier(45, False) == "HIGH"
        assert service._get_wlb_risk_tier(60, True) == "HIGH"
        assert service._get_wlb_risk_tier(60, False) == "MODERATE"
        assert service._get_wlb_risk_tier(80, True) == "MODERATE"
        assert service._get_wlb_risk_tier(80, False) == "LOW"

    def test_get_weekly_wlb_analysis_no_data(self, test_db, test_user):
        """Test weekly analysis with no sessions or survey."""
        profile = test_user.profile
        service = WLBAnalysisService(test_db)

        today = date.today()
        monday = today - timedelta(days=today.weekday())

        result = service.get_weekly_wlb_analysis(profile.id, monday)

        assert result["profile_id"] == str(profile.id)
        assert result["week_start"] == monday.isoformat()
        assert result["has_survey"] is False
        assert result["risk_tier"] == "LOW"
        assert "behavioral_indicators" in result
        assert result["behavioral_indicators"]["concern_count"] == 0

    def test_employee_classification_requires_sufficient_evidence_for_critical(self, test_db):
        service = WLBAnalysisService(test_db)

        result = service._classify_employee_status(
            survey_score=10,
            behavioral={"concerns": [{"severity": "HIGH", "type": "SUSTAINED_OVERTIME"}]},
            historical_patterns=[],
            sessions_count=1,
            checkins_count=0,
        )

        assert result["classification"] == "NEEDS_ATTENTION"
        assert result["data_completeness"] == "partial"
        assert result["classification"] != "CRITICAL"

    def test_employee_classification_missing_survey_stays_needs_attention(self, test_db):
        result = WLBAnalysisService(test_db)._classify_employee_status(
            survey_score=None, behavioral={"concerns": []}, historical_patterns=[],
            sessions_count=3, checkins_count=2,
        )

        assert result["classification"] == "HEALTHY"
        assert result["data_completeness"] == "complete"
        assert "Survey" in result["explanation"]

    def test_employee_classification_healthy_requires_positive_evidence_or_complete_data(self, test_db):
        service = WLBAnalysisService(test_db)

        healthy_by_survey = service._classify_employee_status(
            survey_score=80, behavioral={"concerns": []}, historical_patterns=[],
            sessions_count=0, checkins_count=0,
        )
        healthy_by_complete_data = service._classify_employee_status(
            survey_score=None, behavioral={"concerns": []}, historical_patterns=[],
            sessions_count=3, checkins_count=2,
        )

        assert healthy_by_survey["classification"] == "HEALTHY"
        assert healthy_by_complete_data["classification"] == "HEALTHY"
        assert healthy_by_complete_data["data_completeness"] == "complete"

    def test_employee_classification_marks_no_data_insufficient(self, test_db):
        service = WLBAnalysisService(test_db)

        result = service._classify_employee_status(
            survey_score=None,
            behavioral={"concerns": []},
            historical_patterns=[],
            sessions_count=0,
            checkins_count=0,
        )

        assert result["classification"] == "NEEDS_ATTENTION"
        assert result["data_completeness"] == "insufficient"
        assert result["evidence"] == []
        assert result["explanation"] == "Insufficient data for a reliable assessment."

    def test_employee_classification_keeps_conflicting_survey_and_behavioral_evidence_noncritical(self, test_db):
        result = WLBAnalysisService(test_db)._classify_employee_status(
            survey_score=80,
            behavioral={"concerns": [
                {"severity": "HIGH", "type": "SUSTAINED_OVERTIME", "description": "Repeated overtime"},
                {"severity": "HIGH", "type": "LOW_BREAK_COMPLIANCE", "description": "Few breaks"},
            ]},
            historical_patterns=[],
            sessions_count=4,
            checkins_count=2,
        )

        assert result["classification"] == "NEEDS_ATTENTION"
        assert result["classification"] != "CRITICAL"
        assert len(result["evidence"]) == 2

    def test_low_workload_manageability_is_included_in_behavioral_concerns(self, test_db, test_user):
        from app.models import SessionWellbeingCheckin, WorkSession

        profile = test_user.profile
        week_start = date.today() - timedelta(days=date.today().weekday())
        session = WorkSession(
            profile_id=profile.id,
            started_at=datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=9),
            ended_at=datetime.combine(week_start, datetime.min.time(), tzinfo=timezone.utc) + timedelta(hours=17),
        )
        test_db.add(session)
        test_db.flush()
        test_db.add(SessionWellbeingCheckin(
            user_id=test_user.id, work_session_id=session.id,
            overall_wellbeing=2, mental_fatigue=2, workload_manageability=1,
            perceived_focus=3, break_recovery=3,
        ))
        test_db.commit()

        indicators = WLBAnalysisService(test_db)._compute_behavioral_indicators(
            profile.id, [session], test_db.query(SessionWellbeingCheckin).all(),
            week_start, week_start + timedelta(days=6),
        )

        assert indicators["avg_workload_manageability"] == 1
        assert indicators["avg_overall_wellbeing"] == 2
        assert any(concern["type"] == "LOW_WORKLOAD_MANAGEABILITY" for concern in indicators["concerns"])

    def test_employee_classification_critical_needs_two_independent_signals(self, test_db):
        service = WLBAnalysisService(test_db)

        result = service._classify_employee_status(
            survey_score=10,
            behavioral={"concerns": [
                {"severity": "HIGH", "type": "SUSTAINED_OVERTIME"},
                {"severity": "HIGH", "type": "LOW_BREAK_COMPLIANCE"},
            ]},
            historical_patterns=[],
            sessions_count=4,
            checkins_count=2,
        )

        assert result["classification"] == "CRITICAL"
        assert len(result["evidence"]) >= 2
        assert result["data_completeness"] == "complete"

    def test_weekly_analysis_api_is_scoped_to_authenticated_employee(self, test_client, test_user):
        from app.auth.security import create_access_token

        token = create_access_token(data={"sub": test_user.email})
        response = test_client.get(
            "/wlb/analysis/weekly",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert response.status_code == 200
        assert response.json()["profile_id"] == str(test_user.profile.id)
        assert "employee_status" in response.json()
        assert "wlb_survey" in response.json()

    def test_employee_wlb_api_denies_other_employee_id(self, test_client, test_user, test_db):
        from app.auth.security import create_access_token
        from app.models import User, Profile
        from app.auth.security import get_password_hash

        other = User(
            email="other-wlb@example.com", full_name="Other", role="EMPLOYEE",
            approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpassword123"), account_type="solo",
        )
        test_db.add(other)
        test_db.flush()
        other_profile = Profile(user_id=other.id)
        test_db.add(other_profile)
        test_db.commit()
        token = create_access_token(data={"sub": test_user.email})

        response = test_client.get(
            f"/wlb/analysis/employee/{other_profile.id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 403

    def test_manager_without_active_teams_is_denied_employee_wlb(self, test_client, test_db):
        from app.auth.security import create_access_token, get_password_hash
        from app.models import User, Profile

        manager = User(
            email=f"wlb-no-team-manager-{uuid.uuid4()}@example.com", full_name="Manager",
            role="MANAGER", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpassword123"), account_type="organization",
        )
        employee = User(
            email=f"wlb-no-team-employee-{uuid.uuid4()}@example.com", full_name="Employee",
            role="EMPLOYEE", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpassword123"), account_type="organization",
        )
        test_db.add_all([manager, employee])
        test_db.flush()
        profile = Profile(user_id=employee.id)
        test_db.add(profile)
        test_db.commit()

        response = test_client.get(
            f"/wlb/analysis/employee/{profile.id}",
            headers={"Authorization": f"Bearer {create_access_token(data={'sub': manager.email})}"},
        )

        assert response.status_code == 403

    def test_admin_can_access_employee_wlb(self, test_client, test_db):
        from app.auth.security import create_access_token, get_password_hash
        from app.models import User, Profile

        admin = User(
            email=f"wlb-admin-{uuid.uuid4()}@example.com", full_name="Admin",
            role="ADMIN", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpassword123"), account_type="organization",
        )
        employee = User(
            email=f"wlb-admin-target-{uuid.uuid4()}@example.com", full_name="Employee",
            role="EMPLOYEE", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpassword123"), account_type="organization",
        )
        test_db.add_all([admin, employee])
        test_db.flush()
        profile = Profile(user_id=employee.id)
        test_db.add(profile)
        test_db.commit()

        response = test_client.get(
            f"/wlb/analysis/employee/{profile.id}",
            headers={"Authorization": f"Bearer {create_access_token(data={'sub': admin.email})}"},
        )

        assert response.status_code == 200

    def test_manager_wlb_api_denies_employee_outside_managed_team(self, test_client, test_db):
        from app.auth.security import create_access_token, get_password_hash
        from app.models import User, Profile, Organization

        organization = Organization(name="WLB unassigned org")
        manager = User(
            email="wlb-manager-unassigned@example.com", full_name="Manager", role="MANAGER",
            approval_status="APPROVED", is_active=True, account_type="organization",
            password_hash=get_password_hash("testpassword123"),
        )
        employee = User(
            email="wlb-employee-unassigned@example.com", full_name="Employee", role="EMPLOYEE",
            approval_status="APPROVED", is_active=True, account_type="organization",
            password_hash=get_password_hash("testpassword123"),
        )
        test_db.add_all([organization, manager, employee])
        test_db.flush()
        profile = Profile(user_id=employee.id)
        test_db.add(profile)
        test_db.commit()
        token = create_access_token(data={"sub": manager.email})

        response = test_client.get(
            f"/wlb/analysis/employee/{profile.id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 403

    def test_manager_wlb_api_is_limited_to_managed_team(self, test_client, test_db, test_user, monkeypatch):
        from app.auth.security import create_access_token, get_password_hash
        from app.models import User, Profile, Organization, Team, TeamMembership

        organization = Organization(name="WLB authorization org")
        test_db.add(organization)
        manager = User(
            email="wlb-manager@example.com", full_name="Manager", role="MANAGER",
            approval_status="APPROVED", is_active=True, account_type="organization",
            password_hash=get_password_hash("testpassword123"),
        )
        employee = User(
            email="wlb-employee@example.com", full_name="Employee", role="EMPLOYEE",
            approval_status="APPROVED", is_active=True, account_type="organization",
            password_hash=get_password_hash("testpassword123"),
        )
        test_db.add_all([manager, employee])
        test_db.flush()
        profile = Profile(user_id=employee.id)
        test_db.add(profile)
        test_db.flush()
        team = Team(name="WLB auth team", manager_user_id=manager.id, organization_id=organization.id)
        test_db.add(team)
        test_db.flush()
        test_db.add(TeamMembership(profile_id=profile.id, team_id=team.id, role="EMPLOYEE"))
        test_db.commit()
        outside_profile = test_user.profile

        restricted_analysis = {
            "profile_id": str(profile.id),
            "week_start": "2026-11-02",
            "week_end": "2026-11-08",
            "risk_tier": "CRITICAL",
            "employee_status": {
                "classification": "CRITICAL",
                "data_completeness": "complete",
                "manager_review_recommended": True,
                "explanation": "Private service-level classification",
                "evidence": [
                    {"source": "survey", "description": "Weekly WLB survey score was 12/100", "metric_value": 12},
                    {"source": "work_patterns", "type": "SUSTAINED_OVERTIME", "description": "Worked >140% target hours on 2 days this week", "metric_value": 2},
                    {"source": "work_patterns", "type": "LOW_BREAK_COMPLIANCE", "description": "Break compliance only 25%", "metric_value": 25.0},
                    {"source": "work_patterns", "type": "ELEVATED_FATIGUE", "description": "Self-reported fatigue averaging 4.8/5", "metric_value": 4.8},
                    {"source": "work_patterns", "type": "LOW_WORKLOAD_MANAGEABILITY", "description": "Self-reported workload manageability averaged 1.0/5", "metric_value": 1.0},
                    {"source": "work_patterns", "type": "LOW_REPORTED_WELLBEING", "description": "Self-reported overall wellbeing averaged 1.0/5", "metric_value": 1.0},
                    {"source": "historical_pattern", "pattern_id": "RECURRING_FATIGUE_STRESS", "description": "Recurring fatigue stress"},
                ],
            },
            "behavioral_indicators": {
                "total_work_hours": 42.0,
                "avg_daily_hours": 8.4,
                "work_days": 5,
                "overtime_days": 2,
                "overtime_severe_days": 1,
                "target_daily_hours": 8.0,
                "break_compliance_pct": 25.0,
                "avg_break_minutes_per_day": 7.5,
                "avg_focus_rate": 62.0,
                "avg_fatigue": 4.8,
                "avg_workload_manageability": 1.0,
                "avg_overall_wellbeing": 1.0,
                "concern_count": 5,
                "work_schedule_irregularity": "low",
                "concerns": [
                    {"type": "SUSTAINED_OVERTIME", "severity": "HIGH", "description": "Repeated extended hours", "metric_value": 2},
                    {"type": "LOW_BREAK_COMPLIANCE", "severity": "MEDIUM", "description": "Break compliance low", "metric_value": 25.0},
                    {"type": "ELEVATED_FATIGUE", "severity": "HIGH", "description": "Self-reported fatigue averaging 4.8/5", "metric_value": 4.8},
                    {"type": "LOW_WORKLOAD_MANAGEABILITY", "severity": "HIGH", "description": "Self-reported workload manageability averaged 1.0/5", "metric_value": 1.0},
                    {"type": "LOW_REPORTED_WELLBEING", "severity": "HIGH", "description": "Self-reported overall wellbeing averaged 1.0/5", "metric_value": 1.0},
                ],
            },
            "historical_patterns": [
                {
                    "pattern_id": "INSUFFICIENT_RECOVERY",
                    "evidence_strength": "MEDIUM",
                    "measurements": {"average_break_recovery_score": 1.2, "checkin_count": 4},
                    "observation_period": "14 days",
                    "observation_count": 4,
                    "data_limitations": "Check-in recovery detail marker: private-recovery-marker.",
                },
                {
                    "pattern_id": "RECURRING_FATIGUE_STRESS",
                    "evidence_strength": "HIGH",
                    "measurements": {"average_mental_fatigue": 4.8, "total_stress_factors_reported": 4, "observation_count": 5},
                    "observation_period": "14 days",
                    "observation_count": 5,
                    "data_limitations": "Private fatigue details marker: private-fatigue-marker.",
                },
                {
                    "pattern_id": "RECURRING_OVERWORK",
                    "evidence_strength": "MEDIUM",
                    "measurements": {"target_daily_hours": 8.0, "overwork_days_count": 2, "recent_daily_hours_avg": 8.4},
                    "observation_period": "14 days",
                    "observation_count": 5,
                    "data_limitations": "Based on recorded work sessions.",
                },
            ],
            "data_quality": {"sessions_count": 5, "checkins_count": 5, "has_wlb_survey": True},
        }
        monkeypatch.setattr(
            "app.routers.wlb.WLBAnalysisService.get_weekly_wlb_analysis",
            lambda _service, _profile_id, _week: restricted_analysis,
        )
        token = create_access_token(data={"sub": manager.email})

        forbidden_response = test_client.get(
            f"/wlb/analysis/employee/{outside_profile.id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert forbidden_response.status_code == 403

        response = test_client.get(
            f"/wlb/analysis/employee/{profile.id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["employee_status"]["classification"] == "NEEDS_ATTENTION"
        assert body["employee_status"]["explanation"] != "Private service-level classification"
        assert body["employee_status"]["evidence"] == [
            {"source": "employee_report", "description": "Employee-reported survey concern present."},
            *[
                item for item in restricted_analysis["employee_status"]["evidence"]
                if item.get("type") in ("SUSTAINED_OVERTIME", "LOW_BREAK_COMPLIANCE")
            ],
        ]
        assert "wlb_survey" not in body
        assert "responses" not in str(body)
        assert "notes" not in str(body)
        assert "wellbeing_trends" not in body
        assert body["behavioral_indicators"] == {
            "total_work_hours": 42.0,
            "avg_daily_hours": 8.4,
            "work_days": 5,
            "overtime_days": 2,
            "overtime_severe_days": 1,
            "target_daily_hours": 8.0,
            "break_compliance_pct": 25.0,
            "avg_break_minutes_per_day": 7.5,
            "avg_focus_rate": 62.0,
            "concern_count": 2,
            "work_schedule_irregularity": "low",
        }
        assert body["work_pattern_concerns"] == restricted_analysis["behavioral_indicators"]["concerns"][:2]
        assert [p["pattern_id"] for p in body["historical_patterns"]] == ["RECURRING_OVERWORK"]
        assert "RECURRING_FATIGUE_STRESS" not in str(body)
        assert "avg_fatigue" not in str(body)
        assert "avg_stress" not in str(body)
        assert "4.8" not in str(body)
        assert "4.6" not in str(body)
        assert "private-fatigue-marker" not in str(body)
        assert "private-recovery-marker" not in str(body)
        assert "average_break_recovery_score" not in str(body)
        assert "total_stress_factors_reported" not in str(body)
        assert body["risk_tier"] is None
        assert body["behavioral_indicators"]["concern_count"] == 2
        assert body["historical_patterns"][0]["measurements"] == {
            "target_daily_hours": 8.0,
            "overwork_days_count": 2,
            "recent_daily_hours_avg": 8.4,
        }
        assert "private" not in str(body).lower()

    def test_recommendations_include_evidence_action_and_measurable_outcome(self, test_db):
        service = WLBAnalysisService(test_db)
        recommendations = service._generate_wlb_recommendations(
            {"score": 45, "responses": {}},
            {
                "concerns": [{
                    "type": "RECURRING_OVERTIME",
                    "severity": "MEDIUM",
                    "description": "Worked above target hours on 3 days this week",
                }],
            },
            "HIGH",
        )

        overtime_rec = next(
            rec for rec in recommendations
            if rec["action_type"] == "task_prioritization"
        )
        assert "3 days this week" in overtime_rec["reason"]
        assert overtime_rec["action_step"] == overtime_rec["description"]
        assert "Monitor" in overtime_rec["expected_outcome"]
        assert "not guaranteed" in overtime_rec["expected_outcome"]

    def test_get_wlb_trends(self, test_db, test_user):
        """Test WLB trends over multiple weeks."""
        profile = test_user.profile
        service = WLBAnalysisService(test_db)

        result = service.get_wlb_trends(profile.id, weeks=4)

        assert result["profile_id"] == str(profile.id)
        assert result["weeks_analyzed"] == 4
        assert "weekly_data" in result
        assert len(result["weekly_data"]) == 4
        assert "trend" in result
        assert result["trend"] in ["stable", "improving", "declining"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])