"""
Canonical V2 Feature Schema for Recommendation Acceptance Prediction.
====================================================================

This module defines the single source of truth for feature engineering
used by both the training pipeline (ml_training_pipeline.py) and
the inference service (recommendation_service.py).

SCHEMA VERSION: v2-wellbeing
FEATURE COUNT: 10 features (9 numeric + 1 categorical)

Numeric Features (imputed with 0.0, then standardized):
1. session_length          - Active work session duration in minutes
2. time_since_break        - Minutes since last completed break
3. completion_rate         - Recent task completion rate (0.0-1.0)
4. wellbeing_overall       - Normalized overall wellbeing (1-5) -> (0.0-1.0)
5. wellbeing_fatigue       - Normalized mental fatigue (1-5) -> (0.0-1.0)
6. wellbeing_workload      - Normalized workload manageability (1-5) -> (0.0-1.0)
5. wellbeing_focus         - Normalized perceived focus (1-5) -> (0.0-1.0)
6. wellbeing_recovery      - Normalized break recovery (1-5) -> (0.0-1.0)
7. wellbeing_stress        - Stress factor count (0+)

Categorical Feature (one-hot encoded):
8. recommendation_type     - One of: SHORT_BREAK, WALK, HYDRATE, STRETCH, LUNCH

EXCLUDED FROM ML FEATURES (available for heuristic rules only):
- current_focus_rate       - Real-time focus rate (not available at training time)
- detected_pattern_ids     - Behavioral pattern array (not ML-compatible)

MISSING VALUE HANDLING:
- All numeric features: np.nan during extraction -> 0.0 via SimpleImputer(fill_value=0.0) -> StandardScaler
- Categorical: "" (empty string) -> OneHotEncoder(handle_unknown="ignore")

TEMPORAL SAFETY:
- Training uses feature_snapshot captured at recommendation generation time
- Inference uses feature_snapshot from live feature extraction
- Wellbeing features: use most recent ELIGIBLE check-in (completed session, check-in before generation)
- No future data leakage
"""

from typing import Dict, Any, List, Optional
from datetime import datetime, timezone
import numpy as np


# Canonical V2 feature schema
V2_NUMERIC_FEATURE_KEYS = [
    "session_length",
    "time_since_break",
    "completion_rate",
    "wellbeing_overall",
    "wellbeing_fatigue",
    "wellbeing_workload",
    "wellbeing_focus",
    "wellbeing_recovery",
    "wellbeing_stress",
]

V2_CATEGORICAL_FEATURE_KEYS = ["recommendation_type"]

V2_ALL_FEATURE_KEYS = V2_NUMERIC_FEATURE_KEYS + V2_CATEGORICAL_FEATURE_KEYS

# Feature schema version string
FEATURE_SCHEMA_VERSION = "v2-wellbeing"

# V1 feature schema (actual historical schema from v1_baseline artifacts)
# V1 models used 3 numeric features only: session_length, time_since_break, completion_rate
# No categorical features, no wellbeing features
V1_NUMERIC_FEATURE_KEYS = [
    "session_length",
    "time_since_break",
    "completion_rate"
]
V1_CATEGORICAL_FEATURE_KEYS = []
V1_ALL_FEATURE_KEYS = V1_NUMERIC_FEATURE_KEYS + V1_CATEGORICAL_FEATURE_KEYS

# Minimum training samples required
MINIMUM_TRAINING_SAMPLES = 20

# Label definitions
POSITIVE_LABEL = "accepted"
NEGATIVE_LABELS = {"dismissed", "ignored"}
EXCLUDED_LABELS = {"expired", "helpful", "not_helpful"}  # Not used for ML training


def build_feature_vector(
    feature_snapshot: Dict[str, Any],
    recommendation_type: str
) -> Dict[str, Any]:
    """
    Build a canonical V2 feature vector from a feature snapshot.

    This is the SINGLE function used by both training and inference
    to ensure feature consistency.

    Args:
        feature_snapshot: Dict with keys from V2_NUMERIC_FEATURE_KEYS (values may be None/np.nan)
        recommendation_type: One of the candidate types

    Returns:
        Dict with all V2_ALL_FEATURE_KEYS populated (None -> np.nan for numeric, "" for categorical)
    """
    feature_dict = {}

    # Numeric features - use np.nan for missing (will be imputed)
    for key in V2_NUMERIC_FEATURE_KEYS:
        val = feature_snapshot.get(key)
        if val is None:
            feature_dict[key] = np.nan
        else:
            try:
                feature_dict[key] = float(val)
            except (TypeError, ValueError):
                feature_dict[key] = np.nan

    # Categorical feature
    feature_dict["recommendation_type"] = recommendation_type or ""

    return feature_dict


def validate_feature_vector(feature_dict: Dict[str, Any]) -> bool:
    """
    Validate that a feature vector contains all required keys with valid types.

    Returns:
        True if valid, False otherwise
    """
    for key in V2_NUMERIC_FEATURE_KEYS:
        if key not in feature_dict:
            return False
        val = feature_dict[key]
        if val is not None and not (isinstance(val, (int, float)) or (isinstance(val, float) and np.isnan(val))):
            return False

    if "recommendation_type" not in feature_dict:
        return False

    return True


def extract_feature_snapshot_from_feedback_row(context_features: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract the canonical feature snapshot from a feedback record's context_features.

    Handles both V1 and V2 schema versions gracefully.

    Args:
        context_features: The context_features JSONB from recommendation_feedback

    Returns:
        Dict with V2_NUMERIC_FEATURE_KEYS (values may be None if not present)
    """
    if not context_features:
        return {}

    # Handle feature_snapshot nested structure (V2)
    if "feature_snapshot" in context_features:
        snapshot = context_features["feature_snapshot"]
        if isinstance(snapshot, dict):
            # Map old keys to canonical names
            mapped = {}
            key_mapping = {
                "session_length": "session_length",
                "time_since_break": "time_since_break",
                "completion_rate": "completion_rate",
                "wellbeing_overall": "wellbeing_overall",
                "wellbeing_fatigue": "wellbeing_fatigue",
                "wellbeing_workload": "wellbeing_workload",
                "wellbeing_focus": "wellbeing_focus",
                "wellbeing_recovery": "wellbeing_recovery",
                "wellbeing_stress_count": "wellbeing_stress",
                "wellbeing_stress": "wellbeing_stress",
            }
            for old_key, new_key in key_mapping.items():
                if old_key in snapshot:
                    mapped[new_key] = snapshot[old_key]
            return mapped

    # Direct V1 format (flat keys)
    mapped = {}
    key_mapping = {
        "session_length": "session_length",
        "time_since_break": "time_since_break",
        "completion_rate": "completion_rate",
        "wellbeing_overall": "wellbeing_overall",
        "wellbeing_fatigue": "wellbeing_fatigue",
        "wellbeing_workload": "wellbeing_workload",
        "wellbeing_focus": "wellbeing_focus",
        "wellbeing_recovery": "wellbeing_recovery",
        "wellbeing_stress_count": "wellbeing_stress",
    }
    for old_key, new_key in key_mapping.items():
        if old_key in context_features:
            mapped[new_key] = context_features[old_key]

    return mapped


# Training/Inference preprocessing config
def get_preprocessing_config():
    """
    Get the scikit-learn ColumnTransformer configuration for V2 features.

    Returns:
        Dict with 'numeric_keys', 'categorical_keys', 'all_keys'
    """
    return {
        "numeric_keys": V2_NUMERIC_FEATURE_KEYS,
        "categorical_keys": V2_CATEGORICAL_FEATURE_KEYS,
        "all_keys": V2_ALL_FEATURE_KEYS,
    }


# For backward compatibility with existing code
NUMERIC_FEATURE_KEYS = V2_NUMERIC_FEATURE_KEYS
CATEGORICAL_FEATURE_KEYS = V2_CATEGORICAL_FEATURE_KEYS
ALL_FEATURE_KEYS = V2_ALL_FEATURE_KEYS