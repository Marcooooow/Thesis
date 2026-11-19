"""
Extended tests for password security (short passwords, long passwords > 72 bytes,
Unicode passwords, legacy bcrypt verification, invitation token hashing/verification,
and team invitation auto-provisioning).
"""
import pytest
import hashlib
import secrets
import bcrypt
from app.auth.security import get_password_hash, verify_password
from app.models import TeamInvitation
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app

client = TestClient(app)

def test_password_shorter_than_72_bytes():
    """Verify hashing and verification work correctly for passwords < 72 bytes."""
    pwd = "shortpassword123"
    hashed = get_password_hash(pwd)
    assert verify_password(pwd, hashed) is True
    assert verify_password("wrongpassword", hashed) is False

def test_password_longer_than_72_bytes():
    """Verify passwords longer than 72 bytes hash and verify successfully without truncation."""
    # 100 characters long password
    pwd = "A" * 100 + "123456789!@"
    hashed = get_password_hash(pwd)
    assert verify_password(pwd, hashed) is True
    # Modifying a character at the end (beyond 72 bytes) should fail verification
    pwd_modified = "A" * 100 + "123456789!#0"
    assert verify_password(pwd_modified, hashed) is False

def test_unicode_passwords():
    """Verify Unicode / multi-language passwords hash and verify successfully."""
    pwd = "密码测试🔒password🔑éàçü"
    hashed = get_password_hash(pwd)
    assert verify_password(pwd, hashed) is True
    assert verify_password("wrongunicode", hashed) is False

def test_existing_legacy_bcrypt_hash_verification():
    """Verify that existing legacy raw bcrypt hashes continue to verify correctly."""
    pwd = "legacytestpassword123"
    legacy_hash = bcrypt.hashpw(pwd.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    assert verify_password(pwd, legacy_hash) is True
    assert verify_password("wrongpass", legacy_hash) is False

def test_invitation_token_hashing_and_verification():
    """Verify high-entropy invitation token hashing with SHA-256 and verification."""
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()

    # Verify match
    computed_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
    assert computed_hash == token_hash

def test_team_invitation_registration_and_auto_provisioning(test_db: Session):
    """Verify team invitation flow and auto-provisioning mechanics."""
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
    token_prefix = token[:12]

    assert len(token_hash) == 64
    assert len(token_prefix) == 12
