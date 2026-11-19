import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from db_safety import get_database_url, safe_database_error


def test_missing_database_url_raises_safe_error(monkeypatch):
    monkeypatch.delenv("TEST_DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError, match="TEST_DATABASE_URL is required") as exc:
        get_database_url("TEST_DATABASE_URL")
    assert "password" not in str(exc.value).lower()


def test_database_error_does_not_leak_connection_details():
    url = "postgresql://secret-user:secret-password@secret-host/db"
    message = safe_database_error("query failed", RuntimeError(f"failed to connect to {url}"))
    assert message == "query failed (RuntimeError)"
    assert url not in message
    assert "secret-host" not in message


def test_credential_scripts_have_no_embedded_postgresql_password():
    root = Path(__file__).resolve().parents[1]
    targets = [
        root / "compare_databases.py",
        root / "inspect_overlap.py",
        root / "scripts" / "verify_postgres_migration.py",
        root / "scripts" / "verify_actual_alembic_migration.py",
    ]
    for target in targets:
        content = target.read_text(encoding="utf-8")
        assert "postgresql+psycopg://" not in content
        assert "vUb2TQOaqsNfig8JeyEwL6Dd1cnKV9zZ" not in content
