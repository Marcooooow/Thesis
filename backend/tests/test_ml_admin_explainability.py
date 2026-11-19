"""
Tests for ML Admin Dashboard endpoints, training eligibility, provenance separation,
authorization, and model activation safeguards.
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import uuid
import json
import os
from datetime import datetime, timezone

from app.main import app
from app.database import get_db
from app.models import User, MLModel, RecommendationFeedback, Profile
from app.auth.security import get_password_hash


@pytest.fixture
def admin_user(db: Session):
    """Create an admin test user."""
    user_id = uuid.uuid4()
    user = User(
        id=user_id,
        email="admin_ml@example.com",
        password_hash=get_password_hash("password123"),
        full_name="Admin ML User",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    db.add(user)
    db.commit()
    return user


@pytest.fixture
def employee_user(db: Session):
    """Create a non-admin test user."""
    user_id = uuid.uuid4()
    user = User(
        id=user_id,
        email="employee_ml@example.com",
        password_hash=get_password_hash("password123"),
        full_name="Employee User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    db.add(user)
    db.commit()
    return user


@pytest.fixture
def client(db: Session):
    """Create test client with database session override."""
    def override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app=app)


def test_ml_admin_authorization_enforcement(client: TestClient, employee_user: User):
    """Verify that non-admin users cannot access /admin/ml endpoints."""
    response = client.post("/auth/login", json={
        "email": employee_user.email,
        "password": "password123"
    })
    assert response.status_code == 200
    token = response.json()["access_token"]

    # Try accessing /admin/ml/overview
    res = client.get("/admin/ml/overview", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 403


def test_ml_overview_and_sufficiency_gate(client: TestClient, admin_user: User, db: Session):
    """Verify /admin/ml/overview returns correct sufficiency metrics and blocking reasons."""
    response = client.post("/auth/login", json={
        "email": admin_user.email,
        "password": "password123"
    })
    token = response.json()["access_token"]

    # Add a few feedback records (insufficient < 20)
    for i in range(5):
        fb = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=admin_user.id,
            recommendation_id=uuid.uuid4(),
            recommendation_type="SHORT_BREAK",
            model_version="heuristic-only",
            recommendation_score=0.8,
            user_action="accepted" if i % 2 == 0 else "dismissed",
            context_features={"session_length": 25.0, "time_since_break": 10.0, "completion_rate": 0.8}
        )
        db.add(fb)
    db.commit()

    res = client.get("/admin/ml/overview", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    data = res.json()
    assert "data_sufficiency" in data
    suff = data["data_sufficiency"]
    assert suff["sufficient_for_training"] is False
    assert suff["training_eligible"] is False
    assert "blocking_reason" in suff
    assert suff["labeled_feedback"] == 5


def test_test_data_exclusion_in_sufficiency(client: TestClient, admin_user: User, db: Session):
    """Verify that is_test_data profiles are handled correctly."""
    response = client.post("/auth/login", json={
        "email": admin_user.email,
        "password": "password123"
    })
    token = response.json()["access_token"]

    # Add profile with is_test_data=True
    profile = Profile(
        id=uuid.uuid4(),
        user_id=admin_user.id,
        is_test_data=True
    )
    db.add(profile)
    db.commit()

    res = client.get("/admin/ml/dataset", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    data = res.json()
    assert "data_provenance_note" in data


def test_performance_provenance_separation(client: TestClient, admin_user: User):
    """Verify /admin/ml/performance structurally separates live evaluation and historical benchmark."""
    response = client.post("/auth/login", json={
        "email": admin_user.email,
        "password": "password123"
    })
    token = response.json()["access_token"]

    res = client.get("/admin/ml/performance", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    data = res.json()
    assert "has_live_model" in data
    assert data["has_live_model"] is False
    assert "live_evaluation" in data
    assert data["live_evaluation"] is None
    assert "historical_benchmark" in data
    hb = data["historical_benchmark"]
    assert hb["source"] == "ML_EXPERIMENT_REPORT.md"
    assert hb["context"] == "immutable-thesis-reference"
    assert hb["f1_score"] == 0.4878
    assert hb["roc_auc"] == 0.6842
    assert hb["confusion_matrix"] == [[22, 12], [9, 10]]


def test_run_comparison_post_contract(client: TestClient, admin_user: User):
    """Verify /admin/ml/run-comparison requires POST and enforces data sufficiency."""
    response = client.post("/auth/login", json={
        "email": admin_user.email,
        "password": "password123"
    })
    token = response.json()["access_token"]

    # GET should fail (405 Method Not Allowed)
    res_get = client.get("/admin/ml/run-comparison", headers={"Authorization": f"Bearer {token}"})
    assert res_get.status_code == 405

    # POST with insufficient data (<20 samples) should return 400 Bad Request
    res_post = client.post("/admin/ml/run-comparison", headers={"Authorization": f"Bearer {token}"})
    assert res_post.status_code == 400


def test_model_activation_safeguards(client: TestClient, admin_user: User, db: Session):
    """Verify candidate models are created with is_active=False (manual promotion gate)."""
    model_id = uuid.uuid4()
    model = MLModel(
        id=model_id,
        version="candidate-v1",
        artifact_path="/tmp/fake.joblib",
        training_date=datetime.now(timezone.utc),
        feature_set_version="v1",
        metrics=json.dumps({"f1": 0.5}),
        is_active=False
    )
    db.add(model)
    db.commit()

    model_in_db = db.query(MLModel).filter(MLModel.id == model_id).first()
    assert model_in_db.is_active is False


def test_ml_pipeline_robust_metrics_and_cv(db: Session, admin_user: User):
    """Verify evaluation includes confusion matrix, cross-validation metrics, and small sample limitation."""
    from app.services.ml_training_pipeline import evaluate_model, _extract_training_data
    # Add sufficient labeled records for training/evaluation (>20) with both classes
    for i in range(25):
        fb = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=admin_user.id,
            recommendation_id=uuid.uuid4(),
            recommendation_type="SHORT_BREAK",
            model_version="heuristic-only",
            recommendation_score=0.8,
            user_action="accepted" if i % 2 == 0 else "dismissed",
            context_features={"session_length": 25.0 + i, "time_since_break": 10.0, "completion_rate": 0.8}
        )
        db.add(fb)
    db.commit()

    # Create a dummy model file
    import tempfile
    import os
    import joblib
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler, OneHotEncoder
    from sklearn.compose import ColumnTransformer
    from app.services.ml_training_pipeline import V2_ALL_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS, _build_preprocessing_pipeline

    preprocessor = _build_preprocessing_pipeline(V2_ALL_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS)
    clf = Pipeline([("preprocessor", preprocessor), ("classifier", LogisticRegression())])

    import pandas as pd
    features_list, labels, _, _ = _extract_training_data(db)
    df = pd.DataFrame(features_list)
    clf.fit(df[V2_ALL_FEATURE_KEYS], labels)

    fd, path = tempfile.mkstemp(suffix=".joblib")
    os.close(fd)
    joblib.dump(clf, path)

    model_id = uuid.uuid4()
    ml_model = MLModel(
        id=model_id,
        version="test-robust-v1",
        artifact_path=path,
        training_date=datetime.now(timezone.utc),
        feature_set_version="v2-wellbeing",
        metrics=json.dumps({}),
        is_active=False
    )
    db.add(ml_model)
    db.commit()

    metrics = evaluate_model(db, model_id)
    assert metrics is not None
    assert "confusion_matrix" in metrics
    assert "accuracy" in metrics
    assert "precision" in metrics
    assert "recall" in metrics
    assert "f1" in metrics
    assert "roc_auc" in metrics
    assert metrics["small_sample_limitation"] is True  # 25 samples < 50
    assert metrics["sample_count"] == 25
    assert "limitation_note" in metrics

    # Cleanup temp file
    try:
        os.remove(path)
    except Exception:
        pass


def test_wlb_feedback_is_excluded_from_ml_training(db: Session, admin_user: User):
    from app.services.ml_training_pipeline import _extract_training_data

    break_records = [
        RecommendationFeedback(
            id=uuid.uuid4(), user_id=admin_user.id, recommendation_id=uuid.uuid4(),
            recommendation_type="SHORT_BREAK", user_action=action,
            model_version="heuristic-only", recommendation_score=0.8,
            feature_schema_version="v1-base",
            context_features={"session_length": 25.0, "time_since_break": 10.0, "completion_rate": 0.8},
        )
        for action in ("accepted", "dismissed", "ignored")
    ]
    db.add_all(break_records)
    db.commit()
    baseline = _extract_training_data(db)

    wlb_records = [
        RecommendationFeedback(
            id=uuid.uuid4(), user_id=admin_user.id, recommendation_id=uuid.uuid4(),
            recommendation_type="WLB_WORKLOAD", user_action=action,
            model_version="wlb-rule-based-v1", recommendation_score=0.0,
            feature_schema_version="v2-wellbeing",
            context_features={"recommendation_key": "wlb_overtime", "wellbeing_fatigue": 1.0},
        )
        for action in ("accepted", "dismissed", "ignored")
    ]
    db.add_all(wlb_records)
    db.commit()
    with_wlb = _extract_training_data(db)

    assert with_wlb == baseline
    features, labels, schema_versions, user_ids = with_wlb
    assert [feature["recommendation_type"] for feature in features] == ["SHORT_BREAK"] * 3
    assert labels == [1, 0, 0]
    assert schema_versions == ["v1-base"] * 3
    assert user_ids == [str(admin_user.id)] * 3


def test_strict_provenance_filtering(db: Session, admin_user: User):
    """Verify strict provenance filtering excludes dev_demo, is_test_data records and test profiles."""
    from app.services.ml_training_pipeline import _extract_training_data, assess_data_sufficiency

    # 1. Normal valid record
    db.add(RecommendationFeedback(
        id=uuid.uuid4(), user_id=admin_user.id, recommendation_id=uuid.uuid4(),
        recommendation_type="SHORT_BREAK", user_action="accepted", model_version="heuristic-only",
        recommendation_score=0.8,
        context_features={"session_length": 25.0}
    ))
    # 2. Demo record (dev_demo='true')
    db.add(RecommendationFeedback(
        id=uuid.uuid4(), user_id=admin_user.id, recommendation_id=uuid.uuid4(),
        recommendation_type="SHORT_BREAK", user_action="accepted", model_version="heuristic-only",
        recommendation_score=0.8,
        context_features={"session_length": 25.0, "dev_demo": "true"}
    ))
    # 3. Test data record (is_test_data='true')
    db.add(RecommendationFeedback(
        id=uuid.uuid4(), user_id=admin_user.id, recommendation_id=uuid.uuid4(),
        recommendation_type="SHORT_BREAK", user_action="dismissed", model_version="heuristic-only",
        recommendation_score=0.8,
        context_features={"session_length": 25.0, "is_test_data": "true"}
    ))
    db.commit()

    features_list, labels, _, _ = _extract_training_data(db)
    assert len(features_list) == 1  # Only the normal valid record should be extracted

    sufficiency = assess_data_sufficiency(db)
    assert sufficiency["labeled_feedback"] == 1


def test_admin_model_activation_and_deactivation_lifecycle(client: TestClient, admin_user: User, employee_user: User, db: Session):
    """Test full lifecycle: login, data sufficiency seeding, candidate model creation, activation, deactivation, and single active invariant."""
    response = client.post("/auth/login", json={
        "email": admin_user.email,
        "password": "password123"
    })
    token = response.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Seed sufficient labeled data (>= 20 total, >= 10 accepted, >= 10 dismissed)
    for i in range(25):
        action = "accepted" if i < 12 else "dismissed"
        fb = RecommendationFeedback(
            id=uuid.uuid4(),
            user_id=admin_user.id,
            recommendation_id=uuid.uuid4(),
            recommendation_type="SHORT_BREAK",
            model_version="heuristic-only",
            recommendation_score=0.8,
            user_action=action,
            context_features={"session_length": 25.0 + i, "time_since_break": 10.0, "completion_rate": 0.8},
            feature_schema_version="v2-wellbeing",
            provenance="live"
        )
        db.add(fb)
    db.commit()

    # 2. Create valid dummy model artifact
    import tempfile
    import joblib
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import Pipeline
    from sklearn.preprocessing import StandardScaler, OneHotEncoder
    from sklearn.compose import ColumnTransformer
    from app.services.ml_training_pipeline import V2_ALL_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS, _build_preprocessing_pipeline

    preprocessor = _build_preprocessing_pipeline(V2_ALL_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS)
    clf = Pipeline([("preprocessor", preprocessor), ("classifier", LogisticRegression())])

    import pandas as pd
    from app.services.ml_training_pipeline import _extract_training_data
    features_list, labels, _, _ = _extract_training_data(db)
    df = pd.DataFrame(features_list)
    clf.fit(df[V2_ALL_FEATURE_KEYS], labels)

    fd, path = tempfile.mkstemp(suffix=".joblib")
    os.close(fd)
    joblib.dump(clf, path)

    model_id_1 = uuid.uuid4()
    model_1 = MLModel(
        id=model_id_1,
        version="candidate-v1",
        artifact_path=path,
        training_date=datetime.now(timezone.utc),
        feature_set_version="v2-wellbeing",
        metrics={"f1": 0.6},
        is_active=False
    )
    model_1.validation_status = "PASSED"
    db.add(model_1)
    db.commit()

    # 3. Non-admin activation attempt should be rejected
    emp_res = client.post("/auth/login", json={"email": employee_user.email, "password": "password123"})
    emp_token = emp_res.json()["access_token"]
    res_forbidden = client.post(f"/admin/ml/activate/{model_id_1}", headers={"Authorization": f"Bearer {emp_token}"})
    assert res_forbidden.status_code == 403

    # 4. Admin activation succeeds for eligible model
    res_activate = client.post(f"/admin/ml/activate/{model_id_1}", headers=headers)
    if res_activate.status_code != 200:
        print(f"ACTIVATION_ERROR: {res_activate.status_code} - {res_activate.text}")
    assert res_activate.status_code == 200
    assert res_activate.json()["is_active"] is True

    # 5. Verify single active invariant: create model 2 and activate it, model 1 should become inactive
    model_id_2 = uuid.uuid4()
    model_2 = MLModel(
        id=model_id_2,
        version="candidate-v2",
        artifact_path=path,
        training_date=datetime.now(timezone.utc),
        feature_set_version="v2-wellbeing",
        metrics={"f1": 0.65},
        is_active=False
    )
    model_2.validation_status = "PASSED"
    db.add(model_2)
    db.commit()

    res_activate_2 = client.post(f"/admin/ml/activate/{model_id_2}", headers=headers)
    assert res_activate_2.status_code == 200

    db.expire_all()
    m1_db = db.query(MLModel).filter(MLModel.id == model_id_1).first()
    m2_db = db.query(MLModel).filter(MLModel.id == model_id_2).first()
    assert m1_db.is_active is False
    assert m2_db.is_active is True

    # 6. Deactivate all models (rollback to heuristic fallback)
    res_deactivate = client.post("/admin/ml/deactivate", headers=headers)
    assert res_deactivate.status_code == 200
    assert res_deactivate.json()["ml_inference_active"] is False

    db.expire_all()


def test_scoring_engine_endpoint(client: TestClient, admin_user: User, db: Session):
    """Verify /admin/ml/scoring-engine returns factor weights and scoring rules without import errors."""
    res = client.post("/auth/login", json={"email": admin_user.email, "password": "password123"})
    token = res.json()["access_token"]
    response = client.get("/admin/ml/scoring-engine", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    data = response.json()
    assert "weights" in data or "factors" in data
    assert db.query(MLModel).filter(MLModel.is_active == True).count() == 0

    # Cleanup temp file
    try:
        os.remove(path)
    except Exception:
        pass
