"""Focused restricted first-login authentication tests."""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app
from app.database import get_db
from app.auth.security import verify_password
from app.models import User, Profile
from app.auth.security import get_password_hash


@pytest.fixture
def restricted_client(test_db: Session):
    return TestClient(app)


def get_token(client: TestClient, email: str, password: str):
    resp = client.post("/auth/login", json={"email": email, "password": password})
    return resp.json()["access_token"]


def test_restricted_token_type_and_version(test_client, test_db: Session):
    """Restricted login returns token with type=restricted and version claim."""
    from uuid import uuid4
    email = f"prov_{uuid4().hex[:8]}@test.com"
    user = User(
        email=email, full_name="Prov User",
        password_hash=get_password_hash("TempPass123!"),
        role="EMPLOYEE", approval_status="APPROVED",
        is_active=True, account_type="solo",
        must_change_password=True, password_change_token_version=0,
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.commit()
    # Login with temp password
    resp = test_client.post("/auth/login", json={"email": email, "password": "TempPass123!"})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("message") == "Password change required"
    token = data["access_token"]
    # Decode payload (without verification for type inspection only)
    from jose import jwt
    from app.auth.security import SECRET_KEY, ALGORITHM
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    assert payload.get("type") == "restricted"
    assert payload.get("version") == 0


def test_restricted_token_rejected_by_normal_me(test_client, test_db: Session):
    """Normal /auth/me must reject restricted token."""
    from uuid import uuid4
    email = f"restricted_{uuid4().hex[:8]}@test.com"
    user = User(
        email=email, full_name="Restricted User",
        password_hash=get_password_hash("TempPass123!"),
        role="EMPLOYEE", approval_status="APPROVED",
        is_active=True, must_change_password=True,
        password_change_token_version=1,
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.commit()
    token_resp = test_client.post("/auth/login", json={"email": email, "password": "TempPass123!"})
    token = token_resp.json()["access_token"]
    # Normal me
    resp = test_client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code in [401, 403]


def test_restricted_me_allows_access(test_client, test_db: Session):
    """Restricted /auth/restricted/me allows access."""
    from uuid import uuid4
    email = f"restr_me_{uuid4().hex[:8]}@test.com"
    user = User(
        email=email, full_name="Restr Me",
        password_hash=get_password_hash("TempPass123!"),
        role="EMPLOYEE", approval_status="APPROVED",
        is_active=True, must_change_password=True, password_change_token_version=2,
    )
    test_db.add(user)
    test_db.flush()
    profile = Profile(user_id=user.id)
    test_db.add(profile)
    test_db.commit()
    token_resp = test_client.post("/auth/login", json={"email": email, "password": "TempPass123!"})
    token = token_resp.json()["access_token"]
    resp = test_client.get("/auth/restricted/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert resp.json()["email"] == email