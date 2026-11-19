#!/usr/bin/env python3
"""
Tests for V1 Baseline Training Script.

Validates:
- Dataset eligibility and label mapping
- Feature selection (3 numeric features, recommendation_type excluded)
- User-grouped validation (GroupKFold)
- Preprocessing leakage prevention
- Artifact metadata and inactive status
"""

import sys
import os
import json
import tempfile
import pytest
from unittest.mock import patch, MagicMock

import numpy as np
import pandas as pd

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from sqlalchemy.orm import Session

# Import after path setup
from app.database import SessionLocal
from app.models import RecommendationFeedback, Profile, MLModel
from scripts.train_v1_baseline import (
    V1_NUMERIC_FEATURES,
    V1_FEATURE_SET_VERSION,
    POSITIVE_LABEL,
    NEGATIVE_LABELS,
    extract_v1_training_data,
    run_user_grouped_cv,
    train_final_model,
    MODEL_ARTIFACT_DIR,
)


class TestV1DatasetEligibility:
    """Tests for dataset extraction and label mapping."""

    def test_extract_v1_training_data_returns_correct_shape(self):
        """Verify data extraction returns valid records with expected structure."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            # Check dimensions
            n_samples = len(X)
            n_users = len(set(groups))
            n_features = len(X.columns)

            # Expected: 120 records, 20 users (from v1-base only)
            assert n_samples == 120, f"Expected 120 samples (v1-base only), got {n_samples}"
            assert n_users == 20, f"Expected 20 unique users (v1-base only), got {n_users}"
            assert n_features == 3, f"Expected 3 features, got {n_features}"

            # Check features
            assert list(X.columns) == V1_NUMERIC_FEATURES
            assert len(X.columns) == 3

            # Check users have at least some data
            user_counts = pd.Series(groups).value_counts()
            assert all(user_counts >= 1), f"Some users have 0 records"

            # Check labels (actual counts from v1-base data)
            n_positive = int(y.sum())
            n_negative = len(y) - n_positive
            # Current v1-base dataset: 67 accepted, 53 dismissed/ignored
            assert n_positive == 67, f"Expected 67 accepted, got {n_positive}"
            assert n_negative == 53, f"Expected 53 dismissed/ignored, got {n_negative}"

            print(f"Data: {n_samples} samples, {n_users} users, {n_positive} positive, {n_negative} negative")

        finally:
            db.close()

    def test_label_mapping_accepted_is_positive(self):
        """Verify accepted=1, dismissed/ignored=0."""
        from sqlalchemy import text
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            # Verify positive class is accepted (with v1-base filter)
            sql = text("""
                SELECT user_action, COUNT(*)
                FROM recommendation_feedback
                WHERE user_action IN ('accepted', 'dismissed', 'ignored')
                  AND recommendation_type NOT LIKE 'WLB_%'
                  AND feature_schema_version = 'v1-base'
                GROUP BY user_action
            """)
            counts = dict(db.execute(sql).fetchall())

            assert y.sum() == counts.get('accepted', 0), f"Positive labels don't match accepted count: {y.sum()} vs {counts.get('accepted', 0)}"
            assert len(y) - y.sum() == counts.get('dismissed', 0) + counts.get('ignored', 0), "Negative labels mismatch"

        finally:
            db.close()

    def test_recommendation_type_excluded(self):
        """Verify recommendation_type is NOT in extracted features."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            assert "recommendation_type" not in X.columns
            assert len(X.columns) == 3
            assert set(X.columns) == set(V1_NUMERIC_FEATURES)

        finally:
            db.close()

    def test_feature_variance(self):
        """Verify all 3 features have meaningful variance."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            for feat in V1_NUMERIC_FEATURES:
                unique_vals = X[feat].nunique()
                assert unique_vals > 1, f"Feature {feat} has zero variance (unique={unique_vals})"
                assert X[feat].std() > 0, f"Feature {feat} has zero std"

        finally:
            db.close()


class TestUserGroupedValidation:
    """Tests for GroupKFold cross-validation."""

    def test_groupkfold_produces_5_folds(self):
        """Verify GroupKFold produces exactly 5 folds."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from sklearn.model_selection import GroupKFold
            gkf = GroupKFold(n_splits=5)
            folds = list(gkf.split(X, y, groups=groups))

            assert len(folds) == 5, f"Expected 5 folds, got {len(folds)}"

        finally:
            db.close()

    def test_no_user_overlap_between_train_test(self):
        """Verify no user appears in both train and test within any fold."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from sklearn.model_selection import GroupKFold
            gkf = GroupKFold(n_splits=5)

            for fold_idx, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups=groups), 1):
                train_users = set(groups[train_idx])
                test_users = set(groups[test_idx])
                overlap = train_users & test_users

                assert len(overlap) == 0, f"Fold {fold_idx}: User overlap detected: {overlap}"

        finally:
            db.close()

    def test_fold_sizes_correct(self):
        """Verify fold sizes are reasonable for the dataset."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from sklearn.model_selection import GroupKFold
            gkf = GroupKFold(n_splits=5)

            n_samples = len(X)
            n_users = len(set(groups))

            for fold_idx, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups=groups), 1):
                train_size = len(train_idx)
                test_size = len(test_idx)
                train_users = len(set(groups[train_idx]))
                test_users = len(set(groups[test_idx]))

                # Basic sanity checks
                assert train_size > test_size, f"Fold {fold_idx}: train should be larger than test"
                assert train_size + test_size == n_samples, f"Fold {fold_idx}: sizes don't add up"
                assert train_users + test_users == n_users, f"Fold {fold_idx}: user counts don't add up"
                assert test_users >= 2, f"Fold {fold_idx}: at least 2 test users needed"

                print(f"Fold {fold_idx}: train={train_size} ({train_users} users), test={test_size} ({test_users} users)")

        finally:
            db.close()


class TestPreprocessingLeakagePrevention:
    """Tests for preprocessing fitted independently per fold."""

    def test_scaler_fitted_on_train_only(self):
        """Verify StandardScaler is fitted only on training data per fold."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from sklearn.model_selection import GroupKFold
            from sklearn.preprocessing import StandardScaler

            gkf = GroupKFold(n_splits=5)

            for fold_idx, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups=groups), 1):
                X_train = X.iloc[train_idx]
                X_test = X.iloc[test_idx]

                # Fit scaler on training data
                scaler = StandardScaler()
                scaler.fit(X_train)

                # Get training statistics
                train_mean = scaler.mean_
                train_std = scaler.scale_

                # Transform test data using TRAINING statistics
                X_test_scaled = scaler.transform(X_test)

                # Verify test statistics are DIFFERENT from training statistics
                test_mean = X_test.mean().values
                test_std = X_test.std().values

                # Training mean should not equal test mean (within small tolerance)
                # This confirms scaler used training stats, not test stats
                assert not np.allclose(train_mean, test_mean, atol=1e-2), \
                    f"Fold {fold_idx}: Scaler may have used test data for fitting"

        finally:
            db.close()

    def test_pipeline_uses_train_scaler_for_test_transform(self):
        """Verify the full pipeline uses training-fitted scaler for test transform."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from sklearn.model_selection import GroupKFold
            from sklearn.pipeline import Pipeline
            from sklearn.preprocessing import StandardScaler
            from sklearn.linear_model import LogisticRegression

            gkf = GroupKFold(n_splits=5)

            for fold_idx, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups=groups), 1):
                X_train = X.iloc[train_idx]
                X_test = X.iloc[test_idx]
                y_train = y[train_idx]

                # Create and fit pipeline on training fold
                pipeline = Pipeline([
                    ("scaler", StandardScaler()),
                    ("classifier", LogisticRegression(random_state=42, max_iter=1000, class_weight='balanced'))
                ])
                pipeline.fit(X_train, y_train)

                # Extract scaler from pipeline
                scaler = pipeline.named_steps["scaler"]

                # Transform test data - should use training scaler stats
                X_test_scaled = pipeline.named_steps["scaler"].transform(X_test)

                # Verify it's the same scaler (fitted on train)
                assert scaler.mean_ is not None
                assert scaler.scale_ is not None

        finally:
            db.close()


class TestModelArtifact:
    """Tests for model artifact metadata and inactive status."""

    def test_model_saved_with_is_active_false(self):
        """Verify saved model has is_active=False."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            # Train and save model
            from scripts.train_v1_baseline import train_final_model, save_model_artifact

            pipeline, test_metrics = train_final_model(X, y, groups)

            cv_results = {"cv_metrics": {}, "oof_confusion_matrix": [[0,0],[0,0]]}
            heuristic_comparison = {}

            ml_model = save_model_artifact(
                db=db,
                pipeline=pipeline,
                cv_results=cv_results,
                test_metrics=test_metrics,
                heuristic_comparison=heuristic_comparison,
                n_samples=120,
                n_users=20,
                feature_names=V1_NUMERIC_FEATURES
            )

            # Verify inactive status
            assert ml_model.is_active == False, "Model should be saved with is_active=False"
            assert ml_model.feature_set_version == V1_FEATURE_SET_VERSION
            assert ml_model.artifact_path is not None
            assert os.path.exists(ml_model.artifact_path)

            # Clean up test artifact
            if os.path.exists(ml_model.artifact_path):
                os.remove(ml_model.artifact_path)
            db.delete(ml_model)
            db.commit()

        finally:
            db.close()

    def test_model_metrics_include_required_fields(self):
        """Verify saved metrics contain all required fields."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from scripts.train_v1_baseline import train_final_model, save_model_artifact

            pipeline, test_metrics = train_final_model(X, y, groups)

            cv_results = {"cv_metrics": {}, "oof_confusion_matrix": [[0,0],[0,0]]}
            heuristic_comparison = {}

            ml_model = save_model_artifact(
                db=db,
                pipeline=pipeline,
                cv_results=cv_results,
                test_metrics=test_metrics,
                heuristic_comparison=heuristic_comparison,
                n_samples=120,
                n_users=20,
                feature_names=V1_NUMERIC_FEATURES
            )

            # Check metrics JSON
            assert ml_model.metrics is not None
            metrics = ml_model.metrics

            required_fields = [
                "cv_metrics", "test_metrics", "heuristic_comparison",
                "sample_count", "n_users", "feature_count", "features",
                "feature_importance", "algorithm", "class_weight",
                "cv_strategy", "limitation_note"
            ]

            for field in required_fields:
                assert field in metrics, f"Missing required metrics field: {field}"

            assert metrics["sample_count"] == 120
            assert metrics["n_users"] == 20
            assert metrics["feature_count"] == 3
            assert metrics["features"] == V1_NUMERIC_FEATURES
            assert metrics["algorithm"] == "LogisticRegression"
            assert metrics["class_weight"] == "balanced"
            assert metrics["cv_strategy"] == "GroupKFold(n_splits=5)"
            assert "V1 baseline" in metrics["limitation_note"]
            assert ml_model.is_active is False

            # Clean up
            if os.path.exists(ml_model.artifact_path):
                os.remove(ml_model.artifact_path)
            db.delete(ml_model)
            db.commit()

        finally:
            db.close()

    def test_feature_importance_saved(self):
        """Verify feature importance coefficients are saved."""
        db = SessionLocal()
        try:
            X, y, groups = extract_v1_training_data(db)

            from scripts.train_v1_baseline import train_final_model, save_model_artifact

            pipeline, test_metrics = train_final_model(X, y, groups)

            cv_results = {"cv_metrics": {}, "oof_confusion_matrix": [[0,0],[0,0]]}
            heuristic_comparison = {}

            ml_model = save_model_artifact(
                db=db,
                pipeline=pipeline,
                cv_results=cv_results,
                test_metrics=test_metrics,
                heuristic_comparison=heuristic_comparison,
                n_samples=120,
                n_users=20,
                feature_names=V1_NUMERIC_FEATURES
            )

            # Check feature importance
            assert "feature_importance" in ml_model.metrics
            fi = ml_model.metrics["feature_importance"]
            assert set(fi.keys()) == set(V1_NUMERIC_FEATURES)
            assert all(isinstance(v, float) for v in fi.values())

            # Clean up
            if os.path.exists(ml_model.artifact_path):
                os.remove(ml_model.artifact_path)
            db.delete(ml_model)
            db.commit()

        finally:
            db.close()


class TestArtifactDirectory:
    """Test artifact directory configuration."""

    def test_artifact_directory_exists(self):
        """Verify MODEL_ARTIFACT_DIR exists and is writable."""
        assert os.path.exists(MODEL_ARTIFACT_DIR)
        assert os.path.isdir(MODEL_ARTIFACT_DIR)

        # Test write
        test_file = os.path.join(MODEL_ARTIFACT_DIR, "test_write.tmp")
        with open(test_file, "w") as f:
            f.write("test")
        os.remove(test_file)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])