import uuid
from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.auth.security import create_access_token, get_password_hash
from app.database import get_db
from app.main import app
from app.models import (
    Organization, Profile, RecommendationFeedback, SessionWellbeingCheckin,
    User, WorkLifeBalanceSurvey, WorkSession,
)
from app.services.wlb_analysis_service import wlb_recommendation_uuid


@pytest.fixture
def client(test_db):
    def override_get_db():
        yield test_db

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_wlb_feedback_actions_persist_distinctly_for_owner(client, test_db):
    user = User(
        email=f"wlb-feedback-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="WLB Feedback User",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()
    headers = {"Authorization": f"Bearer {create_access_token(data={'sub': user.email})}"}

    # Get actual recommendations for this profile to find the correct recommendation key
    from app.services.wlb_analysis_service import WLBAnalysisService
    service = WLBAnalysisService(test_db)
    current_monday = date.today() - timedelta(days=date.today().weekday())
    analysis = service.get_weekly_wlb_analysis(profile.id, current_monday)
    # Use the first available recommendation
    active_recommendation = analysis.get("recommendations", [{}])[0]
    recommendation_key = active_recommendation.get("id", "wlb_moderate_1")
    recommendation_id = wlb_recommendation_uuid(
        profile.id, current_monday, recommendation_key
    )

    # Debug the recommendation
    print(f"DEBUG: analysis.recommendations = {analysis.get('recommendations')}")
    print(f"DEBUG: active_recommendation = {active_recommendation}")
    print(f"DEBUG: recommendation_key = {recommendation_key}")
    print(f"DEBUG: recommendation_id = {recommendation_id}")

    for action in ("accepted", "helpful", "not_helpful", "dismissed"):
        # Debug: show what we're looking up
        import uuid as uuid_mod
        api_uuid = uuid_mod.uuid5(uuid_mod.NAMESPACE_URL, f"intellibreak:wlb:{profile.id}:{current_monday.isoformat()}:{recommendation_key}")
        print(f"DEBUG TEST: recommendation_key={recommendation_key}, profile.id={profile.id}, current_monday={current_monday}, test generates={recommendation_id}, api would generate={api_uuid}")
        response = client.post(
            "/recommend/feedback",
            json={"recommendation_id": str(recommendation_id), "user_action": action},
            headers=headers,
        )
        print(f"DEBUG: response={response.status_code}, body={response.json() if response.status_code != 500 else 'error'}")
        assert response.status_code == 200
        assert response.json()["user_action"] == action
        record = test_db.query(RecommendationFeedback).filter_by(
            recommendation_id=recommendation_id, user_id=user.id
        ).one()
        assert record.user_action == action
        assert record.recommendation_type.startswith("WLB_")


def test_wlb_feedback_action_cannot_update_another_users_record(client, test_db):
    owner = User(
        email=f"wlb-owner-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Owner",
        approval_status="APPROVED",
        is_active=True,
    )
    stranger = User(
        email=f"wlb-stranger-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Stranger",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add_all([owner, stranger])
    test_db.flush()
    owner_profile = Profile(user_id=owner.id)
    test_db.add_all([owner_profile, Profile(user_id=stranger.id)])
    test_db.flush()

    # Get actual recommendation for owner
    from app.services.wlb_analysis_service import WLBAnalysisService
    service = WLBAnalysisService(test_db)
    current_monday = date.today() - timedelta(days=date.today().weekday())
    analysis = service.get_weekly_wlb_analysis(owner_profile.id, current_monday)
    active_recommendation = analysis.get("recommendations", [{}])[0]
    recommendation_key = active_recommendation.get("id", "wlb_moderate_1")
    recommendation_id = wlb_recommendation_uuid(
        owner_profile.id, current_monday, recommendation_key
    )
    feedback = RecommendationFeedback(
        recommendation_id=recommendation_id,
        user_id=owner.id,
        model_version="wlb-rule-based-v1",
        recommendation_type=f"WLB_{active_recommendation.get('category', 'MAINTENANCE')}",
        recommendation_score=0.0,
        context_features={"recommendation_key": recommendation_key},
        feature_schema_version="v2-wellbeing",
        reason=active_recommendation.get("title", "Maintain current habits"),
    )
    test_db.add(feedback)
    test_db.commit()

    response = client.post(
        "/recommend/feedback",
        json={"recommendation_id": str(recommendation_id), "user_action": "helpful"},
        headers={"Authorization": f"Bearer {create_access_token(data={'sub': stranger.email})}"},
    )

    assert response.status_code == 404
    test_db.refresh(feedback)
    assert feedback.user_action is None


def test_wlb_feedback_rejects_id_for_non_current_recommendation(client, test_db):
    user = User(
        email=f"wlb-stale-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Stale Recommendation User",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()
    test_db.add(Profile(user_id=user.id))
    stale_id = uuid.uuid4()
    stale_feedback = RecommendationFeedback(
        recommendation_id=stale_id,
        user_id=user.id,
        model_version="wlb-rule-based-v1",
        recommendation_type="WLB_WORKLOAD",
        recommendation_score=0.0,
        context_features={"recommendation_key": "wlb_overtime"},
        feature_schema_version="v2-wellbeing",
        reason="Stale recommendation",
    )
    test_db.add(stale_feedback)
    test_db.commit()

    response = client.post(
        "/recommend/feedback",
        json={"recommendation_id": str(stale_id), "user_action": "helpful"},
        headers={"Authorization": f"Bearer {create_access_token(data={'sub': user.email})}"},
    )

    assert response.status_code == 404
    test_db.refresh(stale_feedback)
    assert stale_feedback.user_action is None


def test_wellness_summary_exposes_stable_ids_and_no_survey_responses(client, test_db):
    user = User(
        email=f"wlb-summary-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Summary User",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()
    organization = Organization(name=f"WLB Org {uuid.uuid4()}")
    test_db.add(organization)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.flush()
    this_monday = date.today() - timedelta(days=date.today().weekday())
    previous_monday = this_monday - timedelta(days=7)
    for week_start, score in ((previous_monday, 75), (this_monday, 0)):
        rating = 1 if score == 0 else 4
        test_db.add(WorkLifeBalanceSurvey(
            profile_id=profile.id,
            organization_id=organization.id,
            week_start_date=week_start,
            rating_disconnect=rating,
            rating_personal_time=rating,
            rating_responsibilities_balance=rating,
            rating_schedule_satisfaction=rating,
            rating_recovery=rating,
            score=score,
        ))
    test_db.commit()
    headers = {"Authorization": f"Bearer {create_access_token(data={'sub': user.email})}"}

    response = client.get("/analytics/wellness/summary", headers=headers)
    assert response.status_code == 200
    summary = response.json()
    comparison = summary["wlb_analysis"]["weekly_comparison"]
    assert comparison["has_comparison"] is True
    assert comparison["previous_week"]["wlb_score"] == 75
    assert comparison["current_week"]["wlb_score"] == 0
    assert comparison["score_change"] == -75
    assert "responses" not in (summary["wlb_analysis"].get("survey") or {})
    evidence_text = str(summary["combined_evidence"])
    for private_label in (
        "disconnecting from work", "personal/family time",
        "schedule satisfaction", "recovery after work", "Rated 1/5", "Rated 2/5",
    ):
        assert private_label not in evidence_text
    assert "self-reported fatigue" not in evidence_text.lower()
    assert "workload manageability" not in evidence_text.lower()
    assert "overall wellbeing" not in evidence_text.lower()
    session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.combine(
            this_monday, datetime.min.time(), tzinfo=timezone.utc
        ) + timedelta(hours=9),
        ended_at=datetime.combine(
            this_monday, datetime.min.time(), tzinfo=timezone.utc
        ) + timedelta(hours=17),
    )
    test_db.add(session)
    test_db.flush()
    test_db.add(SessionWellbeingCheckin(
        user_id=user.id,
        work_session_id=session.id,
        overall_wellbeing=1,
        mental_fatigue=5,
        workload_manageability=1,
        perceived_focus=2,
        break_recovery=1,
        stress_factors=["deadlines"],
        notes="private wellbeing note",
    ))
    test_db.commit()
    response = client.get("/analytics/wellness/summary", headers=headers)
    assert response.status_code == 200
    assert "private wellbeing note" not in str(response.json())
    assert "deadlines" not in str(response.json())
    recommendation = summary["wlb_recommendations"][0]
    assert recommendation["reason"]
    assert recommendation["action_step"]
    assert "Monitor" in recommendation["expected_outcome"]
    assert "not guaranteed" in recommendation["expected_outcome"]
    assert uuid.UUID(recommendation["id"])
    assert recommendation["recommendation_key"]
    first_id = recommendation["id"]
    second = client.get("/analytics/wellness/summary", headers=headers).json()
    assert second["wlb_recommendations"][0]["id"] == first_id
    assert test_db.query(RecommendationFeedback).filter_by(user_id=user.id).count() == 0


def test_wellness_summary_does_not_claim_comparison_without_two_surveys(client, test_db):
    user = User(
        email=f"wlb-no-history-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="No History User",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.flush()
    organization = Organization(name=f"No History Org {uuid.uuid4()}")
    test_db.add(organization)
    test_db.flush()
    this_monday = date.today() - timedelta(days=date.today().weekday())
    test_db.add(WorkLifeBalanceSurvey(
        profile_id=profile.id,
        organization_id=organization.id,
        week_start_date=this_monday,
        rating_disconnect=4,
        rating_personal_time=4,
        rating_responsibilities_balance=4,
        rating_schedule_satisfaction=4,
        rating_recovery=4,
        score=75,
    ))
    test_db.commit()

    response = client.get(
        "/analytics/wellness/summary",
        headers={"Authorization": f"Bearer {create_access_token(data={'sub': user.email})}"},
    )

    assert response.status_code == 200
    comparison = response.json()["wlb_analysis"]["weekly_comparison"]
    assert comparison["has_comparison"] is False
    assert comparison["score_change"] is None


def test_feedback_endpoint_rejects_unknown_action(client, test_db):
    user = User(
        email=f"wlb-invalid-{uuid.uuid4()}@intellibreak.local",
        password_hash=get_password_hash("testpassword123"),
        full_name="Invalid Action User",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.flush()
    test_db.add(Profile(user_id=user.id))
    test_db.commit()

    response = client.post(
        "/recommend/feedback",
        json={"recommendation_id": str(uuid.uuid4()), "user_action": "unrecognized"},
        headers={"Authorization": f"Bearer {create_access_token(data={'sub': user.email})}"},
    )
    assert response.status_code == 400
