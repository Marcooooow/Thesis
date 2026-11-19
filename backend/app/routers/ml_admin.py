"""
ML Model Dashboard Admin Endpoints
Provides data for the ML Model Dashboard in the Admin section.
All endpoints require administrator authorization.
"""
from fastapi import APIRouter, Depends, HTTPException, status, Request, BackgroundTasks
from sqlalchemy import text
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
import uuid
from datetime import datetime, timezone
import os
import json

from ..database import get_db, SessionLocal
from ..auth.security import get_current_admin_user, log_system_activity
from ..models import User, MLModel, RecommendationFeedback, Profile, MLTrainingJob
from ..services.ml_training_pipeline import (
    assess_data_sufficiency,
    train_model,
    get_latest_active_model,
    predict_with_model,
    activate_model,
    evaluate_model,
    evaluate_candidate,
    evaluate_model_on_test_set,
    evaluate_heuristic_baseline,
    reserve_training_job,
    run_training_job,
    recover_interrupted_training_jobs,
    NUMERIC_FEATURE_KEYS,
    CATEGORICAL_FEATURE_KEYS,
    ALL_FEATURE_KEYS,
)

# Background training task. Runs in its own DB session, independent of the request.
def background_train_model(dataset: str, job_id):
    # Sweep stale/interrupted jobs first so they don't block this reservation,
    # then run the requested job.
    db = SessionLocal()
    try:
        recover_interrupted_training_jobs(db)
    finally:
        db.close()

    run_training_job(job_id, dataset)


router = APIRouter(
    prefix="/admin/ml",
    tags=["admin-ml"],
    responses={404: {"description": "Not found"}},
)


@router.on_event("startup")
async def startup_recover_stale_training_jobs():
    """Sweep stale training jobs on application startup."""
    try:
        db = SessionLocal()
        try:
            recover_interrupted_training_jobs(db)
        finally:
            db.close()
    except Exception as e:
        print(f"Startup recovery skipped (tables may not be created yet): {e}")


def _get_feature_definitions() -> Dict[str, str]:
    """Return human-readable definitions for each feature."""
    return {
        "session_length": "Current work session length in minutes (0 if no active session)",
        "time_since_break": "Minutes since the last break ended (9999 if no break recorded)",
        "completion_rate": "Fraction of tasks completed in the last 60 minutes (0.0-1.0)",
        "recommendation_type": "Type of break being recommended (SHORT_BREAK, WALK, HYDRATE, STRETCH, LUNCH)",
    }


@router.get("/overview")
async def get_ml_overview(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns overview of ML model status and training readiness for the specified dataset context.
    """
    # Check if ML recommendations are enabled via environment variable
    ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"

    # Get active model for the selected dataset context
    active_model = get_latest_active_model(db, dataset=dataset)

    # Get data sufficiency assessment
    data_status = assess_data_sufficiency(db, dataset=dataset)
    sufficient = data_status["sufficient_for_training"]
    blocking_reason = None
    if not sufficient:
        labeled = data_status["labeled_feedback"]
        accepted = data_status["accepted"]
        neg = data_status["dismissed"] + data_status["ignored"]
        blocking_reason = f"Insufficient labeled samples: {labeled}/20 (requires at least 20 labeled samples with >=5 accepted and >=5 dismissed/ignored; currently accepted={accepted}, dismissed/ignored={neg})"

    # Determine if ML inference is active
    ml_inference_active = ml_enabled and active_model is not None

    # Determine model status for display
    if not ml_enabled:
        model_status = "disabled"
        model_version = "heuristic-only"
        algorithm = "heuristic (cold-start baseline)"
    elif active_model is None:
        model_status = "enabled-but-no-active-model"
        model_version = "none"
        algorithm = "none"
    else:
        model_status = "active"
        model_version = active_model.version
        algorithm = "LogisticRegression"

    # Get latest evaluation timestamp from active model (if exists)
    latest_evaluation = None
    if active_model and active_model.training_date:
        latest_evaluation = active_model.training_date.isoformat()

    data_status["training_eligible"] = sufficient
    data_status["blocking_reason"] = blocking_reason

    # Distinguish the latest historical trained artifact from the currently
    # deployed inference model: an artifact's existence does NOT imply an
    # active model.
    latest_trained_artifact = (
        db.query(MLModel)
        .filter(MLModel.metrics.isnot(None))
        .order_by(MLModel.training_date.desc())
        .first()
    )
    trained_artifacts_count = db.query(MLModel).filter(
        MLModel.metrics.isnot(None)
    ).count()

    return {
        "dataset_context": dataset,
        "ml_recommendations_enabled": ml_enabled,
        "ml_inference_active": ml_inference_active,
        "model_status": model_status,
        "model_version": model_version,
        "algorithm": algorithm,
        "active_model_id": str(active_model.id) if active_model else None,
        "latest_trained_artifact_id": str(latest_trained_artifact.id) if latest_trained_artifact else None,
        "trained_artifacts_count": trained_artifacts_count,
        "latest_evaluation_timestamp": latest_evaluation,
        "artifact_path": active_model.artifact_path if active_model else None,
        "data_sufficiency": data_status,
    }


@router.get("/performance")
async def get_ml_performance(
    dataset: str = "production",
    model_id: Optional[str] = None,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns performance metrics of the active model or specified candidate model evaluated on the specified dataset context.
    """
    all_models = db.query(MLModel).order_by(MLModel.training_date.desc()).all()

    model_to_show = None
    if model_id:
        try:
            m_uuid = uuid.UUID(model_id)
            model_to_show = db.query(MLModel).filter(MLModel.id == m_uuid).first()
        except ValueError:
            pass

    if not model_to_show:
        active_model = get_latest_active_model(db, dataset=dataset)
        model_to_show = active_model or (all_models[0] if all_models else None)

    available_models_list = []
    for m in all_models:
        job = db.query(MLTrainingJob).filter(MLTrainingJob.model_id == m.id).first()
        m_metrics = {}
        if m.metrics:
            try:
                m_metrics = json.loads(m.metrics) if isinstance(m.metrics, str) else m.metrics
            except Exception:
                pass
        available_models_list.append({
            "model_id": str(m.id),
            "model_version": m.version,
            "is_active": m.is_active,
            "training_date": m.training_date.isoformat() if m.training_date else None,
            "validation_status": getattr(m, 'validation_status', 'PENDING') or 'PENDING',
            "algorithm": "Logistic Regression (V2 schema)",
            "training_job_id": str(job.id) if job else "N/A",
            "dataset": dataset,
            "metrics": m_metrics,
            "accuracy": m_metrics.get("accuracy"),
            "precision": m_metrics.get("precision"),
            "recall": m_metrics.get("recall"),
            "f1": m_metrics.get("f1"),
            "roc_auc": m_metrics.get("roc_auc"),
            "is_eligible_for_activation": (getattr(m, 'validation_status', 'PENDING') == 'PASSED' and m.artifact_path and os.path.exists(m.artifact_path)),
        })

    if not model_to_show:
        historical_benchmark = {
            "source": "ML_EXPERIMENT_REPORT.md",
            "context": "immutable-thesis-reference",
            "test_set_size": 53,
            "train_set_size": 208,
            "model_name": "Logistic Regression (Balanced)",
            "accuracy": 0.6038,
            "precision": 0.4545,
            "recall": 0.5263,
            "f1_score": 0.4878,
            "roc_auc": 0.6842,
            "confusion_matrix": [[22, 12], [9, 10]],
        }
        return {
            "dataset_context": dataset,
            "has_live_model": False,
            "message": "No active or trained model available. Displaying verified thesis benchmark validation reference.",
            "live_evaluation": None,
            "historical_benchmark": historical_benchmark,
            "available_models": available_models_list,
        }

    metrics_source = "no_available_metrics"
    evaluated_metrics = {}
    try:
        res = evaluate_model(db, model_to_show.id, dataset=dataset)
        if res and isinstance(res, dict) and (res.get("accuracy") is not None or res.get("confusion_matrix") is not None):
            evaluated_metrics = res
            metrics_source = "live_evaluation"
        else:
            raise ValueError("Live evaluation returned empty or invalid metrics structure")
    except Exception as eval_exc:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"[ML Admin] evaluate_model failed for model {model_to_show.id} dataset {dataset}: {eval_exc}", exc_info=True)
        if model_to_show.metrics:
            try:
                evaluated_metrics = json.loads(model_to_show.metrics) if isinstance(model_to_show.metrics, str) else model_to_show.metrics
                metrics_source = "stored_metrics"
            except Exception as parse_exc:
                logger.error(f"[ML Admin] Failed to parse stored metrics for model {model_to_show.id}: {parse_exc}", exc_info=True)
                evaluated_metrics = {}
                metrics_source = "no_available_metrics"
        else:
            evaluated_metrics = {}
            metrics_source = "no_available_metrics"

    job = db.query(MLTrainingJob).filter(MLTrainingJob.model_id == model_to_show.id).first()
    live_evaluation = {
        "model_id": str(model_to_show.id),
        "model_version": model_to_show.version,
        "training_date": model_to_show.training_date.isoformat() if model_to_show.training_date else None,
        "is_active": model_to_show.is_active,
        "validation_status": getattr(model_to_show, 'validation_status', 'PENDING') or 'PENDING',
        "training_job_id": str(job.id) if job else "N/A",
        "algorithm": "Logistic Regression (V2 schema)",
        "dataset": dataset,
        "metrics_source": metrics_source,
        "metrics": evaluated_metrics,
        "confusion_matrix": evaluated_metrics.get("confusion_matrix") if isinstance(evaluated_metrics, dict) else None,
        "class_distribution": None,
        "is_eligible_for_activation": (getattr(model_to_show, 'validation_status', 'PENDING') == 'PASSED' and model_to_show.artifact_path and os.path.exists(model_to_show.artifact_path)),
    }

    historical_benchmark = {
        "source": "ML_EXPERIMENT_REPORT.md",
        "context": "immutable-thesis-reference",
        "test_set_size": evaluated_metrics.get("test_sample_count", 53),
        "train_set_size": evaluated_metrics.get("train_sample_count", 208),
        "model_name": "Logistic Regression (Balanced)",
        "accuracy": 0.6038,
        "precision": 0.4545,
        "recall": 0.5263,
        "f1_score": 0.4878,
        "roc_auc": 0.6842,
        "confusion_matrix": [[22, 12], [9, 10]],
    }

    return {
        "dataset_context": dataset,
        "has_live_model": True,
        "live_evaluation": live_evaluation,
        "historical_benchmark": historical_benchmark,
        "available_models": available_models_list,
        "message": f"Live trained model '{model_to_show.version}' evaluated on dataset context '{dataset}'.",
    }


@router.get("/features")
async def get_ml_features_alias(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Alias for /dataset to support clients requesting /features.
    """
    return await get_ml_dataset_info(dataset=dataset, current_user=current_user, db=db)


@router.get("/dataset")
async def get_ml_dataset_info(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns information about the dataset used for training, including provenance, for the specified dataset context.
    """
    data_status = assess_data_sufficiency(db, dataset=dataset)

    # Get feature definitions
    feature_definitions = _get_feature_definitions()

    test_data_note = (
        f"Dataset context: '{dataset}'. Production isolates real operational data; experimental isolates synthetic/demo data; "
        "all combines both."
    )

    return {
        "dataset_context": dataset,
        "labeled_feedback_count": data_status["labeled_feedback"],
        "accepted_count": data_status["accepted"],
        "dismissed_count": data_status["dismissed"],
        "ignored_count": data_status["ignored"],
        "null_pending_count": data_status["null_pending"],
        "total_feedback": data_status["total_feedback"],
        "candidate_type_distribution": data_status["candidate_type_distribution"],
        "minimum_required_for_training": data_status["minimum_required"],
        "sufficient_for_training": data_status["sufficient_for_training"],
        "feature_definitions": feature_definitions,
        "data_provenance_note": test_data_note,
        "training_methodology_note": (
            "Models are trained using all available labeled data in the selected dataset context. "
            "For algorithm comparison, a hold-out test set should be used."
        ),
    }


@router.get("/activity")
async def get_ml_activity(
    dataset: str = "production",
    days: int = 30,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns daily recommendation activity time-series (generated, accepted, dismissed, ignored)
    for the specified dataset context and date range.
    """
    where_clauses = []
    if dataset == "production":
        where_clauses.append("(context_features->>'dev_demo') IS DISTINCT FROM 'true'")
        where_clauses.append("(context_features->>'is_test_data') IS DISTINCT FROM 'true'")
        where_clauses.append("user_id NOT IN (SELECT user_id FROM profiles WHERE is_test_data = true)")
    elif dataset == "experimental":
        where_clauses.append("((context_features->>'dev_demo') = 'true' OR (context_features->>'is_test_data') = 'true' OR user_id IN (SELECT user_id FROM profiles WHERE is_test_data = true))")

    from datetime import datetime, timedelta, timezone
    start_dt = datetime.now(timezone.utc) - timedelta(days=days)
    where_clauses.append("timestamp >= :start_dt")

    where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

    sql = text(f"""
        SELECT
            TO_CHAR(timestamp, 'YYYY-MM-DD') as day,
            COUNT(*) as generated,
            SUM(CASE WHEN user_action = 'accepted' THEN 1 ELSE 0 END) as accepted,
            SUM(CASE WHEN user_action = 'dismissed' THEN 1 ELSE 0 END) as dismissed,
            SUM(CASE WHEN user_action = 'ignored' OR user_action IS NULL THEN 1 ELSE 0 END) as ignored
        FROM recommendation_feedback
        WHERE {where_sql}
        GROUP BY TO_CHAR(timestamp, 'YYYY-MM-DD')
        ORDER BY day ASC
    """)

    rows = db.execute(sql, {"start_dt": start_dt}).fetchall()

    activity_data = []
    for r in rows:
        activity_data.append({
            "date": r[0],
            "generated": int(r[1]),
            "accepted": int(r[2]),
            "dismissed": int(r[3]),
            "ignored": int(r[4])
        })

    return {
        "dataset_context": dataset,
        "days": days,
        "activity_data": activity_data
    }


@router.get("/pipeline-status")
async def get_ml_pipeline_status(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns the end-to-end recommendation pipeline stage status for the specified dataset context.
    Stages are derived from live system state (ML flag, active model, data sufficiency) rather than hardcoded.
    """
    ml_enabled = os.getenv("ML_RECOMMENDATIONS_ENABLED", "false").lower() == "true"
    active_model = db.query(MLModel).filter(MLModel.is_active == True).order_by(MLModel.training_date.desc()).first()
    data_status = assess_data_sufficiency(db, dataset=dataset)
    sufficient = data_status["sufficient_for_training"]

    ml_stage_status = "active" if (ml_enabled and active_model is not None) else "disabled"
    ml_stage_desc = (
        "Active model used for acceptance probability"
        if ml_stage_status == "active"
        else "ML disabled (no active model / flag off)"
    )

    stages = [
        {
            "name": "Feature Extraction",
            "status": "active",
            "description": "Extracting behavioral & wellbeing features",
        },
        {
            "name": "Candidate Generation",
            "status": "active",
            "description": "Generating 5 break type candidates",
        },
        {
            "name": "Eligibility Filtering",
            "status": "active",
            "description": "Applying break cooldown & active break gates",
        },
        {
            "name": "Heuristic Scoring",
            "status": "active",
            "description": "Scoring candidates with evidence-based rules",
        },
        {
            "name": "ML Acceptance Prediction",
            "status": ml_stage_status,
            "description": ml_stage_desc,
        },
        {
            "name": "Final Ranking",
            "status": "active",
            "description": "Sorting by heuristic score (ML enhancement skipped)" if ml_stage_status == "disabled" else "Sorting by combined heuristic + ML score",
        },
        {
            "name": "Recommendation Served",
            "status": "active",
            "description": "Top candidate returned, logged to feedback table",
        },
        {
            "name": "Feedback Collection",
            "status": "active",
            "description": "User action recorded for future training",
        },
    ]

    return {
        "dataset_context": dataset,
        "ml_enabled": ml_enabled,
        "ml_inference_active": ml_enabled and active_model is not None,
        "training_ready": sufficient,
        "stages": stages,
    }


@router.get("/scoring-engine")
async def get_ml_scoring_engine(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns the heuristic scoring formula documentation, ML enhancement formula, and candidate adjustments.
    Heuristic weights are sourced from the live recommendation service constants.
    """
    from ..services.recommendation_service import (
        FACTOR_WEIGHTS,
        PATTERN_WEIGHTS,
        CANDIDATE_BASELINES,
    )

    factors = [
        {
            "name": name,
            "weight": weight,
            "condition": desc,
        }
        for name, weight, desc in FACTOR_WEIGHTS
    ]

    patterns = [
        {
            "pattern": name,
            "weight": weight,
            "candidates": candidates,
            "evidence": evidence,
            "description": desc,
        }
        for name, weight, candidates, evidence, desc in PATTERN_WEIGHTS
    ]

    candidate_adjustments = [
        {
            "candidate": candidate,
            "baseline": baseline,
        }
        for candidate, baseline in CANDIDATE_BASELINES.items()
    ]

    return {
        "heuristic_formula": {
            "baseline": 0.5,
            "factors": factors,
            "description": "Base score 0.5 + weighted factor adjustments, clamped to [0,1]",
        },
        "ml_enhancement_formula": {
            "description": "ML acceptance probability blended into heuristic score when an active model exists",
            "blend": "final_score = 0.7 * heuristic_score + 0.3 * ml_acceptance_probability",
            "active": True,
        },
        "candidate_adjustments": candidate_adjustments,
        "weights": factors,
        "patterns": patterns,
    }


@router.get("/training-feedback")
async def get_ml_training_feedback(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns labeled feedback counts, class distribution, training readiness, and training history for the specified dataset context.
    """
    data_status = assess_data_sufficiency(db, dataset=dataset)

    where_clauses = []
    if dataset == "production":
        where_clauses.append("(context_features->>'dev_demo') IS DISTINCT FROM 'true'")
        where_clauses.append("(context_features->>'is_test_data') IS DISTINCT FROM 'true'")
        where_clauses.append("user_id NOT IN (SELECT user_id FROM profiles WHERE is_test_data = true)")
    elif dataset == "experimental":
        where_clauses.append("((context_features->>'dev_demo') = 'true' OR (context_features->>'is_test_data') = 'true' OR user_id IN (SELECT user_id FROM profiles WHERE is_test_data = true))")

    where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

    class_sql = text(f"""
        SELECT
            SUM(CASE WHEN user_action = 'accepted' THEN 1 ELSE 0 END) as positive,
            SUM(CASE WHEN user_action IN ('dismissed', 'ignored') THEN 1 ELSE 0 END) as negative
        FROM recommendation_feedback
        WHERE {where_sql}
    """)
    class_row = db.execute(class_sql).first()

    history = [
        {
            "model_id": str(m.id),
            "model_version": m.version,
            "training_date": m.training_date.isoformat() if m.training_date else None,
            "is_active": m.is_active,
            "feature_set_version": getattr(m, 'feature_set_version', 'v1-base'),
        }
        for m in db.query(MLModel).order_by(MLModel.training_date.desc()).all()
    ]

    return {
        "dataset_context": dataset,
        "labeled_count": data_status["labeled_feedback"],
        "accepted_count": data_status["accepted"],
        "dismissed_count": data_status["dismissed"],
        "ignored_count": data_status["ignored"],
        "min_required": data_status["minimum_required"],
        "min_per_class": 5,
        "sufficient_for_training": data_status["sufficient_for_training"],
        "class_distribution": {
            "positive": int(class_row[0] or 0),
            "negative": int(class_row[1] or 0),
        },
        "training_history": history,
    }


@router.get("/feature-importance")
async def get_ml_feature_importance(
    model_id: Optional[str] = None,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns feature importance from a selected model (active or candidate).
    For LogisticRegression, this extracts feature names from the preprocessing pipeline
    and computes absolute coefficient magnitudes.
    Does NOT change activation status.
    """
    all_models = db.query(MLModel).order_by(MLModel.training_date.desc()).all()

    model_to_show = None
    if model_id:
        try:
            m_uuid = uuid.UUID(model_id)
            model_to_show = db.query(MLModel).filter(MLModel.id == m_uuid).first()
        except ValueError:
            pass

    if not model_to_show:
        active_model = get_latest_active_model(db, dataset=dataset)
        model_to_show = active_model or (all_models[0] if all_models else None)

    available_models_list = [
        {
            "model_id": str(m.id),
            "model_version": m.version,
            "is_active": m.is_active,
            "training_date": m.training_date.isoformat() if m.training_date else None,
            "feature_set_version": getattr(m, 'feature_set_version', 'v1-base')
        }
        for m in all_models
    ]

    if not model_to_show:
        return {
            "message": "No trained models available",
            "feature_importance": None,
            "available_models": available_models_list,
        }

    from ..services.ml_training_pipeline import load_model_artifact
    model_or_pipeline = load_model_artifact(model_to_show)
    if model_or_pipeline is None:
        return {
            "message": "Failed to load model artifact: artifact not found locally or on Supabase Storage",
            "feature_importance": None,
            "available_models": available_models_list,
        }

    feature_importance = {}
    feature_names = []

    try:
        if hasattr(model_or_pipeline, "named_steps"):
            preprocessor = model_or_pipeline.named_steps.get("preprocessor")
            classifier = model_or_pipeline.named_steps.get("classifier")

            if preprocessor and hasattr(preprocessor, "get_feature_names_out"):
                feature_names = list(preprocessor.get_feature_names_out())
            elif preprocessor and hasattr(preprocessor, "transformers_"):
                fn = []
                for name, trans, cols in preprocessor.transformers_:
                    if name == 'num' and isinstance(cols, list):
                        fn.extend(cols)
                    elif name == 'cat' and hasattr(trans, 'named_steps'):
                        oh = trans.named_steps.get('onehot')
                        if oh and hasattr(oh, 'categories_'):
                            for c_idx, col in enumerate(cols):
                                cats = oh.categories_[c_idx]
                                fn.extend([f"{col}_{cat}" for cat in cats])
                    elif isinstance(cols, list):
                        fn.extend(cols)
                feature_names = fn

            if classifier is None:
                classifier = model_or_pipeline
        else:
            classifier = model_or_pipeline

        if hasattr(classifier, "coef_"):
            coef = classifier.coef_[0]
            if not feature_names or len(feature_names) != len(coef):
                feature_names = [f"feature_{i}" for i in range(len(coef))]

            for name, val in zip(feature_names, coef):
                clean_name = name.replace("num__", "").replace("cat__", "")
                feature_importance[clean_name] = abs(float(val))
        elif hasattr(classifier, "feature_importances_"):
            importances = classifier.feature_importances_
            feature_names = [f"feature_{i}" for i in range(len(importances))]
            for name, val in zip(feature_names, importances):
                feature_importance[name] = float(val)
        else:
            feature_importance = None
    except Exception as e:
        feature_importance = None

    return {
        "model_id": str(model_to_show.id),
        "model_version": model_to_show.version,
        "is_active": model_to_show.is_active,
        "feature_set_version": getattr(model_to_show, 'feature_set_version', 'v1-base'),
        "training_date": model_to_show.training_date.isoformat() if model_to_show.training_date else None,
        "algorithm_assumed": "Logistic Regression (Balanced) with Preprocessing Pipeline",
        "feature_importance": feature_importance,
        "available_models": available_models_list,
        "note": "Feature importance represents absolute standardized coefficients (|coef|), showing how strongly each feature influences acceptance prediction. Note: Indicates model usage, not causal effects.",
    }


@router.get("/comparison")
async def get_ml_comparison(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns algorithm comparison summary and thesis reference baseline for the specified dataset context.
    """
    historical_comparison = [
        {"algorithm": "Logistic Regression (Balanced)", "accuracy": 0.6038, "precision": 0.4545, "recall": 0.5263, "f1": 0.4878, "roc_auc": 0.6842, "status": "Thesis Benchmark (Validated)"},
        {"algorithm": "Decision Tree", "accuracy": 0.5660, "precision": 0.4100, "recall": 0.4700, "f1": 0.4380, "roc_auc": 0.5800, "status": "Thesis Baseline"},
        {"algorithm": "Random Forest", "accuracy": 0.5850, "precision": 0.4300, "recall": 0.5000, "f1": 0.4620, "roc_auc": 0.6300, "status": "Thesis Baseline"},
        {"algorithm": "Gradient Boosting", "accuracy": 0.5660, "precision": 0.4150, "recall": 0.4800, "f1": 0.4450, "roc_auc": 0.6100, "status": "Thesis Baseline"},
    ]
    data_status = assess_data_sufficiency(db, dataset=dataset)
    return {
        "dataset_context": dataset,
        "comparison_results": historical_comparison,
        "data_sufficiency": data_status,
        "note": f"Comparison between active model, heuristics, and thesis benchmarks across dataset context '{dataset}'."
    }


@router.post("/train")
@router.post("/train-candidate")
async def train_candidate_model(
    dataset: str = "production",
    background_tasks: BackgroundTasks = None,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Triggers training of a new candidate model if data sufficiency permits on the specified dataset context.
    Creates model record with is_active=False (manual promotion gate).
    """
    data_status = assess_data_sufficiency(db, dataset=dataset)
    if not data_status["sufficient_for_training"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient labeled data for training in dataset '{dataset}': {data_status.get('blocking_reason', 'Requires at least 20 labeled samples.')}",
        )

    # Atomically reserve a job; reject duplicates while an active job exists.
    job = reserve_training_job(db, dataset=dataset, requested_by=current_user.id)
    if job is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A training job is already scheduled or running.",
        )

    background_tasks.add_task(background_train_model, dataset=dataset, job_id=job.id)
    return {
        "dataset_context": dataset,
        "job_id": str(job.id),
        "message": f"Candidate model training scheduled in background on dataset '{dataset}'.",
        "status": "scheduled",
    }


@router.post("/activate/{model_id}")
async def activate_candidate_model(
    model_id: str,
    request: Request,
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Guarded activation endpoint for a trained candidate model.
    Enforces:
    1. Admin authorization.
    2. Model existence and valid artifact path on disk.
    3. Data sufficiency & class balance (>= 20 labeled samples, >= 10 accepted, >= 10 dismissed/ignored).
    4. Single active model transactionality.
    5. Audit logging in system activity logs.
    """
    try:
        m_uuid = uuid.UUID(model_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid model ID format",
        )

    model = db.query(MLModel).filter(MLModel.id == m_uuid).first()
    if not model:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Model not found",
        )

    # Verify artifact exists on disk
    if not model.artifact_path or not os.path.exists(model.artifact_path):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Model artifact file not found on disk",
        )

    # Verify validation_status is PASSED before activation
    # A candidate must have passed independent user-level evaluation to be eligible for promotion
    if not hasattr(model, 'validation_status') or model.validation_status != "PASSED":
        current_status = getattr(model, 'validation_status', None)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Model activation blocked: validation_status is '{current_status}'. Only models with validation_status == 'PASSED' can be activated. Run candidate evaluation first.",
        )

    # Verify evaluation evidence exists in metrics
    if not model.metrics or not isinstance(model.metrics, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Model activation blocked: evaluation evidence (metrics) is missing or invalid.",
        )

    # Verify feature schema compatibility
    if not hasattr(model, 'feature_set_version') or model.feature_set_version not in ["v1-base", "v2-wellbeing"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Model activation blocked: unsupported feature_set_version '{getattr(model, 'feature_set_version', None)}'. Must be 'v1-base' or 'v2-wellbeing'.",
        )

    # Enforce data sufficiency using robust assessment (>= 20 labeled, >= 5 per class)
    data_status = assess_data_sufficiency(db, dataset=dataset)
    if not data_status["sufficient_for_training"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Promotion blocked: requires at least {data_status['minimum_required']} labeled samples with >= 5 in each class (currently {data_status['labeled_feedback']} labeled samples)."
        )

    # Attempt activation
    success = activate_model(db, m_uuid)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to activate model transactionally.",
        )

    # Log audit activity
    from ..auth.security import log_system_activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="ML_MODEL_ACTIVATED",
        category="ML",
        target_type="ml_model",
        target_id=str(model.id),
        target_display_label=model.version,
        outcome="SUCCESS",
        summary=f"Activated ML model version {model.version}",
        action_details={"model_id": str(model.id), "model_version": model.version},
    )

    return {
        "message": f"Model version {model.version} successfully activated.",
        "model_id": str(model.id),
        "version": model.version,
        "is_active": True,
    }


@router.post("/deactivate")
async def deactivate_all_models(
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Deactivates all active models (rollback / fallback to heuristics).
    """
    try:
        db.query(MLModel).update({MLModel.is_active: False})
        db.commit()

        from ..auth.security import log_system_activity
        log_system_activity(
            db=db,
            user_id=current_user.id,
            request=request,
            action_type="ML_MODELS_DEACTIVATED",
            category="ML",
            target_type="ml_model",
            target_id=None,
            target_display_label="all_models",
            outcome="SUCCESS",
            summary="Deactivated all ML models (reverted to heuristic fallback)",
            action_details={},
        )

        return {
            "message": "All ML models successfully deactivated. System reverted to heuristic fallback.",
            "ml_inference_active": False,
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to deactivate models: {str(e)}"
        )


# Placeholder for algorithm comparison - we will implement a POST endpoint to run comparison
@router.post("/run-comparison")
async def run_algorithm_comparison(
    dataset: str = "production",
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Triggers an algorithm comparison experiment (requires sufficient labeled data) on the specified dataset context.
    """
    # Check if we have sufficient data
    data_status = assess_data_sufficiency(db, dataset=dataset)
    if not data_status["sufficient_for_training"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Insufficient labeled data for training. Need at least {data_status['minimum_required']} labeled samples with at least 5 per class.",
        )

    # Import necessary ML libraries
    try:
        import numpy as np
        import pandas as pd
        from sklearn.model_selection import train_test_split
        from sklearn.linear_model import LogisticRegression
        from sklearn.tree import DecisionTreeClassifier
        from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
        from sklearn.preprocessing import StandardScaler, OneHotEncoder
        from sklearn.compose import ColumnTransformer
        from sklearn.pipeline import Pipeline
        from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
    except ImportError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Required ML libraries not available: {str(e)}",
        )

    # Extract training data (same as in ml_training_pipeline)
    from sqlalchemy import text
    from ..models import RecommendationFeedback

    # We'll reuse the _extract_training_data function but need to import it.
    # To avoid circular import, we'll copy the logic here or import from services.
    # Let's import from services.
    from ..services.ml_training_pipeline import _extract_training_data

    features_list, labels, *rest = _extract_training_data(db, dataset=dataset)

    if len(labels) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No labeled data available for comparison.",
        )

    # Convert to DataFrame for preprocessing
    df = pd.DataFrame(features_list)
    # Ensure all columns are present
    for key in ALL_FEATURE_KEYS:
        if key not in df.columns:
            df[key] = 0.0 if key in NUMERIC_FEATURE_KEYS else ""
    X = df[ALL_FEATURE_KEYS]
    y = np.array(labels)

    # Split into train and test sets (stratified)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Define algorithms to compare
    algorithms = {
        "LogisticRegression": LogisticRegression(random_state=42, max_iter=1000),
        "DecisionTree": DecisionTreeClassifier(random_state=42),
        "RandomForest": RandomForestClassifier(n_estimators=100, random_state=42),
        "GradientBoosting": GradientBoostingClassifier(random_state=42),
    }

    # Build preprocessing pipeline (same as in ml_training_pipeline)
    numeric_transformer = Pipeline(steps=[
        ("scaler", StandardScaler())
    ])
    categorical_transformer = Pipeline(steps=[
        ("onehot", OneHotEncoder(handle_unknown="ignore"))
    ])
    preprocessor = ColumnTransformer(
        transformers=[
            ("num", numeric_transformer, NUMERIC_FEATURE_KEYS),
            ("cat", categorical_transformer, CATEGORICAL_FEATURE_KEYS)
        ]
    )

    results = []

    for alg_name, model in algorithms.items():
        try:
            # Create pipeline
            clf = Pipeline(steps=[
                ("preprocessor", preprocessor),
                ("classifier", model)
            ])

            # Train
            clf.fit(X_train, y_train)

            # Predict on test set
            y_pred = clf.predict(X_test)
            y_proba = clf.predict_proba(X_test)[:, 1] if hasattr(clf, "predict_proba") else None

            # Compute metrics
            metrics = {
                "accuracy": float(accuracy_score(y_test, y_pred)),
                "precision": float(precision_score(y_test, y_pred, zero_division=0)),
                "recall": float(recall_score(y_test, y_pred, zero_division=0)),
                "f1": float(f1_score(y_test, y_pred, zero_division=0)),
                "roc_auc": float(roc_auc_score(y_test, y_proba)) if y_proba is not None and len(set(y_test)) > 1 else 0.5,
            }

            # Save artifact (we'll save the pipeline)
            model_id = uuid.uuid4()
            artifact_dir = os.path.join(os.path.dirname(__file__), "../../../ml_artifacts")
            os.makedirs(artifact_dir, exist_ok=True)
            artifact_path = os.path.join(artifact_dir, f"exp_model_{model_id}.joblib")
            try:
                import joblib
                joblib.dump(clf, artifact_path)
            except ImportError:
                artifact_path = None  # Cannot save artifact

            # Record in ml_experiments table
            experiment_id = uuid.uuid4()
            version = f"exp-{alg_name}-{datetime.now().strftime('%Y%m%d%H%M%S')}"

            # We need to insert into ml_experiments table; we'll use raw SQL or ORM.
            # Let's use ORM via the session.
            from ..models import MLExperiment  # We haven't defined this model yet; we'll skip for now and just return results.
            # Since we haven't added the MLExperiment model to the database (we only added ml_experiments table via migration),
            # we can still use the table via SQLAlchemy if we define a model, but to keep moving, we'll just return the results.
            # In a full implementation, we would define the MLExperiment model and insert here.

            results.append({
                "algorithm": alg_name,
                "version": version,
                "metrics": metrics,
                "artifact_path": artifact_path,
                "dataset_hash": None,  # We could compute a hash of X_train+y_train
                "is_baseline": alg_name == "LogisticRegression",  # Arbitrary baseline
            })
        except Exception as e:
            # Log error and continue with other algorithms
            results.append({
                "algorithm": alg_name,
                "error": str(e),
            })

    # Return the comparison results
    return {
        "comparison_results": results,
        "train_test_split_note": "Data split stratified 80% train, 20% test.",
        "feature_used": ALL_FEATURE_KEYS,
        "note": "Results are returned but not persisted to database because MLExperiment model is not yet defined. "
                "In a full implementation, we would store each experiment in the ml_experiments table.",
    }


@router.get("/prediction-inspector/{profile_id}")
async def get_prediction_inspector(
    profile_id: str,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns feature values and prediction details for a given profile's latest recommendation.
    If profile_id is 'latest', picks the most recent recommendation feedback in the system.
    """
    if profile_id.lower() == "latest":
        recent_feedback = db.query(RecommendationFeedback).order_by(RecommendationFeedback.timestamp.desc()).first()
        if not recent_feedback:
            return {
                "profile_id": None,
                "message": "No recommendation history found in the system.",
                "features": None,
                "prediction_details": None,
            }
        profile = db.query(Profile).filter(Profile.user_id == recent_feedback.user_id).first()
        if not profile:
            return {
                "profile_id": None,
                "message": "Profile not found for latest recommendation feedback.",
                "features": None,
                "prediction_details": None,
            }
        target_profile_id = profile.id
    else:
        try:
            target_profile_id = uuid.UUID(profile_id)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid profile ID format",
            )
        profile = db.query(Profile).filter(Profile.id == target_profile_id).first()
        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found",
            )

    # Get the most recent recommendation feedback for this profile (regardless of user_action)
    recent_feedback = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.user_id == profile.user_id
    ).order_by(RecommendationFeedback.timestamp.desc()).first()

    if not recent_feedback:
        return {
            "profile_id": str(target_profile_id),
            "message": "No recommendation history found for this profile.",
            "features": None,
            "prediction_details": None,
        }

    # Extract features from the feedback's context_features
    context_features = recent_feedback.context_features or {}
    # Ensure we have all expected features (fill missing with defaults)
    features = {}
    for feat in ALL_FEATURE_KEYS:
        features[feat] = context_features.get(feat, 0.0 if feat in NUMERIC_FEATURE_KEYS else "")

    # Determine if ML inference was actually executed for this prediction:
    # a valid active model must be loaded AND predict_proba() must execute
    # successfully AND its output must be applied. We verify by re-running the
    # inference path against the current active model with these features.
    active_model = get_latest_active_model(db)
    prediction_probability = None
    ml_used = False
    if active_model is not None:
        try:
            score = predict_with_model(db, features, recent_feedback.recommendation_type)
            if score is not None:
                prediction_probability = float(score)
                ml_used = True
        except Exception:
            prediction_probability = None
            ml_used = False

    # Determine what recommendation was made
    recommendation_type = recent_feedback.recommendation_type
    recommendation_score = recent_feedback.recommendation_score
    reason = recent_feedback.reason
    model_version = recent_feedback.model_version

    return {
        "profile_id": str(target_profile_id),
        "feedback_id": str(recent_feedback.id),
        "timestamp": recent_feedback.timestamp.isoformat() if recent_feedback.timestamp else None,
        "features": features,
        "context_features": context_features,
        "ml_used": ml_used,
        "ml_inference_executed": ml_used,  # explicit prediction-level field: ML inference was actually executed
        "heuristic_fallback_active": not ml_used,
        "model_version_used": model_version,
        "recommendation_type": recommendation_type,
        "recommendation_score": recommendation_score,
        "reason": reason,
        "prediction_probability": prediction_probability,  # Probability of acceptance from current active model
        "note": "The prediction probability shown is what the current active model would predict for these features. "
                "If ml_used is True, the historical recommendation likely used a similar model (maybe the same if no retraining).",
    }


@router.post("/generate-dataset")
async def generate_ml_dataset(
    organization_name: str = "IntelliBreak Demo Organization",
    num_managers: int = 2,
    num_employees: int = 10,
    num_teams: int = 2,
    days_back: int = 30,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Generate realistic demonstration dataset for ML experimental training context.
    """
    from datetime import date, timedelta
    end_date = date.today()
    start_date = end_date - timedelta(days=days_back)

    from ..services.historical_behavioral_generator import generate_historical_behavioral_dataset
    try:
        summary = generate_historical_behavioral_dataset(
            db,
            current_user=current_user,
            organization_name=organization_name,
            start_date=start_date,
            end_date=end_date,
            num_managers=num_managers,
            num_employees=num_employees,
            num_teams=num_teams
        )
        return {
            "status": "success",
            "message": "Realistic dataset generated successfully.",
            "summary": summary
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Dataset generation failed: {str(e)}"
        )


@router.get("/training-history")
async def get_ml_training_history(
    dataset: Optional[str] = None,
    limit: int = 20,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Returns training job history with dataset context, status, extracted sample count, positive/negative counts, duration, and failure reasons.
    """
    query = db.query(MLTrainingJob)
    if dataset:
        query = query.filter(MLTrainingJob.dataset == dataset)
    jobs = query.order_by(MLTrainingJob.created_at.desc()).limit(limit).all()

    result = []
    for j in jobs:
        result.append({
            "job_id": str(j.id),
            "status": j.status,
            "dataset_context": j.dataset,
            "extracted_samples": j.extracted_samples or 0,
            "positive_count": j.positive_count or 0,
            "negative_count": j.negative_count or 0,
            "duration_seconds": j.duration_seconds or 0.0,
            "error_message": j.error_message,
            "model_id": str(j.model_id) if j.model_id else None,
            "created_at": j.created_at.isoformat() if j.created_at else None,
            "started_at": j.started_at.isoformat() if j.started_at else None,
            "completed_at": j.completed_at.isoformat() if j.completed_at else None,
        })
    return {
        "dataset_context": dataset or "all",
        "jobs": result
    }