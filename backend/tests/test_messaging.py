from fastapi.testclient import TestClient
import pytest
import uuid as uuid_mod
from app.database import Base, get_db
from app.auth.security import create_access_token, get_current_user
from app.main import app
import json

client = TestClient(app)

def _token(email: str = "alice@example.com") -> str:
    # Construct a minimal valid JWT for testing (no real secret match assumed; we rely on dependency catching missing user)
    payload = {"sub": email, "type": "access"}
    return create_access_token(data=payload, expires_delta=None)

def _make_engine():
    from sqlalchemy import create_engine, Column, String, Text, DateTime, ForeignKey, Boolean, UniqueConstraint, Index
    from sqlalchemy.orm import declarative_base, sessionmaker
    Base = declarative_base()
    class T(Base):
        __tablename__ = "t"
        id = Column(String(36), primary_key=True)
    eng = create_engine("sqlite://")
    Base.metadata.create_all(eng)
    sm = sessionmaker(bind=eng)
    return eng, sm

def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "healthy"

def test_messages_endpoint_requires_auth():
    r = client.get("/messages")
    assert r.status_code in [401, 403, 422]
