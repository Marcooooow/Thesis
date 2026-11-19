"""
Tests for ML pipeline test data exclusion.

Tests cover:
- Test profiles (is_test_data=true) are excluded from ML training data
- Real profiles (is_test_data=false) are included in ML training data
- Backwards compatibility: email pattern fallback works for profiles without is_test_data
- extract_task_events filters out test data at the source
- classify_data_source prioritizes explicit flag over email pattern
"""

import pytest
from unittest.mock import MagicMock, patch
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from uuid import uuid4
from datetime import datetime, timezone


class MockRow:
    """Mock database row for psycopg2 RealDictCursor results."""
    def __init__(self, **kwargs):
        for key, value in kwargs.items():
            setattr(self, key, value)

    def __getitem__(self, key):
        return getattr(self, key)


class TestMLTestDataExclusion:

    @pytest.fixture
    def mock_conn(self):
        """Create a mock database connection."""
        conn = MagicMock()
        conn.autocommit = True
        return conn

    @pytest.fixture
    def mock_cursor(self):
        """Create a mock cursor that returns dict-like rows."""
        cursor = MagicMock()
        return cursor

    def test_classify_data_source_uses_explicit_flag_true(self, mock_conn):
        """When is_test_data=true, classify_data_source should return TEST."""
        from ml_pipeline_foundation import classify_data_source

        # Mock query result with explicit is_test_data=True
        mock_results = [
            MockRow(profile_id=str(uuid4()), is_test_data=True, email="real@company.com"),
            MockRow(profile_id=str(uuid4()), is_test_data=False, email="test@company.com"),
        ]

        with patch('ml_pipeline_foundation.query_db', return_value=mock_results):
            result = classify_data_source(mock_conn)

            # Verify is_test_data=true is classified as TEST
            for profile_id, data_source in result.items():
                if mock_results[0]['profile_id'] == profile_id:
                    assert data_source == "TEST"
                elif mock_results[1]['profile_id'] == profile_id:
                    assert data_source == "REAL"

    def test_classify_data_source_uses_explicit_flag_false(self, mock_conn):
        """When is_test_data=false, classify_data_source should return REAL."""
        from ml_pipeline_foundation import classify_data_source

        profile_id = str(uuid4())
        mock_results = [
            MockRow(profile_id=profile_id, is_test_data=False, email="demo@company.com"),
        ]

        with patch('ml_pipeline_foundation.query_db', return_value=mock_results):
            result = classify_data_source(mock_conn)

            # Even with "demo" in email, explicit flag=false means REAL
            assert result[profile_id] == "REAL"

    def test_classify_data_source_fallback_to_email_pattern(self, mock_conn):
        """When is_test_data is NULL, fallback to email pattern matching."""
        from ml_pipeline_foundation import classify_data_source

        # Profile with demo in email, is_test_data=NULL (not set)
        profile_id_demo = str(uuid4())
        profile_id_real = str(uuid4())

        mock_results = [
            MockRow(profile_id=profile_id_demo, is_test_data=None, email="demo@company.com"),
            MockRow(profile_id=profile_id_real, is_test_data=None, email="real@company.com"),
        ]

        with patch('ml_pipeline_foundation.query_db', return_value=mock_results):
            result = classify_data_source(mock_conn)

            # Without explicit flag, email pattern should be used as fallback
            assert result[profile_id_demo] == "TEST"  # "demo" in email
            assert result[profile_id_real] == "REAL"

    def test_classify_data_source_explicit_flag_priority(self, mock_conn):
        """Explicit is_test_data flag should override email pattern detection."""
        from ml_pipeline_foundation import classify_data_source

        # Profile with "demo" in email but is_test_data=False (should be REAL)
        profile_id = str(uuid4())
        mock_results = [
            MockRow(profile_id=profile_id, is_test_data=False, email="demo@company.com"),
        ]

        with patch('ml_pipeline_foundation.query_db', return_value=mock_results):
            result = classify_data_source(mock_conn)

            # Explicit flag=false should override "demo" in email
            assert result[profile_id] == "REAL"

    def test_extract_task_events_excludes_test_data(self, mock_conn):
        """extract_task_events should exclude tasks from test profiles."""
        from ml_pipeline_foundation import extract_task_events

        test_profile_id = str(uuid4())
        real_profile_id = str(uuid4())

        # Query should filter by is_test_data
        with patch('ml_pipeline_foundation.query_db') as mock_query:
            mock_query.return_value = []  # Empty result is fine for this test

            extract_task_events(mock_conn)

            # Verify the query includes the is_test_data filter
            called_sql = mock_query.call_args[0][1]
            assert 'is_test_data' in called_sql or 'p.is_test_data' in called_sql

    def test_training_window_data_source_tracking(self):
        """Verify TrainingWindow dataclass tracks data_source correctly."""
        from ml_pipeline_foundation import TrainingWindow
        from datetime import datetime, timezone

        # Create a training window with TEST data source
        window = TrainingWindow(
            profile_id=str(uuid4()),
            observation_time=datetime.now(timezone.utc),
            feature_window_start=datetime.now(timezone.utc),
            feature_window_end=datetime.now(timezone.utc),
            gap_start=datetime.now(timezone.utc),
            gap_end=datetime.now(timezone.utc),
            target_window_start=datetime.now(timezone.utc),
            target_window_end=datetime.now(timezone.utc),
            feature_task_count=5,
            feature_task_completion_rate=15.0,
            feature_time_since_last_break_minutes=30.0,
            feature_continuous_work_minutes=60.0,
            feature_recent_break_count=2,
            feature_hour_of_day=10,
            target_task_count=3,
            target_task_completion_rate=9.0,
            personal_baseline_rate=12.0,
            target_is_decline=False,
            data_source="TEST"  # Should be excluded from training
        )

        assert window.data_source == "TEST"

        # Create one with REAL data source
        window_real = TrainingWindow(
            profile_id=str(uuid4()),
            observation_time=datetime.now(timezone.utc),
            feature_window_start=datetime.now(timezone.utc),
            feature_window_end=datetime.now(timezone.utc),
            gap_start=datetime.now(timezone.utc),
            gap_end=datetime.now(timezone.utc),
            target_window_start=datetime.now(timezone.utc),
            target_window_end=datetime.now(timezone.utc),
            feature_task_count=5,
            feature_task_completion_rate=15.0,
            feature_time_since_last_break_minutes=30.0,
            feature_continuous_work_minutes=60.0,
            feature_recent_break_count=2,
            feature_hour_of_day=10,
            target_task_count=3,
            target_task_completion_rate=9.0,
            personal_baseline_rate=12.0,
            target_is_decline=False,
            data_source="REAL"
        )

        assert window_real.data_source == "REAL"

    def test_validate_dataset_separates_real_and_test(self):
        """validate_dataset should correctly separate real and test data."""
        from ml_pipeline_foundation import validate_dataset, TrainingWindow, DatasetSummary
        from datetime import datetime, timezone

        mock_conn = MagicMock()

        # Create sample windows with different data sources
        windows = []

        # Add 5 REAL windows
        for i in range(5):
            window = TrainingWindow(
                profile_id=str(uuid4()),
                observation_time=datetime.now(timezone.utc),
                feature_window_start=datetime.now(timezone.utc),
                feature_window_end=datetime.now(timezone.utc),
                gap_start=datetime.now(timezone.utc),
                gap_end=datetime.now(timezone.utc),
                target_window_start=datetime.now(timezone.utc),
                target_window_end=datetime.now(timezone.utc),
                feature_task_count=5,
                feature_task_completion_rate=15.0,
                feature_time_since_last_break_minutes=30.0,
                feature_continuous_work_minutes=60.0,
                feature_recent_break_count=2,
                feature_hour_of_day=10,
                target_task_count=3,
                target_task_completion_rate=9.0,
                personal_baseline_rate=12.0,
                target_is_decline=False,
                data_source="REAL"
            )
            windows.append(window)

        # Add 3 TEST windows
        for i in range(3):
            window = TrainingWindow(
                profile_id=str(uuid4()),
                observation_time=datetime.now(timezone.utc),
                feature_window_start=datetime.now(timezone.utc),
                feature_window_end=datetime.now(timezone.utc),
                gap_start=datetime.now(timezone.utc),
                gap_end=datetime.now(timezone.utc),
                target_window_start=datetime.now(timezone.utc),
                target_window_end=datetime.now(timezone.utc),
                feature_task_count=5,
                feature_task_completion_rate=15.0,
                feature_time_since_last_break_minutes=30.0,
                feature_continuous_work_minutes=60.0,
                feature_recent_break_count=2,
                feature_hour_of_day=10,
                target_task_count=3,
                target_task_completion_rate=9.0,
                personal_baseline_rate=12.0,
                target_is_decline=False,
                data_source="TEST"
            )
            windows.append(window)

        # Mock query_db to return counts for validate_dataset's database queries
        with patch('ml_pipeline_foundation.query_db') as mock_query:
            # Return counts for: users, sessions, tasks, completed_tasks
            mock_query.side_effect = [
                [{'n': 10}],   # total_users
                [{'n': 20}],   # total_sessions
                [{'n': 100}],  # total_tasks
                [{'n': 80}],   # completed_tasks
            ]

            summary = validate_dataset(mock_conn, windows)

            # Verify counts are correct
            assert summary.real_data_count == 5
            assert summary.test_data_count == 3
            assert summary.valid_training_windows == 5

    def test_insufficient_data_handling(self):
        """Test that the ML pipeline correctly reports insufficient data."""
        from ml_pipeline_foundation import run_ml_pipeline

        # Mock the database to return no events
        with patch('ml_pipeline_foundation.extract_task_events', return_value=[]), \
             patch('ml_pipeline_foundation.classify_data_source', return_value={}), \
             patch('ml_pipeline_foundation.get_db_connection') as mock_get_conn, \
             patch('ml_pipeline_foundation.query_db') as mock_query:

            mock_conn = MagicMock()
            mock_get_conn.return_value = mock_conn

            # Mock the database queries for basic counts in validate_dataset
            mock_query.side_effect = [
                [{'n': 0}],   # total_users
                [{'n': 0}],   # total_sessions
                [{'n': 0}],   # total_tasks
                [{'n': 0}],   # completed_tasks
            ]

            summary = run_ml_pipeline()

            assert summary.training_permitted == False
            assert "Insufficient real training examples" in summary.rejection_reason
            assert summary.real_data_count == 0
            assert summary.valid_training_windows == 0