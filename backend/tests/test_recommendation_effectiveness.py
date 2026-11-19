import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import datetime, timezone, timedelta

client = TestClient(app)

def test_recommendation_effectiveness_comprehensive(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org Comp Rec {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    admin_user = models.User(
        email=f"admin_comprec_{unique_id}@test.com", full_name="Admin Comp Rec", role="ADMIN",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(admin_user)
    test_db.commit()
    test_db.refresh(admin_user)
    test_db.add(models.OrganizationMembership(user_id=admin_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    # Team 1: 3 employees (not suppressed, N >= 3)
    team1 = models.Team(name="Team Alpha", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team1)
    test_db.commit()
    test_db.refresh(team1)

    profile_ids_1 = []
    for i in range(3):
        emp = models.User(
            email=f"emp1_{i}_{unique_id}@test.com", full_name=f"Emp 1-{i}", role="EMPLOYEE",
            account_type="organization", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(emp)
        test_db.commit()
        test_db.refresh(emp)
        prof = models.Profile(user_id=emp.id, target_daily_hours=8, is_test_data=False)
        test_db.add(prof)
        test_db.commit()
        test_db.refresh(prof)
        profile_ids_1.append(prof.id)
        test_db.add(models.OrganizationMembership(user_id=emp.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
        test_db.add(models.TeamMembership(team_id=team1.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

        # Nov 3, 2026 is Tuesday
        t_nov3 = datetime(2026, 11, 3, 10, 0, 0, tzinfo=timezone.utc)
        rec_id = uuid.uuid4()
        # Feedback with response (accepted, trackable type SHORT_BREAK with break action)
        fb1 = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=rec_id,
            model_version="cold-start-baseline",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.9,
            context_features={},
            timestamp=t_nov3,
            user_action="accepted",
            break_started_at=t_nov3 + timedelta(minutes=5)
        )
        # Duplicate feedback event for same recommendation_id (should not double count unique recommendation)
        fb1_dup = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=rec_id,
            model_version="cold-start-baseline",
            recommendation_type="SHORT_BREAK",
            recommendation_score=0.9,
            context_features={},
            timestamp=t_nov3 + timedelta(minutes=1),
            user_action="accepted",
            break_started_at=t_nov3 + timedelta(minutes=5)
        )
        # Dismissed recommendation (WALK - trackable)
        fb2 = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=uuid.uuid4(),
            model_version="cold-start-baseline",
            recommendation_type="WALK",
            recommendation_score=0.8,
            context_features={},
            timestamp=t_nov3 + timedelta(hours=1),
            user_action="dismissed"
        )
        # Pending recommendation (user_action is None - should NOT count as having feedback)
        fb3 = models.RecommendationFeedback(
            user_id=emp.id,
            recommendation_id=uuid.uuid4(),
            model_version="cold-start-baseline",
            recommendation_type="HYDRATE", # unsupported action type
            recommendation_score=0.7,
            context_features={},
            timestamp=t_nov3 + timedelta(hours=2),
            user_action=None
        )
        test_db.add_all([fb1, fb1_dup, fb2, fb3])
        test_db.commit()

    # Team 2: 2 employees (suppressed N < 3)
    team2 = models.Team(name="Team Beta", organization_id=org.id, manager_user_id=admin_user.id, is_active=True)
    test_db.add(team2)
    test_db.commit()
    test_db.refresh(team2)

    for i in range(2):
        emp = models.User(
            email=f"emp2_{i}_{unique_id}@test.com", full_name=f"Emp 2-{i}", role="EMPLOYEE",
            account_type="organization", approval_status="APPROVED", is_active=True,
            password_hash=get_password_hash("testpass")
        )
        test_db.add(emp)
        test_db.commit()
        test_db.refresh(emp)
        prof = models.Profile(user_id=emp.id, target_daily_hours=8, is_test_data=False)
        test_db.add(prof)
        test_db.commit()
        test_db.refresh(prof)
        test_db.add(models.OrganizationMembership(user_id=emp.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
        test_db.add(models.TeamMembership(team_id=team2.id, profile_id=prof.id, role="EMPLOYEE"))
        test_db.commit()

    admin_token = create_access_token(data={"sub": admin_user.email})
    headers = {"Authorization": f"Bearer {admin_token}"}

    res = client.get("/analytics/admin/recommendation-effectiveness", headers=headers, params={
        "start_date": "2026-11-01",
        "end_date": "2026-11-05"
    })
    assert res.status_code == 200
    data = res.json()

    # Verify Team 2 suppression (N=2 < 3)
    team_beta = next(t for t in data["teams"] if t["team_name"] == "Team Beta")
    assert team_beta["privacy_suppressed"] is True
    assert team_beta["generated_count"] is None
    assert team_beta["accepted_count"] is None
    assert team_beta["acceptance_rate"] is None

    # Verify Team Alpha (N=3 >= 3)
    team_alpha = next(t for t in data["teams"] if t["team_name"] == "Team Alpha")
    assert team_alpha["privacy_suppressed"] is False
    assert team_alpha["generated_count"] == 9 # 3 employees * 3 unique recs (fb1, fb2, fb3)
    assert team_alpha["accepted_count"] == 3
    assert team_alpha["dismissed_count"] == 3

    # Verify historical weekday label for Nov 3, 2026 (Tue)
    nov3_trend = next((t for t in data["historical_trends"] if t["date"] == "2026-11-03"), None)
    assert nov3_trend is not None
    assert nov3_trend["day"] == "Tue"

    # Test unauthorized access (employee role)
    emp_token = create_access_token(data={"sub": f"emp1_0_{unique_id}@test.com"})
    emp_headers = {"Authorization": f"Bearer {emp_token}"}
    res_unauth = client.get("/analytics/admin/recommendation-effectiveness", headers=emp_headers)
    assert res_unauth.status_code == 403
