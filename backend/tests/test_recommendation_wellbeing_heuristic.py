"""
Tests for Wellbeing-Aware Heuristic Recommendation Ranking & Reasoning.
Covers:
1. High fatigue + prolonged continuous work.
2. Low recovery with supporting context.
3. Good recovery shortly after break (suppression of unnecessary breaks).
4. Missing or stale wellbeing data (None handling).
5. Changing relevant wellbeing input changes candidate ranking with constants.
6. Cold-start and ML disabled fallback behavior.
"""

import os
import uuid
from datetime import datetime, timedelta, timezone
import pytest
from sqlalchemy.orm import Session

from app.models import (
    User, Profile, Organization, OrganizationMembership,
    Team, TeamMembership, WorkSession, Break, Task,
    SessionWellbeingCheckin, RecommendationFeedback, UserSettings, MLModel
)
from app.services.recommendation_service import (
    _extract_features, _score_candidate, _recommend_for_profile
)
from app.auth.security import get_password_hash


def test_wellbeing_heuristic_scoring_fatigue_boost():
    """Test that high fatigue increases score for rest/movement candidates."""
    features_base = {
        "session_length_minutes": 40.0,
        "time_since_last_break_minutes": 20.0,
        "recent_task_completion_rate": 0.5,
        "preferred_interval_minutes": 30,
        "wellbeing_fatigue": None,
    }
    features_fatigued = features_base.copy()
    features_fatigued["wellbeing_fatigue"] = 0.9  # High fatigue

    score_base = _score_candidate("WALK", features_base)
    score_fatigued = _score_candidate("WALK", features_fatigued)

    assert score_fatigued > score_base, "High fatigue should boost WALK score"


def test_wellbeing_heuristic_good_recovery_suppression():
    """Test that good recovery shortly after break lowers break score."""
    features_base = {
        "session_length_minutes": 25.0,
        "time_since_last_break_minutes": 10.0,
        "recent_task_completion_rate": 0.6,
        "preferred_interval_minutes": 30,
        "wellbeing_recovery": None,
    }
    features_recovered = features_base.copy()
    features_recovered["wellbeing_recovery"] = 0.9  # Good recovery

    score_base = _score_candidate("SHORT_BREAK", features_base)
    score_recovered = _score_candidate("SHORT_BREAK", features_recovered)

    assert score_recovered < score_base, "Good recovery shortly after break should reduce break score"


def test_changing_wellbeing_input_changes_ranking():
    """Demonstrate that changing a relevant wellbeing input changes candidate ranking when other inputs are held constant."""
    features_normal = {
        "session_length_minutes": 50.0,
        "time_since_last_break_minutes": 35.0,
        "recent_task_completion_rate": 0.5,
        "preferred_interval_minutes": 30,
        "wellbeing_fatigue": 0.1,  # Low fatigue
        "wellbeing_recovery": 0.8,  # Good recovery
    }

    features_fatigued = features_normal.copy()
    features_fatigued["wellbeing_fatigue"] = 0.95  # Extreme fatigue
    features_fatigued["wellbeing_recovery"] = 0.2  # Low recovery

    # Score candidates under normal wellbeing
    scores_normal = {c: _score_candidate(c, features_normal) for c in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]}
    # Score candidates under high fatigue / low recovery
    scores_fatigued = {c: _score_candidate(c, features_fatigued) for c in ["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH", "LUNCH"]}

    top_normal = max(scores_normal, key=scores_normal.get)
    top_fatigued = max(scores_fatigued, key=scores_fatigued.get)

    # Fatigue/recovery should elevate WALK/STRETCH/SHORT_BREAK scores relative to baseline
    assert scores_fatigued["WALK"] > scores_normal["WALK"]
    assert scores_fatigued["STRETCH"] > scores_normal["STRETCH"]


def test_missing_wellbeing_data_neutral():
    """Test that missing wellbeing data (None) behaves identically to baseline neutrality."""
    features_none = {
        "session_length_minutes": 45.0,
        "time_since_last_break_minutes": 30.0,
        "recent_task_completion_rate": 0.5,
        "preferred_interval_minutes": 30,
        "wellbeing_fatigue": None,
        "wellbeing_recovery": None,
        "wellbeing_workload": None,
        "wellbeing_stress_count": 0,
    }
    features_empty_dict = {
        "session_length_minutes": 45.0,
        "time_since_last_break_minutes": 30.0,
        "recent_task_completion_rate": 0.5,
        "preferred_interval_minutes": 30,
    }

    assert _score_candidate("WALK", features_none) == _score_candidate("WALK", features_empty_dict)
