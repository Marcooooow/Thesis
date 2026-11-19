"""
ML Service for Work Pattern Decline Prediction
==============================================

This service provides an API endpoint for predicting work pattern decline
using trained machine learning models. It loads the latest trained model
and makes predictions based on user data.

IMPORTANT: The model outputs P(imminent work-pattern decline) - the probability
that task completion rate will significantly decline in the subsequent 20-40
minute window compared to the user's personal baseline.

This does NOT measure:
- fatigue
- stress
- mental health
- medical condition
- worker performance rating
- human worth
- productivity score

DEPLOYMENT STATUS: As of 2026-11-10, no production-trained model is deployed.
The model artifact at ml_models/latest_model.pkl is a SYNTHETIC model trained
on synthetic data (RandomForest_Synthetic, 2026-09-07). It uses 7 features that
do not match the 8 features expected by the production feature extractor.
This endpoint returns 501 Not Implemented to prevent misuse of the synthetic model.
The thesis scope is recommendation-acceptance prediction, not work-pattern decline.
"""

import os
import sys
import json
import pickle
from datetime import datetime
from typing import Dict, Any, Optional
import numpy as np
import pandas as pd
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User, Profile, Task, WorkSession, Break

router = APIRouter(
    prefix="/ml",
    tags=["ml"],
    responses={404: {"description": "Not found"}},
)

# Global variables for model caching
_model_cache = None
_model_metadata = None

# Known synthetic model identifiers
_SYNTHETIC_MODEL_NAME = "RandomForest_Synthetic"
_SYNTHETIC_TRAINING_TIMESTAMP = "20260907_152548"


def _is_synthetic_model(metadata: Optional[Dict[str, Any]]) -> bool:
    """Check if the loaded model is the known synthetic model."""
    if not metadata:
        return False
    model_name = metadata.get('model_name', '')
    training_ts = metadata.get('training_timestamp', '')
    return (
        model_name == _SYNTHETIC_MODEL_NAME or
        training_ts == _SYNTHETIC_TRAINING_TIMESTAMP
    )


def _load_latest_model():
    """Load the latest trained model from disk.

    Returns:
        tuple: (model, metadata) or (None, None) if no model available.
               Synthetic models are treated as unavailable for production predictions.
    """
    global _model_cache, _model_metadata

    if _model_cache is not None:
        return _model_cache, _model_metadata

    # Look for latest model in ml_models directory
    models_dir = os.path.join(os.path.dirname(__file__), '../../../ml_models')
    latest_model_path = os.path.join(models_dir, "latest_model.pkl")

    if not os.path.exists(latest_model_path):
        return None, None

    try:
        with open(latest_model_path, 'rb') as f:
            model_data = pickle.load(f)

        metadata = {
            'model_name': model_data['model_name'],
            'feature_names': model_data['feature_names'],
            'training_timestamp': model_data['training_timestamp'],
            'performance': model_data['performance'],
            'training_config': model_data.get('training_config', {})
        }

        # Check if this is the synthetic model
        if _is_synthetic_model(metadata):
            # Log but don't cache as production model
            import logging
            logger = logging.getLogger(__name__)
            logger.warning(
                f"Synthetic model detected ({metadata['model_name']}, "
                f"trained {metadata['training_timestamp']}). "
                "Not loading for production predictions. "
                "Thesis scope: recommendation-acceptance prediction only."
            )
            return None, {
                **metadata,
                'deployment_status': 'synthetic-not-deployed',
                'note': 'This is a synthetic model trained on synthetic data. '
                        'Not suitable for production predictions. '
                        'Work-pattern decline prediction is not deployed; '
                        'thesis scope is recommendation-acceptance prediction.'
            }

        _model_cache = model_data['model']
        _model_metadata = metadata

        return _model_cache, _model_metadata
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"Error loading ML model: {e}")
        return None, None


@router.post("/predict-decline")
async def predict_decline_probability(
    request: Dict[str, Any],
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Predict work pattern decline probability for the current user

    Expected request body:
    {
        "token": "user's authentication token"
    }

    Returns:
    {
        "decline_probability": 0.0-1.0,
        "model_used": "model_name",
        "timestamp": "ISO timestamp",
        "confidence_level": "low/medium/high"
    }
    """
    # This endpoint is not implemented because no production-trained model is deployed.
    # The model artifact at ml_models/latest_model.pkl is a synthetic model trained
    # on synthetic data (RandomForest_Synthetic, 2026-09-07) with mismatched features.
    # Thesis scope: recommendation-acceptance prediction, not work-pattern decline.
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail={
            "message": "Work-pattern decline prediction is not deployed.",
            "reason": "The available model artifact (ml_models/latest_model.pkl) is a synthetic model "
                      "trained on synthetic data (RandomForest_Synthetic, 2026-09-07). It uses 7 features "
                      "that do not match the 8 features expected by the production feature extractor. "
                      "Using it for predictions would produce meaningless results.",
            "thesis_scope": "The thesis focuses on recommendation-acceptance prediction, "
                            "not work-pattern decline prediction. See /recommend/health for "
                            "the deployed recommendation system status.",
            "alternative": "For break recommendations with ML enhancement, use /recommend/generate "
                           "which uses a heuristic baseline with optional ML enhancement for "
                           "recommendation-acceptance prediction (activated after sufficient feedback)."
        }
    )


@router.get("/model-info")
async def get_model_info(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get information about the currently loaded ML model
    """
    model, metadata = _load_latest_model()
    if model is None:
        # Check if synthetic model exists but is not deployed
        models_dir = os.path.join(os.path.dirname(__file__), '../../../ml_models')
        latest_model_path = os.path.join(models_dir, "latest_model.pkl")
        if os.path.exists(latest_model_path):
            try:
                with open(latest_model_path, 'rb') as f:
                    model_data = pickle.load(f)
                metadata = {
                    'model_name': model_data['model_name'],
                    'feature_names': model_data['feature_names'],
                    'training_timestamp': model_data['training_timestamp'],
                    'performance': model_data['performance'],
                    'training_config': model_data.get('training_config', {}),
                    'deployment_status': 'synthetic-not-deployed',
                    'note': 'This is a synthetic model trained on synthetic data. '
                            'Not suitable for production predictions. '
                            'Work-pattern decline prediction is not deployed; '
                            'thesis scope is recommendation-acceptance prediction.'
                }
                return metadata
            except Exception:
                pass
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "message": "No production ML model available.",
                "note": "Work-pattern decline prediction is not deployed. "
                        "Thesis scope: recommendation-acceptance prediction only. "
                        "See /recommend/health for deployed recommendation system status."
            }
        )

    return {
        "model_name": metadata['model_name'] if metadata else "unknown",
        "training_timestamp": metadata['training_timestamp'] if metadata else None,
        "performance": metadata['performance'] if metadata else None,
        "feature_count": len(metadata['feature_names']) if metadata and metadata['feature_names'] else 0,
        "training_config": metadata.get('training_config', {}) if metadata else {},
        "deployment_status": "active"
    }


@router.get("/health")
async def ml_health_check():
    """
    Health check for ML service
    """
    model, metadata = _load_latest_model()
    if model is None:
        # Check if synthetic model exists but is not deployed
        models_dir = os.path.join(os.path.dirname(__file__), '../../../ml_models')
        latest_model_path = os.path.join(models_dir, "latest_model.pkl")
        if os.path.exists(latest_model_path):
            try:
                with open(latest_model_path, 'rb') as f:
                    model_data = pickle.load(f)
                return {
                    "status": "degraded",
                    "model_loaded": False,
                    "model_available_on_disk": True,
                    "model_name": model_data['model_name'],
                    "training_timestamp": model_data['training_timestamp'],
                    "deployment_status": "synthetic-not-deployed",
                    "message": "Synthetic model artifact exists but is not loaded for production. "
                               "Work-pattern decline prediction is not deployed. "
                               "Thesis scope: recommendation-acceptance prediction only."
                }
            except Exception:
                pass
        return {
            "status": "unhealthy",
            "model_loaded": False,
            "model_available_on_disk": False,
            "message": "No ML model artifact found. Work-pattern decline prediction not deployed."
        }

    return {
        "status": "healthy",
        "model_loaded": True,
        "model_name": metadata['model_name'] if metadata else "unknown",
        "deployment_status": "active",
        "message": "ML service is operational with production-trained model"
    }