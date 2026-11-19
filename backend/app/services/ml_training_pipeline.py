"""
ML Training Pipeline for Recommendation Service.
Handles extraction of training data, feature preprocessing, model training,
evaluation, and model artifact/version management.
Does NOT activate a model unless sufficient data exists and evaluation passes.
"""
import os
import json
import uuid
import hashlib
import logging
import time
import urllib.request
import urllib.error

logger = logging.getLogger("intellibreak.ml")
from datetime import datetime, timezone
from typing import Tuple, List, Dict, Any, Optional

import numpy as np
from sqlalchemy import text
from sqlalchemy.orm import Session

# Try to import scikit-learn; if not available, we'll fall back to a non-ML baseline
try:
    from sklearn.linear_model import LogisticRegression
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.preprocessing import StandardScaler, OneHotEncoder
    from sklearn.impute import SimpleImputer
    from sklearn.compose import ColumnTransformer
    from sklearn.pipeline import Pipeline
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score, confusion_matrix
    from sklearn.model_selection import StratifiedKFold, GroupKFold, train_test_split
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False

from ..database import SessionLocal, engine
from ..models import RecommendationFeedback, MLModel, Profile, MLTrainingJob

# Import canonical feature schema
from .feature_schema import (
    V2_NUMERIC_FEATURE_KEYS,
    V2_CATEGORICAL_FEATURE_KEYS,
    V2_ALL_FEATURE_KEYS,
    FEATURE_SCHEMA_VERSION,
    MINIMUM_TRAINING_SAMPLES,
    POSITIVE_LABEL,
    NEGATIVE_LABELS,
    extract_feature_snapshot_from_feedback_row,
    build_feature_vector,
)

# Backward compatibility aliases for existing code
NUMERIC_FEATURE_KEYS = V2_NUMERIC_FEATURE_KEYS
CATEGORICAL_FEATURE_KEYS = V2_CATEGORICAL_FEATURE_KEYS

# Import heuristic scoring function
try:
    from .recommendation_service import _score_candidate
except ImportError:
    _score_candidate = None
ALL_FEATURE_KEYS = V2_ALL_FEATURE_KEYS

# Configuration
MODEL_ARTIFACT_DIR = os.path.join(os.path.dirname(__file__), "ml_artifacts")
RANDOM_STATE = 42

# Ensure artifact directory exists
os.makedirs(MODEL_ARTIFACT_DIR, exist_ok=True)


def upload_artifact_to_supabase(local_path: str, remote_filename: str) -> bool:
    """Upload trained joblib artifact to Supabase Storage bucket (private ml-models)."""
    supabase_url = os.getenv("SUPABASE_URL")
    service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "ml-models")

    if not supabase_url or not service_role_key:
        return False

    url = f"{supabase_url.rstrip('/')}/storage/v1/object/{bucket}/{remote_filename}"
    try:
        with open(local_path, "rb") as f:
            data = f.read()

        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Authorization": f"Bearer {service_role_key}",
                "apikey": service_role_key,
                "Content-Type": "application/octet-stream",
                "x-upsert": "true"
            },
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status in (200, 201)
    except Exception as e:
        print(f"Supabase Storage upload error: {e}")
        return False


def download_artifact_from_supabase(remote_filename: str, local_dest_path: str) -> bool:
    """Download trained joblib artifact from Supabase Storage bucket."""
    supabase_url = os.getenv("SUPABASE_URL")
    service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    bucket = os.getenv("SUPABASE_STORAGE_BUCKET", "ml-models")

    if not supabase_url or not service_role_key:
        return False

    url = f"{supabase_url.rstrip('/')}/storage/v1/object/{bucket}/{remote_filename}"
    try:
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {service_role_key}",
                "apikey": service_role_key
            },
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            if response.status == 200:
                os.makedirs(os.path.dirname(local_dest_path), exist_ok=True)
                with open(local_dest_path, "wb") as f:
                    f.write(response.read())
                return True
    except Exception as e:
        print(f"Supabase Storage download error: {e}")
        return False
    return False


def _artifact_relative_key(artifact_path: str) -> str:
    """Derive a portable relative storage key from any artifact path."""
    return os.path.join("models", os.path.basename(artifact_path))


def _resolve_artifact_local_path(artifact_path: str) -> str:
    """Resolve a portable relative key or absolute path to a local artifact path."""
    basename = os.path.basename(artifact_path)
    return os.path.join(MODEL_ARTIFACT_DIR, basename)


def _compute_sha256(file_path: str) -> str:
    """Compute SHA-256 checksum of a local file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def _verify_artifact_checksum(local_path: str, expected_sha256: Optional[str]) -> bool:
    """Verify local artifact SHA-256 checksum when expected digest is provided."""
    if not expected_sha256:
        return True
    try:
        return _compute_sha256(local_path) == expected_sha256
    except Exception:
        return False


def load_model_artifact(model_record: MLModel) -> Optional[Any]:
    """
    Safely load model artifact from a portable relative storage key,
    downloading from Supabase Storage if missing locally.
    Validates SHA-256 checksum when recorded, and feature-set compatibility.
    """
    if not model_record or not model_record.artifact_path:
        return None

    artifact_key = _artifact_relative_key(model_record.artifact_path)
    local_path = _resolve_artifact_local_path(artifact_key)

    expected_sha256 = None
    try:
        if model_record.metrics and isinstance(model_record.metrics, str):
            parsed_metrics = json.loads(model_record.metrics)
            expected_sha256 = parsed_metrics.get("artifact_sha256")
    except Exception:
        expected_sha256 = None

    try:
        if os.path.exists(local_path):
            if not _verify_artifact_checksum(local_path, expected_sha256):
                print(f"Artifact checksum mismatch or missing for {local_path}; refreshing from storage.")
            else:
                import joblib
                return joblib.load(local_path)

        downloaded = download_artifact_from_supabase(os.path.basename(artifact_key), local_path)
        if not downloaded and not os.path.exists(local_path):
            return None

        if not _verify_artifact_checksum(local_path, expected_sha256):
            print(f"Artifact SHA-256 verification failed for {local_path}.")
            return None

        import joblib
        model_or_pipeline = joblib.load(local_path)
        return model_or_pipeline
    except Exception as e:
        print(f"Failed to load/validate model artifact {artifact_key}: {e}")
        return None


def _is_truthy_flag(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() == "true"
    return False


def _is_synthetic_record(context_features: Optional[Dict[str, Any]]) -> bool:
    if not context_features:
        return False
    return (
        _is_truthy_flag(context_features.get("dev_demo"))
        or _is_truthy_flag(context_features.get("is_test_data"))
    )


def _get_test_user_ids(db: Session) -> set:
    return {str(user_id) for (user_id,) in db.query(Profile.user_id).filter(Profile.is_test_data == True).all()}


def _matches_dataset_context(row: Any, dataset: str, test_user_ids: set) -> bool:
    """Dialect-agnostic predicate matching the dataset context rules."""
    if dataset == "all":
        return True
    is_synthetic = _is_synthetic_record(row.context_features) or str(row.user_id) in test_user_ids
    return is_synthetic if dataset == "experimental" else not is_synthetic


def _iter_labeled_feedback(db: Session, dataset: str):
    """Yield RecommendationFeedback rows eligible for training in the given context."""
    test_user_ids = _get_test_user_ids(db)
    return (
        row
        for row in db.query(RecommendationFeedback).filter(
            RecommendationFeedback.user_action.isnot(None),
            RecommendationFeedback.user_action.in_([POSITIVE_LABEL, "dismissed", "ignored"]),
            ~RecommendationFeedback.recommendation_type.like("WLB_%"),
            RecommendationFeedback.user_action != "expired",
        ).all()
        if _matches_dataset_context(row, dataset, test_user_ids)
    )


def _extract_training_data(db: Session, dataset: str = "production") -> Tuple[List[Dict[str, Any]], List[int], List[str], List[str]]:
    """
    Extract labeled training data from recommendation_feedback.
    Handles different feature schema versions by extracting appropriate features and
    enriching wellbeing check-ins when missing.
    Returns:
        features_list: list of dicts with keys from the appropriate feature set
        labels: list of 0/1 (1 for accepted, 0 for dismissed/ignored)
        schema_versions: list of schema version strings
        user_ids: list of user_id strings for user-grouped CV
    """
    features_list = []
    labels = []
    schema_versions = []
    user_ids = []

    for rec in _iter_labeled_feedback(db, dataset):
        user_id = rec.user_id
        rec_type = rec.recommendation_type
        user_action = rec.user_action
        schema_version = rec.feature_schema_version
        context_features_json = rec.context_features

        # Normalize user_id to hyphenated UUID string format
        if isinstance(user_id, str):
            # If it's a 32-char hex string without hyphens, format it
            if len(user_id) == 32 and '-' not in user_id:
                user_id = f"{user_id[0:8]}-{user_id[8:12]}-{user_id[12:16]}-{user_id[16:20]}-{user_id[20:32]}"
        elif hasattr(user_id, 'hex'):
            user_id = str(user_id)

        if isinstance(context_features_json, str):
            try:
                context_features = json.loads(context_features_json)
            except json.JSONDecodeError:
                context_features = {}
        else:
            context_features = context_features_json or {}

        # Use canonical feature extraction from feature_schema
        feature_snapshot = extract_feature_snapshot_from_feedback_row(context_features)

        # Build canonical feature vector
        feature_dict = build_feature_vector(feature_snapshot, rec_type)

        features_list.append(feature_dict)
        labels.append(1 if user_action == POSITIVE_LABEL else 0)
        schema_versions.append(schema_version or "v1-base")
        user_ids.append(str(user_id))

    return features_list, labels, schema_versions, user_ids


def _evaluate_with_cross_validation(X: Any, y: np.ndarray, groups: Optional[List[str]] = None) -> Dict[str, Any]:
    """
    Perform cross-validation (StratifiedKFold or GroupKFold if groups provided and diverse).
    Handles small sample limitations gracefully.
    """
    n_samples = len(y)
    n_classes = len(set(y))

    if n_samples < 5 or n_classes < 2:
        return {
            "cv_available": False,
            "limitation_reason": f"Insufficient samples ({n_samples}) or single class present."
        }

    n_splits = min(5, n_samples)
    if n_splits < 2:
        n_splits = 2

    try:
        unique_groups = set(groups) if groups else set()
        if groups and len(unique_groups) >= 2 and len(unique_groups) <= n_samples:
            cv = GroupKFold(n_splits=min(n_splits, len(unique_groups)))
            split_gen = cv.split(X, y, groups=groups)
        else:
            cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=RANDOM_STATE)
            split_gen = cv.split(X, y)

        fold_accs = []
        fold_precs = []
        fold_recs = []
        fold_f1s = []
        fold_aucs = []
        all_oof_preds = []
        all_oof_true = []

        preprocessor = _build_preprocessing_pipeline(V2_ALL_FEATURE_KEYS, V2_NUMERIC_FEATURE_KEYS)

        for train_idx, test_idx in split_gen:
            X_train_fold, X_test_fold = X.iloc[train_idx], X.iloc[test_idx]
            y_train_fold, y_test_fold = y[train_idx], y[test_idx]

            if len(set(y_test_fold)) < 2:
                continue

            clf = Pipeline(steps=[
                ("preprocessor", preprocessor),
                ("classifier", LogisticRegression(random_state=RANDOM_STATE, max_iter=1000))
            ])
            clf.fit(X_train_fold, y_train_fold)
            preds = clf.predict(X_test_fold)
            probs = clf.predict_proba(X_test_fold)[:, 1] if hasattr(clf, "predict_proba") else np.zeros_like(preds, dtype=float)

            fold_accs.append(accuracy_score(y_test_fold, preds))
            fold_precs.append(precision_score(y_test_fold, preds, zero_division=0))
            fold_recs.append(recall_score(y_test_fold, preds, zero_division=0))
            fold_f1s.append(f1_score(y_test_fold, preds, zero_division=0))
            if len(set(y_test_fold)) > 1:
                fold_aucs.append(roc_auc_score(y_test_fold, probs))

            all_oof_preds.extend(preds.tolist())
            all_oof_true.extend(y_test_fold.tolist())

        if not fold_accs:
            return {"cv_available": False, "limitation_reason": "Cross-validation splits lacked class diversity."}

        oof_cm = confusion_matrix(all_oof_true, all_oof_preds).tolist() if all_oof_true else [[0,0],[0,0]]

        small_sample_limitation = n_samples < 50
        return {
            "cv_available": True,
            "n_splits": n_splits,
            "sample_count": n_samples,
            "small_sample_limitation": small_sample_limitation,
            "limitation_note": "Evaluated on small sample (< 50 labeled records); cross-validation metrics may exhibit high variance." if small_sample_limitation else None,
            "cv_accuracy_mean": float(np.mean(fold_accs)),
            "cv_accuracy_std": float(np.std(fold_accs)),
            "cv_precision_mean": float(np.mean(fold_precs)),
            "cv_precision_std": float(np.std(fold_precs)),
            "cv_recall_mean": float(np.mean(fold_recs)),
            "cv_recall_std": float(np.std(fold_recs)),
            "cv_f1_mean": float(np.mean(fold_f1s)),
            "cv_f1_std": float(np.std(fold_f1s)),
            "cv_roc_auc_mean": float(np.mean(fold_aucs)) if fold_aucs else 0.5,
            "cv_roc_auc_std": float(np.std(fold_aucs)) if fold_aucs else 0.0,
            "cv_confusion_matrix": oof_cm
        }
    except Exception as e:
        return {
            "cv_available": False,
            "error": str(e),
            "sample_count": n_samples,
            "small_sample_limitation": n_samples < 50,
            "limitation_note": "Cross-validation failed or insufficient sample diversity."
        }


def _build_preprocessing_pipeline(feature_keys: List[str], numeric_keys: List[str]) -> Optional[ColumnTransformer]:
    """
    Build a scikit-learn ColumnTransformer for preprocessing with SimpleImputer.
    Returns None if scikit-learn not available.
    """
    if not SKLEARN_AVAILABLE:
        return None

    # Numeric pipeline: impute missing values (NaN) then standardize
    numeric_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="constant", fill_value=0.0)),
        ("scaler", StandardScaler())
    ])

    # Categorical pipeline: one-hot encode
    categorical_transformer = Pipeline(steps=[
        ("onehot", OneHotEncoder(handle_unknown="ignore"))
    ])

    # Determine which keys are categorical (not in numeric_keys)
    categorical_keys = [key for key in feature_keys if key not in numeric_keys]

    # Build transformers list dynamically
    transformers = []
    if numeric_keys:
        transformers.append(("num", numeric_transformer, numeric_keys))
    if categorical_keys:
        transformers.append(("cat", categorical_transformer, categorical_keys))

    if not transformers:
        return None

    preprocessor = ColumnTransformer(transformers=transformers)
    return preprocessor


def train_model(db: Session, dataset: str = "production", model_type: str = "random_forest", version_name: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """
    Train a model if sufficient data exists.
    Returns a dict with model metadata and path if training succeeded, else None.
    Does NOT activate the model (is_active=False).
    """
    if not SKLEARN_AVAILABLE:
        print("Scikit-learn not available; skipping ML training.")
        return None

    # Extract training data
    features_list, labels, schema_versions, user_ids = _extract_training_data(db, dataset=dataset)
    n_samples = len(labels)
    print(f"Found {n_samples} labeled feedback records for training.")

    if n_samples < MINIMUM_TRAINING_SAMPLES:
        print(f"Insufficient labeled data (< {MINIMUM_TRAINING_SAMPLES}). Skipping training.")
        return None

    # Check class balance
    n_pos = sum(labels)
    n_neg = n_samples - n_pos
    print(f"Class balance: positive={n_pos}, negative={n_neg}")
    if n_pos < 5 or n_neg < 5:
        print("Too few samples in one class; skipping training.")
        return None

    # Group features by schema version for separate processing
    # For now, we'll process all together but validate schema consistency
    schema_version_counts = {}
    for version in schema_versions:
        schema_version_counts[version] = schema_version_counts.get(version, 0) + 1
    print(f"Schema version distribution: {schema_version_counts}")

    # Build preprocessing and model pipeline with SimpleImputer to handle missing values
    all_feature_keys = V2_ALL_FEATURE_KEYS  # Use extended feature set
    numeric_keys = V2_NUMERIC_FEATURE_KEYS

    numeric_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="constant", fill_value=0.0)),
        ("scaler", StandardScaler())
    ])
    categorical_transformer = Pipeline(steps=[
        ("onehot", OneHotEncoder(handle_unknown="ignore"))
    ])
    categorical_keys = [key for key in all_feature_keys if key not in numeric_keys]
    transformers = []
    if numeric_keys:
        transformers.append(("num", numeric_transformer, numeric_keys))
    if categorical_keys:
        transformers.append(("cat", categorical_transformer, categorical_keys))
    preprocessor = ColumnTransformer(transformers=transformers)

    if model_type == "random_forest":
        model = RandomForestClassifier(n_estimators=100, random_state=RANDOM_STATE)
    else:
        model = LogisticRegression(random_state=RANDOM_STATE, max_iter=1000)
    clf = Pipeline(steps=[
        ("preprocessor", preprocessor),
        ("classifier", model)
    ])

    # Prepare feature matrix using pandas DataFrame
    import pandas as pd
    df = pd.DataFrame(features_list)
    for key in all_feature_keys:
        if key not in df.columns:
            df[key] = np.nan if key in numeric_keys else ""
        else:
            if key in numeric_keys:
                df[key] = df[key].apply(lambda x: float(x) if x is not None and not (isinstance(x, float) and np.isnan(x)) else np.nan)
            else:
                df[key] = df[key].fillna("").astype(str)
    X = df[all_feature_keys]
    y = np.array(labels)

    # Group-aware train/test split to ensure user-level separation
    split_result = _group_aware_train_test_split(X, y, user_ids, test_size=0.2, random_state=RANDOM_STATE)
    if split_result is None:
        print("Group-aware split failed; insufficient users or samples. Skipping training.")
        return None

    X_train, X_test, y_train, y_test, train_groups, test_groups, group_aware_used = split_result

    # Fit pipeline ONLY on training split
    clf.fit(X_train, y_train)

    # 1. Training metrics
    train_preds = clf.predict(X_train)
    train_probs = clf.predict_proba(X_train)[:, 1] if hasattr(clf, "predict_proba") else np.zeros_like(train_preds, dtype=float)
    train_cm = confusion_matrix(y_train, train_preds).tolist()
    train_metrics = {
        "sample_count": len(y_train),
        "accuracy": float(accuracy_score(y_train, train_preds)),
        "precision": float(precision_score(y_train, train_preds, zero_division=0)),
        "recall": float(recall_score(y_train, train_preds, zero_division=0)),
        "f1": float(f1_score(y_train, train_preds, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_train, train_probs)) if len(set(y_train)) > 1 else 0.5,
        "confusion_matrix": train_cm
    }

    # 2. Cross-validation metrics (on training split)
    cv_res = _evaluate_with_cross_validation(X_train, y_train, train_groups)

    # 3. Independent test metrics (on held-out test split)
    test_preds = clf.predict(X_test)
    test_probs = clf.predict_proba(X_test)[:, 1] if hasattr(clf, "predict_proba") else np.zeros_like(test_preds, dtype=float)
    test_cm = confusion_matrix(y_test, test_preds).tolist()
    test_metrics = {
        "sample_count": len(y_test),
        "accuracy": float(accuracy_score(y_test, test_preds)),
        "precision": float(precision_score(y_test, test_preds, zero_division=0)),
        "recall": float(recall_score(y_test, test_preds, zero_division=0)),
        "f1": float(f1_score(y_test, test_preds, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_test, test_probs)) if len(set(y_test)) > 1 else 0.5,
        "confusion_matrix": test_cm
    }

    metrics = {
        "training_metrics": train_metrics,
        "test_metrics": test_metrics,
        "cv_metrics": cv_res,
        "accuracy": test_metrics["accuracy"],
        "precision": test_metrics["precision"],
        "recall": test_metrics["recall"],
        "f1": test_metrics["f1"],
        "roc_auc": test_metrics["roc_auc"],
        "confusion_matrix": test_cm,
        "sample_count": n_samples,
        "train_set_size": len(y_train),
        "test_set_size": len(y_test),
        "train_unique_users": len(set(train_groups)),
        "test_unique_users": len(set(test_groups)),
        "group_aware_split_used": group_aware_used,
        "small_sample_limitation": n_samples < 50,
        "limitation_note": "Evaluated on small sample (< 50 labeled records); performance metrics and test split estimates may exhibit high variance." if n_samples < 50 else None,
        "f1_threshold": 0.5,
        "f1_threshold_status": "provisional",
        "f1_threshold_note": "F1 > 0.5 is a provisional engineering criterion; not statistically validated for small datasets.",
    }

    # Save artifact (pipeline)
    model_id = uuid.uuid4()
    local_artifact_path = os.path.join(MODEL_ARTIFACT_DIR, f"model_{model_id}.joblib")
    relative_artifact_key = os.path.join("models", f"model_{model_id}.joblib")
    try:
        import joblib
        joblib.dump(clf, local_artifact_path)
        sha256_digest = _compute_sha256(local_artifact_path)
        metrics["artifact_sha256"] = sha256_digest
        upload_artifact_to_supabase(local_artifact_path, f"model_{model_id}.joblib")
    except Exception as e:
        print(f"Joblib save or Supabase upload failed: {e}")
        return None

    # Record in MLModel table with portable relative path
    version = version_name or f"trained-{dataset}-v{datetime.now().strftime('%Y%m%d%H%M%S')}"
    ml_model = MLModel(
        id=model_id,
        version=version,
        artifact_path=relative_artifact_key,
        training_date=datetime.now(timezone.utc),
        feature_set_version="v2-wellbeing",
        metrics=json.dumps(metrics),
        is_active=False
    )
    db.add(ml_model)
    db.commit()
    db.refresh(ml_model)

    return {
        "model_id": str(model_id),
        "version": version,
        "artifact_path": relative_artifact_key,
        "metrics": metrics,
        "is_active": False
    }


def evaluate_candidate(db: Session, model_id: uuid.UUID, dataset: str = "production") -> Dict[str, Any]:
    """
    Evaluate a candidate model against the current active model (if exists)
    and the heuristic baseline, using independent test data.
    Determines validation status.
    """
    # Evaluate on independent test split only
    metrics = evaluate_model_on_test_set(db, model_id, dataset)
    if not metrics:
        return {"result": "FAILED", "reason": "Evaluation failed - insufficient test data"}

    # Check if independent user-level evaluation was available
    group_aware_used = metrics.get("group_aware_split_used", False)
    test_unique_users = metrics.get("test_unique_users", 0)
    train_unique_users = metrics.get("train_unique_users", 0)

    # If group-aware split was NOT used (fallback to row-level), validation is PENDING
    # A candidate cannot pass validation without independent user-level evaluation
    if not group_aware_used:
        return {
            "model_id": str(model_id),
            "result": "PENDING",
            "reason": "Independent user-level evaluation not available (insufficient unique users). Evaluation performed with row-level split which may have user leakage.",
            "metrics": metrics,
            "comparison": {"active_model": None, "heuristic_baseline": None},
            "acceptance_criteria": {
                "f1_gt_05": metrics.get("f1", 0) > 0.5,
                "sufficient_test_samples": metrics.get("test_sample_count", 0) >= 10,
                "beats_heuristic": False,
                "beats_or_matches_active": False,
                "independent_evaluation": False
            }
        }

    # Compare against active model if it exists
    active_model = get_latest_active_model(db)
    comparison = {"active_model": None, "heuristic_baseline": None}

    if active_model and active_model.id != model_id and active_model.metrics:
        import json
        active_metrics = json.loads(active_model.metrics) if isinstance(active_model.metrics, str) else active_model.metrics
        comparison["active_model"] = {
            "model_id": str(active_model.id),
            "f1": active_metrics.get("f1", 0),
            "improvement": metrics.get("f1", 0) - active_metrics.get("f1", 0)
        }

    # Compare against heuristic baseline
    heuristic_metrics = evaluate_heuristic_baseline(db, dataset)
    if heuristic_metrics:
        comparison["heuristic_baseline"] = heuristic_metrics
        comparison["heuristic_baseline"]["improvement"] = metrics.get("f1", 0) - heuristic_metrics.get("f1", 0)

    # Acceptance criteria based on Phase 4/5 remediation plan:
    # 1. Must have ROC-AUC >= 0.60 (ensuring true discriminative ranking)
    # 2. Must have F1 >= 0.55 AND sufficient test samples (>= 10)
    # 3. Must compare favorably against heuristic baseline and active model
    roc_auc_val = metrics.get("roc_auc", 0)
    f1_val = metrics.get("f1", 0)
    passed = (
        roc_auc_val >= 0.60 and
        f1_val >= 0.55 and
        metrics.get("test_sample_count", 0) >= 10 and
        (comparison["heuristic_baseline"] is None or f1_val >= comparison["heuristic_baseline"].get("f1", 0) - 0.02) and
        (comparison["active_model"] is None or f1_val >= comparison["active_model"].get("f1", 0))
    )

    return {
        "model_id": str(model_id),
        "result": "PASSED" if passed else "FAILED",
        "metrics": metrics,
        "comparison": comparison,
        "acceptance_criteria": {
            "roc_auc_ge_060": roc_auc_val >= 0.60,
            "f1_ge_055": f1_val >= 0.55,
            "sufficient_test_samples": metrics.get("test_sample_count", 0) >= 10,
            "beats_or_matches_heuristic": comparison["heuristic_baseline"] is None or f1_val >= comparison["heuristic_baseline"].get("f1", 0) - 0.02,
            "beats_or_matches_active": comparison["active_model"] is None or f1_val >= comparison["active_model"].get("f1", 0),
            "independent_evaluation": True
        }
    }


def _group_aware_train_test_split(X, y, groups, test_size=0.2, random_state=42):
    """
    Split data ensuring no user appears in both train and test sets.
    Uses GroupShuffleSplit for proper user-level separation.
    Falls back to stratified split if insufficient users for group-aware split.
    Returns (X_train, X_test, y_train, y_test, train_groups, test_groups, group_aware_used)
    """
    from sklearn.model_selection import GroupShuffleSplit, train_test_split

    n_samples = len(y)
    n_users = len(set(groups))

    # Need at least 2 users and enough samples for group-aware split
    if n_users >= 2 and n_samples >= 5:
        gss = GroupShuffleSplit(n_splits=1, test_size=test_size, random_state=random_state)

        try:
            train_idx, test_idx = next(gss.split(X, y, groups=groups))
            X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
            y_train, y_test = y[train_idx], y[test_idx]
            train_groups = [groups[i] for i in train_idx]
            test_groups = [groups[i] for i in test_idx]

            # Verify no user overlap
            assert set(train_groups).isdisjoint(set(test_groups)), "User leakage detected in group-aware split"

            return X_train, X_test, y_train, y_test, train_groups, test_groups, True
        except ValueError:
            # GroupShuffleSplit failed, fall through to stratified
            pass

    # Fallback: stratified split (row-level, NOT user-level separated)
    # This preserves class distribution but may have user leakage
    if len(set(y)) > 1 and n_samples >= 10:
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=random_state, stratify=y
        )
    else:
        X_train, X_test, y_train, y_test = X, X, y, y

    train_groups = groups
    test_groups = groups

    return X_train, X_test, y_train, y_test, train_groups, test_groups, False


def evaluate_model_on_test_set(db: Session, model_id: uuid.UUID, dataset: str = "production") -> Optional[Dict[str, Any]]:
    """
    Evaluate a given model ONLY on the independent test set (20% holdout).
    Uses group-aware split to ensure user-level separation between training and test.
    """
    if not SKLEARN_AVAILABLE:
        return None

    model_record = db.query(MLModel).filter(MLModel.id == model_id).first()
    if model_record is None:
        return None

    model_or_pipeline = load_model_artifact(model_record)
    if model_or_pipeline is None:
        return None

    # Extract labeled data
    features_list, labels, _, user_ids = _extract_training_data(db, dataset=dataset)
    if len(labels) < 10:  # Need minimum for train/test split
        return None

    try:
        import pandas as pd
        df = pd.DataFrame(features_list)
        if hasattr(model_record, 'feature_set_version') and model_record.feature_set_version == "v2-wellbeing":
            feature_keys = V2_ALL_FEATURE_KEYS
            numeric_keys = V2_NUMERIC_FEATURE_KEYS
        else:
            feature_keys = V1_ALL_FEATURE_KEYS
            numeric_keys = V1_NUMERIC_FEATURE_KEYS

        for key in feature_keys:
            if key not in df.columns:
                df[key] = 0.0 if key in numeric_keys else ""
        X = df[feature_keys]
        y = np.array(labels)
    except ImportError:
        return None

    # Group-aware train/test split to ensure user-level separation
    split_result = _group_aware_train_test_split(X, y, user_ids, test_size=0.2, random_state=RANDOM_STATE)
    if split_result is None:
        return None

    X_train, X_test, y_train, y_test, train_groups, test_groups, group_aware_used = split_result

    if len(y_test) < 5:
        return None

    try:
        preds = model_or_pipeline.predict(X_test)
        probs = model_or_pipeline.predict_proba(X_test)[:, 1] if hasattr(model_or_pipeline, "predict_proba") else np.zeros(len(y_test))

        cm = confusion_matrix(y_test, preds).tolist()

        # Also run cross-validation on training data for stability estimate
        train_user_ids = train_groups
        cv_res = _evaluate_with_cross_validation(X_train, y_train, train_user_ids) if len(y_train) >= 10 else {}

        metrics = {
            "accuracy": float(accuracy_score(y_test, preds)),
            "precision": float(precision_score(y_test, preds, zero_division=0)),
            "recall": float(recall_score(y_test, preds, zero_division=0)),
            "f1": float(f1_score(y_test, preds, zero_division=0)),
            "roc_auc": float(roc_auc_score(y_test, probs)) if len(set(y_test)) > 1 else 0.5,
            "confusion_matrix": cm,
            "test_sample_count": len(y_test),
            "test_class_distribution": {str(c): int(np.sum(y_test == c)) for c in set(y_test)},
            "test_unique_users": len(set(test_groups)),
            "train_unique_users": len(set(train_groups)),
            "group_aware_split_used": group_aware_used,
            "f1_threshold": 0.5,
            "f1_threshold_status": "provisional",
            "f1_threshold_note": "F1 > 0.5 is a provisional engineering criterion; not statistically validated for small datasets.",
            **cv_res
        }
        return metrics
    except Exception:
        return None


def evaluate_heuristic_baseline(db: Session, dataset: str = "production") -> Optional[Dict[str, Any]]:
    """
    Evaluate the heuristic recommendation engine on the same evaluation records.
    Returns F1 and other metrics for comparison.

    LIMITATION: Currently evaluates SHORT_BREAK candidate type only.
    Other recommendation types (WALK, HYDRATE, STRETCH, LUNCH) are not evaluated
    due to insufficient labeled data for each type.
    """
    if _score_candidate is None:
        return None

    # Extract labeled data with features
    features_list, labels, _, user_ids = _extract_training_data(db, dataset=dataset)
    n_samples = len(labels)
    n_users = len(set(user_ids))

    if n_samples < 10 or n_users < 2:
        return None

    try:
        import pandas as pd
        df = pd.DataFrame(features_list)
        y = np.array(labels)

        # Group-aware split to match ML evaluation
        split_result = _group_aware_train_test_split(df, y, user_ids, test_size=0.2, random_state=RANDOM_STATE)
        if split_result is None:
            return None

        _, X_test, _, y_test, _, test_groups, _ = split_result

        if len(y_test) < 5:
            return None

        # Score each test record using the heuristic engine
        # Map V2 feature names to heuristic expected names
        heuristic_preds = []
        for _, row in X_test.iterrows():
            features = row.to_dict()
            # Map V2 feature keys to heuristic expected keys
            heuristic_features = {
                "session_length_minutes": features.get("session_length", 0),
                "time_since_last_break_minutes": features.get("time_since_break", 9999),
                "recent_task_completion_rate": features.get("completion_rate", 0),
                "wellbeing_overall": features.get("wellbeing_overall"),
                "wellbeing_fatigue": features.get("wellbeing_fatigue"),
                "wellbeing_workload": features.get("wellbeing_workload"),
                "wellbeing_focus": features.get("wellbeing_focus"),
                "wellbeing_recovery": features.get("wellbeing_recovery"),
                "wellbeing_stress_count": features.get("wellbeing_stress"),
                "preferred_interval_minutes": 30,
                "has_active_break": False,
                "last_break_duration_minutes": 0,
            }
            score = _score_candidate("SHORT_BREAK", heuristic_features)
            # Convert score to binary prediction (threshold at 0.5)
            pred = 1 if score > 0.5 else 0
            heuristic_preds.append(pred)

        heuristic_preds = np.array(heuristic_preds)

        return {
            "f1": float(f1_score(y_test, heuristic_preds, zero_division=0)),
            "precision": float(precision_score(y_test, heuristic_preds, zero_division=0)),
            "recall": float(recall_score(y_test, heuristic_preds, zero_division=0)),
            "accuracy": float(accuracy_score(y_test, heuristic_preds)),
            "test_sample_count": len(y_test),
            "test_unique_users": len(set(test_groups)),
            "evaluation_scope": "SHORT_BREAK only",
            "evaluation_scope_note": "Heuristic baseline evaluation limited to SHORT_BREAK candidate type due to insufficient labeled data for other recommendation types."
        }
    except Exception:
        return None


def get_latest_active_model(db: Session, dataset: str = "production") -> Optional[MLModel]:
    """
    Retrieve the most recent active ML model from the database for the specified dataset context.
    Returns None if no active model exists.
    Any active model (regardless of training dataset context: production, experimental, or combined)
    is eligible to serve production inference.
    """
    query = db.query(MLModel).filter(MLModel.is_active == True)
    if dataset == "experimental":
        query = query.filter(MLModel.version.like("%experimental%"))
    return query.order_by(MLModel.training_date.desc()).first()


def predict_with_model(db: Session, features_dict: Dict[str, Any], recommendation_type: str) -> Optional[float]:
    """
    Use the latest active PRODUCTION model to predict probability of acceptance.
    Returns probability (float in [0,1]) if model exists and can predict, else None.
    Handles both V1 and V2 feature sets based on model's feature_set_version.
    """
    start_time = time.time()
    model_record = get_latest_active_model(db, dataset="production")
    if model_record is None:
        logger.info("predict_with_model: No active production model found; fallback active.")
        return None

    try:
        model_or_pipeline = load_model_artifact(model_record)
        if model_or_pipeline is None:
            logger.error(f"predict_with_model: Failed to load artifact for model_id={model_record.id}")
            return None
    except Exception as e:
        logger.error(f"predict_with_model: Exception loading artifact: {e}")
        return None

    # Prepare input for prediction
    feature_dict = features_dict.copy()
    feature_dict["recommendation_type"] = recommendation_type

    try:
        import pandas as pd
        df = pd.DataFrame([feature_dict])
        if hasattr(model_record, 'feature_set_version') and model_record.feature_set_version == "v2-wellbeing":
            feature_keys = V2_ALL_FEATURE_KEYS
            numeric_keys = V2_NUMERIC_FEATURE_KEYS
        else:
            feature_keys = V1_ALL_FEATURE_KEYS
            numeric_keys = V1_NUMERIC_FEATURE_KEYS

        for key in feature_keys:
            if key not in df.columns:
                df[key] = 0.0 if key in numeric_keys else ""
        X = df[feature_keys]
        prob = model_or_pipeline.predict_proba(X)[0, 1]
        latency_ms = (time.time() - start_time) * 1000.0
        logger.info(f"ML Inference Success: model_id={model_record.id}, version={model_record.version}, latency_ms={latency_ms:.2f}, prob={prob:.4f}")
        return float(prob)
    except Exception as e:
        logger.error(f"ML Inference Exception: model_id={model_record.id}, error={e}")
        return None


def evaluate_model(db: Session, model_id: uuid.UUID, dataset: str = "production") -> Optional[Dict[str, Any]]:
    """
    Evaluate a given model (by ID) on the current labeled data.
    Returns metrics dict if evaluation possible, else None.
    Handles both V1 and V2 feature sets based on model's feature_set_version.
    """
    if not SKLEARN_AVAILABLE:
        return None

    # Fetch the model record
    model_record = db.query(MLModel).filter(MLModel.id == model_id).first()
    if model_record is None:
        return None

    model_or_pipeline = load_model_artifact(model_record)
    if model_or_pipeline is None:
        return None

    # Extract labeled data
    features_list, labels, _, user_ids = _extract_training_data(db, dataset=dataset)
    if len(labels) == 0:
        return None

    try:
        import pandas as pd
        df = pd.DataFrame(features_list)
        # Determine which feature set to use based on model's feature_set_version
        if hasattr(model_record, 'feature_set_version') and model_record.feature_set_version == "v2-wellbeing":
            # Use V2 feature set
            feature_keys = V2_ALL_FEATURE_KEYS
            numeric_keys = V2_NUMERIC_FEATURE_KEYS
        else:
            # Default to V1 feature set
            feature_keys = V1_ALL_FEATURE_KEYS
            numeric_keys = V1_NUMERIC_FEATURE_KEYS

        # Ensure all required columns are present
        for key in feature_keys:
            if key not in df.columns:
                df[key] = 0.0 if key in numeric_keys else ""
        X = df[feature_keys]
    except ImportError:
        return None

    try:
        preds = model_or_pipeline.predict(X)
        probs = model_or_pipeline.predict_proba(X)[:, 1] if hasattr(model_or_pipeline, "predict_proba") else np.zeros(len(labels))
        cm = confusion_matrix(labels, preds).tolist()
        cv_res = _evaluate_with_cross_validation(X, np.array(labels), user_ids)

        metrics = {
            "accuracy": float(accuracy_score(labels, preds)),
            "precision": float(precision_score(labels, preds, zero_division=0)),
            "recall": float(recall_score(labels, preds, zero_division=0)),
            "f1": float(f1_score(labels, preds, zero_division=0)),
            "roc_auc": float(roc_auc_score(labels, probs)) if len(set(labels)) > 1 else 0.5,
            "confusion_matrix": cm,
            "sample_count": len(labels),
            "small_sample_limitation": len(labels) < 50,
            "limitation_note": "Evaluated on small sample (< 50 labeled records); metrics and CV estimates may exhibit high variance." if len(labels) < 50 else None,
            **cv_res
        }
        return metrics
    except Exception:
        return None


def activate_model(db: Session, model_id: uuid.UUID) -> bool:
    """
    Activate a model by setting is_active=True. Deactivates all other models.
    Returns True if successful.
    """
    try:
        model = db.query(MLModel).filter(MLModel.id == model_id).first()
        if model is None:
            return False

        # Deactivate all other models so there is a single active production model
        db.query(MLModel).update({MLModel.is_active: False})

        model.is_active = True
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


def assess_data_sufficiency(db: Session, dataset: str = "production") -> Dict[str, Any]:
    """
    Assess whether we have enough data to train a model.
    Returns a dict with counts and recommendations.
    """
    rows = list(_iter_labeled_feedback(db, dataset))
    total = len(rows)
    labeled = total
    accepted = sum(1 for r in rows if r.user_action == POSITIVE_LABEL)
    dismissed = sum(1 for r in rows if r.user_action == "dismissed")
    ignored = sum(1 for r in rows if r.user_action == "ignored")

    # null_pending count
    test_user_ids = _get_test_user_ids(db)
    all_null_rows = db.query(RecommendationFeedback).filter(RecommendationFeedback.user_action.is_(None)).all()
    null_actions = sum(1 for r in all_null_rows if _matches_dataset_context(r, dataset, test_user_ids))

    type_dist = {}
    for r in rows:
        t = r.recommendation_type
        type_dist[t] = type_dist.get(t, 0) + 1

    sufficient = (
        labeled >= MINIMUM_TRAINING_SAMPLES and
        accepted >= 5 and (dismissed + ignored) >= 5
    )

    return {
        "dataset_context": dataset,
        "total_feedback": total,
        "labeled_feedback": labeled,
        "accepted": accepted,
        "dismissed": dismissed,
        "ignored": ignored,
        "null_pending": null_actions,
        "candidate_type_distribution": type_dist,
        "sufficient_for_training": sufficient,
        "minimum_required": MINIMUM_TRAINING_SAMPLES,
        "note": f"Training requires at least MINIMUM_TRAINING_SAMPLES labeled records, with at least 5 in each class. Current dataset context: {dataset}.",
        "test_data_explanation": "Production context excludes test/demo data; experimental includes only test/demo data; all includes combined dataset.",
    }

# ---------------------------------------------------------------------------
# A-01 TASK 1 & 2: Persistent training-job lifecycle + atomic duplicate guard
# ---------------------------------------------------------------------------

# Terminal states — a job in one of these never blocks a future reservation.
_TERMINAL_JOB_STATUSES = ("COMPLETED", "FAILED", "INTERRUPTED")


def reserve_training_job(db: Session, dataset: str, requested_by) -> Optional[MLTrainingJob]:
    """
    Atomically reserve a training job, rejecting duplicates while an active job exists.
    """
    db.rollback()
    recover_interrupted_training_jobs(db)
    try:
        db.expire_all()
        active = db.query(MLTrainingJob).filter(
            MLTrainingJob.status.in_(["SCHEDULED", "RUNNING"])
        ).first()

        if active is not None:
            return None

        job = MLTrainingJob(status="SCHEDULED", dataset=dataset, requested_by=requested_by)
        db.add(job)
        db.commit()
        db.refresh(job)
        return job
    except Exception:
        db.rollback()
        return None


def mark_job_running(db: Session, job_id: uuid.UUID) -> None:
    job = db.query(MLTrainingJob).filter(MLTrainingJob.id == job_id).first()
    if job:
        job.status = "RUNNING"
        job.started_at = datetime.now(timezone.utc)
        db.commit()


def mark_job_completed(db: Session, job_id: uuid.UUID, model_id: uuid.UUID, extracted_samples: Optional[int] = None, positive_count: Optional[int] = None, negative_count: Optional[int] = None) -> None:
    job = db.query(MLTrainingJob).filter(MLTrainingJob.id == job_id).first()
    if job:
        job.status = "COMPLETED"
        job.completed_at = datetime.now(timezone.utc)
        job.model_id = model_id
        if extracted_samples is not None:
            job.extracted_samples = extracted_samples
        if positive_count is not None:
            job.positive_count = positive_count
        if negative_count is not None:
            job.negative_count = negative_count
        if job.started_at and job.completed_at:
            job.duration_seconds = (job.completed_at - job.started_at).total_seconds()
        db.commit()


def mark_job_failed(db: Session, job_id: uuid.UUID, error_message: str, extracted_samples: Optional[int] = None, positive_count: Optional[int] = None, negative_count: Optional[int] = None) -> None:
    job = db.query(MLTrainingJob).filter(MLTrainingJob.id == job_id).first()
    if job:
        job.status = "FAILED"
        job.completed_at = datetime.now(timezone.utc)
        job.error_message = error_message
        if extracted_samples is not None:
            job.extracted_samples = extracted_samples
        if positive_count is not None:
            job.positive_count = positive_count
        if negative_count is not None:
            job.negative_count = negative_count
        if job.started_at and job.completed_at:
            job.duration_seconds = (job.completed_at - job.started_at).total_seconds()
        db.commit()


def recover_interrupted_training_jobs(db: Session) -> int:
    """
    Mark jobs left in SCHEDULED/RUNNING by an interrupted process as INTERRUPTED.
    FastAPI BackgroundTasks are in-process and NOT durable across restarts, so a
    job that never reached a terminal state before shutdown is unrecoverable.
    This does NOT resume the job; it only records its terminal INTERRUPTED state
    so it no longer blocks future reservations. Returns the number recovered.
    Only jobs older than STALE_JOB_TIMEOUT (1 hour) or without created_at are considered interrupted.
    """
    from datetime import timedelta
    STALE_JOB_TIMEOUT = timedelta(hours=1)
    cutoff = datetime.now(timezone.utc) - STALE_JOB_TIMEOUT
    rows = db.query(MLTrainingJob).filter(
        MLTrainingJob.status.in_(["SCHEDULED", "RUNNING"]),
        MLTrainingJob.id != uuid.UUID("00000000-0000-0000-0000-000000000000"),
        (MLTrainingJob.created_at < cutoff) | (MLTrainingJob.created_at.is_(None)),
    ).all()
    now = datetime.now(timezone.utc)
    for job in rows:
        job.status = "INTERRUPTED"
        job.completed_at = now
        if not job.error_message:
            job.error_message = "Interrupted by application restart (BackgroundTasks are not durable)."
    if rows:
        db.commit()
    return len(rows)


def run_training_job(job_id: uuid.UUID, dataset: str) -> None:
    """
    Background execution of one reserved training job. Runs in its own database
    session (created here, closed in finally) so it is independent of the original
    request session. Never auto-activates the candidate.
    """
    db = SessionLocal()
    extracted_samples = 0
    positive_count = 0
    negative_count = 0
    try:
        mark_job_running(db, job_id)

        # Extract training data first to record actual extraction metrics on the job
        features_list, labels, _, user_ids = _extract_training_data(db, dataset=dataset)
        extracted_samples = len(labels)
        positive_count = int(sum(labels)) if labels else 0
        negative_count = extracted_samples - positive_count

        # Update job record immediately after extraction
        job = db.query(MLTrainingJob).filter(MLTrainingJob.id == job_id).first()
        if job:
            job.extracted_samples = extracted_samples
            job.positive_count = positive_count
            job.negative_count = negative_count
            db.commit()

        # Train (candidate is created with is_active=False inside train_model)
        result = train_model(db, dataset=dataset)
        if not result:
            mark_job_failed(db, job_id, "Training produced no model (insufficient data or scikit-learn unavailable).", extracted_samples, positive_count, negative_count)
            return

        model_id = uuid.UUID(result["model_id"])

        # TASK 3: set PENDING before evaluation, persist evidence, then resolve.
        model = db.query(MLModel).filter(MLModel.id == model_id).first()
        if model:
            model.validation_status = "PENDING"
            db.commit()

        try:
            evaluation = evaluate_candidate(db, model_id, dataset=dataset)
        except Exception as exc:  # evaluation must not leave candidate PENDING forever
            db.rollback()
            evaluation = {"result": "FAILED", "reason": f"Evaluation raised: {exc}", "metrics": None}

        evidence = {
            "evaluation_scope": dataset,
            "evaluated_at": datetime.now(timezone.utc).isoformat(),
            "feature_schema_version": getattr(model, "feature_set_version", None) if model else None,
            "result": evaluation.get("result"),
            "reason": evaluation.get("reason"),
            "metrics": evaluation.get("metrics"),
            "comparison": evaluation.get("comparison"),
            "acceptance_criteria": evaluation.get("acceptance_criteria"),
        }
        if model:
            model.metrics = evidence
            model.validation_status = "PASSED" if evaluation.get("result") == "PASSED" else "FAILED"
            db.commit()

        mark_job_completed(db, job_id, model_id, extracted_samples, positive_count, negative_count)
    except Exception as exc:
        db.rollback()
        try:
            mark_job_failed(db, job_id, f"Training job failed: {exc}", extracted_samples, positive_count, negative_count)
        except Exception:
            pass
    finally:
        db.close()
