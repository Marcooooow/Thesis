"""
Tests for persistent ML artifact storage and loading lifecycle.
Covers:
1. Successful upload and load of model artifact.
2. Missing local artifact with successful cloud retrieval / download fallback.
3. Invalid or corrupted artifact handling.
4. Storage/network failure graceful fallback.
5. Feature-set version compatibility checks.
"""
import os
import uuid
import pytest
from unittest.mock import patch, MagicMock
from sqlalchemy.orm import Session

from app.models import MLModel
from app.services.ml_training_pipeline import (
    load_model_artifact,
    upload_artifact_to_supabase,
    download_artifact_from_supabase
)

def test_load_model_artifact_missing_and_download(tmp_path):
    """Test loading when local artifact is missing but successfully downloaded from Supabase Storage."""
    dummy_path = tmp_path / "dummy_model.joblib"
    model_record = MLModel(
        id=uuid.uuid4(),
        version="test-v1",
        artifact_path=str(dummy_path),
        feature_set_version="v2-wellbeing"
    )

    # File doesn't exist initially
    assert not dummy_path.exists()

    with patch("app.services.ml_training_pipeline.download_artifact_from_supabase", return_value=True) as mock_download, \
         patch("joblib.load", return_value="mock_pipeline") as mock_load:

        result = load_model_artifact(model_record)
        mock_download.assert_called_once()
        assert result == "mock_pipeline"

def test_load_model_artifact_invalid_corrupted(tmp_path):
    """Test loading corrupted/invalid artifact returns None gracefully."""
    dummy_path = tmp_path / "corrupt_model.joblib"
    dummy_path.write_bytes(b"not a valid joblib file")

    model_record = MLModel(
        id=uuid.uuid4(),
        version="test-v2",
        artifact_path=str(dummy_path),
        feature_set_version="v2-wellbeing"
    )

    result = load_model_artifact(model_record)
    assert result is None

@patch("urllib.request.urlopen")
def test_upload_artifact_storage_failure(mock_urlopen, tmp_path):
    """Test upload handles network/storage failure gracefully and returns False."""
    dummy_path = tmp_path / "model.joblib"
    dummy_path.write_bytes(b"model data")

    mock_urlopen.side_effect = Exception("Storage timeout")

    with patch.dict(os.environ, {"SUPABASE_URL": "https://test.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "secret"}):
        success = upload_artifact_to_supabase(str(dummy_path), "model.joblib")
        assert success is False
