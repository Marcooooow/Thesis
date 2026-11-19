"""
Tests for JWT secret key startup validation.
Covers:
1. Missing SECRET_KEY raises RuntimeError
2. Empty SECRET_KEY raises RuntimeError
3. Insecure placeholder values rejected in production
4. Insecure placeholder values warned but allowed in development
5. Short secrets rejected in production
6. Low entropy secrets rejected in production
7. Strong secrets accepted in production
8. Current development secret accepted in development
"""

import os
import pytest
import warnings


def _reset_secret_key_env():
    """Helper to reset SECRET_KEY for each test."""
    if 'SECRET_KEY' in os.environ:
        del os.environ['SECRET_KEY']
    if 'RENDER' in os.environ:
        del os.environ['RENDER']
    if 'ENVIRONMENT' in os.environ:
        del os.environ['ENVIRONMENT']
    if 'DATABASE_URL' in os.environ:
        del os.environ['DATABASE_URL']


@pytest.fixture(autouse=True)
def clean_env():
    """Ensure clean environment for each test."""
    _reset_secret_key_env()
    yield
    _reset_secret_key_env()


def _import_validate():
    """Import validation function with fresh module state."""
    # Need to reload main and security modules to pick up new env vars
    import importlib
    import sys
    # Remove cached modules
    for mod_name in list(sys.modules.keys()):
        if mod_name.startswith('app.'):
            del sys.modules[mod_name]
    import app.main
    return app.main._validate_secret_key


def test_missing_secret_key_production():
    """Missing SECRET_KEY in production raises RuntimeError."""
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="SECRET_KEY environment variable is required but not set"):
        validate()


def test_empty_secret_key_production():
    """Empty SECRET_KEY in production raises RuntimeError."""
    os.environ['SECRET_KEY'] = ''
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="SECRET_KEY environment variable is required but not set"):
        validate()


def test_placeholder_secret_key_production():
    """Placeholder SECRET_KEY in production raises RuntimeError."""
    os.environ['SECRET_KEY'] = 'default'
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="insecure placeholder value"):
        validate()


def test_placeholder_secret_key_development_warns():
    """Placeholder SECRET_KEY in development warns but allows."""
    os.environ['SECRET_KEY'] = 'default'
    os.environ['RENDER'] = 'false'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        validate()
        assert len(w) == 1
        assert issubclass(w[0].category, RuntimeWarning)
        assert "insecure placeholder" in str(w[0].message)


def test_short_secret_production():
    """Short SECRET_KEY in production raises RuntimeError."""
    os.environ['SECRET_KEY'] = 'short123'
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="at least 32 characters"):
        validate()


def test_low_entropy_secret_production():
    """Low entropy SECRET_KEY in production raises RuntimeError."""
    os.environ['SECRET_KEY'] = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'  # 32 chars but all same
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="insufficient entropy"):
        validate()


def test_strong_secret_production():
    """Strong SECRET_KEY in production accepted."""
    os.environ['SECRET_KEY'] = 'a-very-strong-secret-key-with-sufficient-entropy-for-production'
    os.environ['RENDER'] = 'true'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    # Should not raise
    validate()


def test_current_dev_secret_development():
    """Current development secret accepted in development."""
    os.environ['SECRET_KEY'] = 'tRGtNYAVHGN0gyXbbtdwU4MVIFYSoSXzudYQNTqwPDs'
    os.environ['RENDER'] = 'false'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    # Should not raise
    validate()


def test_environment_variable_production():
    """ENVIRONMENT=production triggers production validation."""
    os.environ['SECRET_KEY'] = 'default'
    os.environ['ENVIRONMENT'] = 'production'
    os.environ['DATABASE_URL'] = 'sqlite:///./test.db'
    validate = _import_validate()

    with pytest.raises(RuntimeError, match="insecure placeholder value"):
        validate()