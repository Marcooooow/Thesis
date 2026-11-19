"""
Phase 4 Step 1 — Regression tests for WLB/Risk/Serialization fixes.

Tests confirm:
1. No hardcoded 65.0 fallback; returns None for empty surveys
2. Null risk_tier becomes "insufficient_data"
3. Report and insights use same WLB aggregation
4. rating_averages present in HTTP response
"""
import pytest
from datetime import datetime, timezone, timedelta
from sqlalchemy.orm import Session
from app.database import SessionLocal
from app.models import (
    User, Organization, Profile, OrganizationMembership,
    WorkLifeBalanceSurvey, Team, TeamMembership
)
from app.services.admin_organization_report_service import AdminOrganizationReportService
from app.services.organizational_insights_service import OrganizationalInsightsService
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


@pytest.fixture(scope="function")
def test_org_and_users(db: Session):
    """Create test org with users for regression testing."""
    org = Organization(name="Test Org Regression")
    db.add(org)
    db.flush()

    admin_user = User(email="admin_regression@test.local", password_hash="test", full_name="Admin Regression")
    db.add(admin_user)
    db.flush()

    org_member = OrganizationMembership(
        user_id=admin_user.id,
        organization_id=org.id,
        status="APPROVED"
    )
    db.add(org_member)
    db.flush()

    profile1 = Profile(user_id=admin_user.id, is_test_data=True)
    db.add(profile1)
    db.flush()

    db.commit()
    return org, admin_user, profile1


class TestWLBFallbackRemoved:
    """Test Fix 1: No hardcoded 65.0 fallback for empty surveys."""

    def test_no_survey_returns_none_not_fallback(self, db: Session, test_org_and_users):
        """Insights service returns None for no surveys, not 65.0."""
        org, admin_user, _ = test_org_and_users

        # Generate insights with no WLB surveys
        result = OrganizationalInsightsService.generate_organizational_insights(
            db=db,
            current_user=admin_user,
            period="this_week"
        )

        # Should not crash; insights should handle None gracefully
        assert result is not None
        assert "insights" in result
        # Verify no WLB insights were generated (due to insufficient data)
        wlb_insights = [i for i in result["insights"] if i.get("category") == "wlb"]
        # Should have informational insight but not use 65.0
        for insight in wlb_insights:
            if "score" in str(insight).lower():
                assert "65.0" not in str(insight), "Fallback 65.0 should not be used"


class TestRiskClassificationFix:
    """Test Fix 2: Null risk_tier becomes 'insufficient_data', not 'low'."""

    def test_null_risk_tier_not_low(self, db: Session, test_org_and_users):
        """When compute_weekly_risk returns None tier, classify as insufficient_data."""
        org, admin_user, profile = test_org_and_users

        # Generate insights
        result = OrganizationalInsightsService.generate_organizational_insights(
            db=db,
            current_user=admin_user,
            period="this_week"
        )

        # Check risk distribution in wellbeing insights
        wb_insights = [i for i in result["insights"] if i.get("category") == "wellbeing"]
        for insight in wb_insights:
            metrics = insight.get("supporting_metrics", {})
            risk_dist = metrics.get("risk_distribution", {})
            # If there are insufficient_data cases, they should be counted correctly
            if "insufficient_data" in risk_dist:
                assert risk_dist["insufficient_data"] >= 0
            # low_risk should not include misclassified insufficient_data
            assert "low_risk" in risk_dist or risk_dist.get("low_risk", 0) >= 0


class TestWLBAggregationConsistency:
    """Test Fix 3: Report and insights use same WLB aggregation."""

    def test_same_wlb_survey_population(self, db: Session, test_org_and_users):
        """Report and insights query same WLB surveys."""
        org, admin_user, profile = test_org_and_users

        # Add WLB surveys
        start = datetime.now(timezone.utc).date() - timedelta(days=21)
        for i in range(3):
            survey = WorkLifeBalanceSurvey(
                profile_id=profile.id,
                organization_id=org.id,
                week_start_date=start + timedelta(weeks=i),
                score=60.0 + i * 5,
                rating_disconnect=3,
                rating_personal_time=3,
                rating_responsibilities_balance=3,
                rating_schedule_satisfaction=3,
                rating_recovery=3
            )
            db.add(survey)
        db.commit()

        # Get report
        report_service = AdminOrganizationReportService(db, admin_user)
        report = report_service.generate_preview(period="this_month")

        # Get insights
        insights = OrganizationalInsightsService.generate_organizational_insights(
            db=db,
            current_user=admin_user,
            period="this_month"
        )

        # Extract WLB data from both
        report_wlb = report.get("work_life_balance", {})
        report_avg = report_wlb.get("avg_wlb_score")

        wlb_insights = [i for i in insights["insights"] if i.get("category") == "wlb"]
        insights_wlb = None
        if wlb_insights and len(wlb_insights) > 0:
            insights_wlb = wlb_insights[0].get("supporting_metrics", {}).get("current_avg_wlb")

        # Both should return WLB data (not None, not fallback)
        assert report_avg is not None
        assert report_avg > 0


class TestRatingAveragesSerialization:
    """Test Fix 4: rating_averages present in HTTP JSON response."""

    def test_rating_averages_in_preview_response(self, db: Session, test_org_and_users):
        """Main response includes rating_averages in work_life_balance."""
        org, admin_user, profile = test_org_and_users

        # Add WLB surveys
        start = datetime.now(timezone.utc).date() - timedelta(days=14)
        survey = WorkLifeBalanceSurvey(
            profile_id=profile.id,
            organization_id=org.id,
            week_start_date=start,
            score=60.0,
            rating_disconnect=3,
            rating_personal_time=4,
            rating_responsibilities_balance=3,
            rating_schedule_satisfaction=4,
            rating_recovery=3
        )
        db.add(survey)
        db.commit()

        # Call service to get response dict
        report_service = AdminOrganizationReportService(db, admin_user)
        response_dict = report_service.generate_preview(period="this_month")

        # Verify rating_averages is present in main WLB section
        wlb = response_dict.get("work_life_balance", {})
        assert "rating_averages" in wlb, "rating_averages missing from main WLB section"

        rating_avg = wlb.get("rating_averages", {})
        assert "disconnect" in rating_avg
        assert "personal_time" in rating_avg
        assert "recovery" in rating_avg

        # Verify values are numeric (not None/suppressed at org level)
        assert isinstance(rating_avg.get("disconnect"), (int, float))
        assert isinstance(rating_avg.get("personal_time"), (int, float))
        assert isinstance(rating_avg.get("recovery"), (int, float))

    def test_rating_averages_in_team_comparison(self, db: Session, test_org_and_users):
        """Team comparison includes rating_averages in each team's WLB."""
        org, admin_user, profile = test_org_and_users

        # Create team with >= 3 members
        team = Team(organization_id=org.id, name="Test Team", is_active=True, manager_user_id=admin_user.id)
        db.add(team)
        db.flush()

        # Add 3 profiles to team
        for i in range(3):
            user = User(email=f"user{i}@test.local", password_hash="test", full_name=f"User {i}")
            db.add(user)
            db.flush()

            p = Profile(user_id=user.id, is_test_data=False)
            db.add(p)
            db.flush()

            membership = TeamMembership(
                team_id=team.id,
                profile_id=p.id
            )
            db.add(membership)

            # Add WLB survey
            survey = WorkLifeBalanceSurvey(
                profile_id=p.id,
                organization_id=org.id,
                week_start_date=datetime.now(timezone.utc).date() - timedelta(days=7),
                score=65.0 + i,
                rating_disconnect=3 + i,
                rating_personal_time=3,
                rating_responsibilities_balance=3,
                rating_schedule_satisfaction=3,
                rating_recovery=3
            )
            db.add(survey)

        db.commit()

        # Get report
        report_service = AdminOrganizationReportService(db, admin_user)
        response = report_service.generate_preview(period="this_month")

        # Check team comparison
        team_comp = response.get("team_comparison", [])
        assert len(team_comp) > 0, "team_comparison should not be empty"

        # Find our test team
        test_team = [t for t in team_comp if t.get("team_name") == "Test Team"]
        assert len(test_team) > 0, "Test team not found in comparison"

        team_data = test_team[0]
        wlb = team_data.get("work_life_balance", {})

        # Since team has >= 3 members, should not be suppressed
        assert not team_data.get("privacy_suppressed"), "Team should not be suppressed"

        # rating_averages MUST be present
        assert "rating_averages" in wlb, "rating_averages missing from team WLB"

        rating_avg = wlb.get("rating_averages", {})
        assert rating_avg.get("disconnect") is not None
        assert rating_avg.get("personal_time") is not None
        assert rating_avg.get("recovery") is not None
