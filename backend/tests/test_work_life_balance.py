import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.auth.security import get_password_hash, create_access_token
from app import models
import uuid
from datetime import date, datetime, timezone, timedelta

client = TestClient(app)

def test_wlb_survey_scoring_extremes_and_mixed(test_db):
    unique_id = str(uuid.uuid4())[:8]
    org = models.Organization(name=f"Org WLB Test {unique_id}")
    test_db.add(org)
    test_db.commit()
    test_db.refresh(org)

    emp_user = models.User(
        email=f"emp_wlb_test_{unique_id}@test.com", full_name="Emp WLB Test", role="EMPLOYEE",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user)
    test_db.commit()
    test_db.refresh(emp_user)

    emp_profile = models.Profile(user_id=emp_user.id, target_daily_hours=8, is_test_data=False)
    test_db.add(emp_profile)
    test_db.commit()

    test_db.add(models.OrganizationMembership(user_id=emp_user.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
    test_db.commit()

    token = create_access_token(data={"sub": emp_user.email})
    headers = {"Authorization": f"Bearer {token}"}

    today = date.today()
    monday = today - timedelta(days=today.weekday())

    # 1. All ratings equal to 1 -> score 0
    payload_min = {
        "week_start_date": str(monday),
        "rating_disconnect": 1,
        "rating_personal_time": 1,
        "rating_responsibilities_balance": 1,
        "rating_schedule_satisfaction": 1,
        "rating_recovery": 1
    }
    res = client.post("/wlb/survey", json=payload_min, headers=headers)
    assert res.status_code == 201
    assert res.json()["score"] == 0.0

    # 2. Duplicate submission returns HTTP 409
    res_dup = client.post("/wlb/survey", json=payload_min, headers=headers)
    assert res_dup.status_code == 409

    # Create employee 2 for max score and mixed score on different weeks
    emp_user2 = models.User(
        email=f"emp_wlb_test2_{unique_id}@test.com", full_name="Emp WLB Test 2", role="EMPLOYEE",
        account_type="organization", approval_status="APPROVED", is_active=True,
        password_hash=get_password_hash("testpass")
    )
    test_db.add(emp_user2)
    test_db.commit()
    test_db.refresh(emp_user2)

    emp_profile2 = models.Profile(user_id=emp_user2.id, target_daily_hours=8, is_test_data=False)
    test_db.add(emp_profile2)
    test_db.commit()
    test_db.add(models.OrganizationMembership(user_id=emp_user2.id, organization_id=org.id, role="EMPLOYEE", status="APPROVED"))
    test_db.commit()

    token2 = create_access_token(data={"sub": emp_user2.email})
    headers2 = {"Authorization": f"Bearer {token2}"}

    week_last = monday - timedelta(days=7)
    # 3. All ratings equal to 5 -> score 100
    payload_max = {
        "week_start_date": str(week_last),
        "rating_disconnect": 5,
        "rating_personal_time": 5,
        "rating_responsibilities_balance": 5,
        "rating_schedule_satisfaction": 5,
        "rating_recovery": 5
    }
    res_max = client.post("/wlb/survey", json=payload_max, headers=headers2)
    assert res_max.status_code == 201
    assert res_max.json()["score"] == 100.0

    # 4. Mixed ratings (e.g. 3, 3, 3, 3, 3 -> sum 15 -> ((15-5)/20)*100 = 50.0)
    week_prev = monday - timedelta(days=14)
    payload_mixed = {
        "week_start_date": str(week_prev),
        "rating_disconnect": 3,
        "rating_personal_time": 3,
        "rating_responsibilities_balance": 3,
        "rating_schedule_satisfaction": 3,
        "rating_recovery": 3
    }
    res_mixed = client.post("/wlb/survey", json=payload_mixed, headers=headers2)
    assert res_mixed.status_code == 201
    assert res_mixed.json()["score"] == 50.0

    # 5. Missing answers rejected (Pydantic validation)
    payload_missing = {
        "week_start_date": str(monday - timedelta(days=21)),
        "rating_disconnect": 3,
        "rating_personal_time": 3
    }
    res_missing = client.post("/wlb/survey", json=payload_missing, headers=headers2)
    assert res_missing.status_code == 422

    # 6. Ratings below 1 or above 5 rejected
    payload_out_of_bounds = {
        "week_start_date": str(monday - timedelta(days=21)),
        "rating_disconnect": 0,
        "rating_personal_time": 3,
        "rating_responsibilities_balance": 3,
        "rating_schedule_satisfaction": 3,
        "rating_recovery": 3
    }
    res_oob = client.post("/wlb/survey", json=payload_out_of_bounds, headers=headers2)
    assert res_oob.status_code == 422

    # 7. History returns only authenticated employee's records
    res_hist1 = client.get("/wlb/survey/history", headers=headers)
    assert res_hist1.status_code == 200
    assert len(res_hist1.json()) == 1

    res_hist2 = client.get("/wlb/survey/history", headers=headers2)
    assert res_hist2.status_code == 200
    assert len(res_hist2.json()) == 2

    # 8. Check week boundary endpoint
    res_check = client.get("/wlb/survey/check", headers=headers, params={"week_start_date": str(monday)})
    assert res_check.status_code == 200
    assert res_check.json()["submitted"] is True
    assert res_check.json()["survey"]["score"] == 0.0
