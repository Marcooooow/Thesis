"""Tests for user settings API endpoints."""

import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database import get_db
from app.models import User, UserSettings, Profile
from app.auth.security import get_password_hash
from sqlalchemy.orm import Session
import uuid
from datetime import datetime, timezone


@pytest.fixture
def authenticated_user(db: Session):
    """Create an authenticated test user."""
    user_id = uuid.uuid4()
    user = User(
        id=user_id,
        email="test@example.com",
        password_hash=get_password_hash("password123"),
        full_name="Test User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    db.add(user)

    # Create associated profile
    profile = Profile(
        id=uuid.uuid4(),
        user_id=user_id,
        is_test_data=True,
    )
    db.add(profile)
    db.commit()

    return user


@pytest.fixture
def client(db: Session):
    """Create test client with database session."""
    def override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)


class TestGetSettings:
    """Tests for GET /settings endpoint."""

    def test_get_settings_creates_defaults_when_missing(self, client: TestClient, authenticated_user: User, db: Session):
        """GET /settings creates default settings when none exist for authenticated user."""
        # Login and get token
        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        assert response.status_code == 200
        token = response.json()["access_token"]

        # Get settings for user with no existing settings
        response = client.get(
            "/settings",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        data = response.json()

        # Verify defaults are created
        assert data["notifications_enabled"] is True
        assert data["break_reminders"] is True
        assert data["break_interval_minutes"] == 30
        assert data["break_duration_minutes"] == 10
        assert data["break_coach_enabled"] is True
        assert data["break_coach_cooldown_minutes"] == 30
        assert data["reduce_motion"] is False
        assert "created_at" in data
        assert "updated_at" in data

        # Verify settings were actually persisted
        settings_in_db = db.query(UserSettings).filter(UserSettings.user_id == authenticated_user.id).first()
        assert settings_in_db is not None
        assert settings_in_db.notifications_enabled is True

    def test_get_settings_existing(self, client: TestClient, authenticated_user: User, db: Session):
        """Get existing settings should return all fields."""
        # Create settings
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        # Login
        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Get settings
        response = client.get(
            "/settings",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        data = response.json()

        # Verify defaults
        assert data["notifications_enabled"] is True
        assert data["break_reminders"] is True
        assert data["break_interval_minutes"] == 30
        assert data["break_duration_minutes"] == 10
        assert data["break_coach_enabled"] is True
        assert data["break_coach_cooldown_minutes"] == 30
        assert data["reduce_motion"] is False
        assert "created_at" in data
        assert "updated_at" in data

    def test_get_settings_unauthenticated(self, client: TestClient):
        """Unauthenticated request should return 401."""
        response = client.get("/settings")
        assert response.status_code == 401


class TestCreateSettings:
    """Tests for POST /settings endpoint."""

    def test_create_settings_new_user(self, client: TestClient, authenticated_user: User, db: Session):
        """Creating settings for new user should work."""
        # Login
        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Create settings
        response = client.post(
            "/settings",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 201
        data = response.json()

        # Verify defaults
        assert data["notifications_enabled"] is True
        assert data["break_interval_minutes"] == 30

    def test_create_settings_idempotent(self, client: TestClient, authenticated_user: User, db: Session):
        """Creating settings twice should return existing settings."""
        # Create settings first time
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        # Login
        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Try to create again
        response = client.post(
            "/settings",
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 201  # Still 201 for idempotent POST
        data = response.json()
        assert data["notifications_enabled"] is True


class TestUpdateSettings:
    """Tests for PATCH /settings endpoint."""

    def test_update_single_field(self, client: TestClient, authenticated_user: User, db: Session):
        """Update single notification setting."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Update break_reminders to false
        response = client.patch(
            "/settings",
            json={"break_reminders": False},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["break_reminders"] is False
        # Other fields unchanged
        assert data["notifications_enabled"] is True

    def test_update_break_interval_valid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update break interval to valid value."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Update to valid value
        response = client.patch(
            "/settings",
            json={"break_interval_minutes": 60},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        assert response.json()["break_interval_minutes"] == 60

    def test_update_break_interval_invalid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update break interval to invalid value should fail."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Update to invalid value
        response = client.patch(
            "/settings",
            json={"break_interval_minutes": 999},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 422  # Validation error

    def test_update_timezone(self, client: TestClient, authenticated_user: User, db: Session):
        """Update timezone setting."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Update timezone
        response = client.patch(
            "/settings",
            json={"timezone": "Asia/Manila"},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        assert response.json()["timezone"] == "Asia/Manila"

    def test_update_multiple_fields(self, client: TestClient, authenticated_user: User, db: Session):
        """Update multiple fields in one request."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Update multiple fields
        response = client.patch(
            "/settings",
            json={
                "break_reminders": False,
                "break_interval_minutes": 45,
                "timezone": "America/New_York",
                "reduce_motion": True,
            },
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["break_reminders"] is False
        assert data["break_interval_minutes"] == 45
        assert data["timezone"] == "America/New_York"
        assert data["reduce_motion"] is True
        # Other fields unchanged
        assert data["notifications_enabled"] is True

    def test_update_settings_auto_create(self, client: TestClient, authenticated_user: User, db: Session):
        """Updating non-existent settings auto-creates them."""
        db.query(UserSettings).filter(UserSettings.user_id == authenticated_user.id).delete()
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Try to update non-existent settings
        response = client.patch(
            "/settings",
            json={"break_reminders": False},
            headers={"Authorization": f"Bearer {token}"}
        )
        assert response.status_code == 200
        assert response.json()["break_reminders"] is False

    def test_update_focus_percentage_valid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update focus target percentage with valid values."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        for pct in [0, 50, 100]:
            response = client.patch(
                "/settings",
                json={"focus_target_percentage": pct},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert response.status_code == 200
            assert response.json()["focus_target_percentage"] == pct

    def test_update_focus_percentage_invalid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update focus target percentage with invalid values should fail."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Test invalid values
        for pct in [-1, 101, 1000]:
            response = client.patch(
                "/settings",
                json={"focus_target_percentage": pct},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert response.status_code == 422  # Validation error

    def test_update_daily_hours_range(self, client: TestClient, authenticated_user: User, db: Session):
        """Update daily target hours with valid range."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        # Valid values
        for hours in [1, 8, 24]:
            response = client.patch(
                "/settings",
                json={"work_target_daily_hours": hours},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert response.status_code == 200
            assert response.json()["work_target_daily_hours"] == hours

    def test_update_time_format_valid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update time format with valid values."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        for fmt in ["12h", "24h"]:
            response = client.patch(
                "/settings",
                json={"time_format": fmt},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert response.status_code == 200
            assert response.json()["time_format"] == fmt

    def test_update_interface_density_valid(self, client: TestClient, authenticated_user: User, db: Session):
        """Update interface density with valid values."""
        settings = UserSettings(user_id=authenticated_user.id)
        db.add(settings)
        db.commit()

        response = client.post("/auth/login", json={
            "email": authenticated_user.email,
            "password": "password123"
        })
        token = response.json()["access_token"]

        for density in ["COMPACT", "COMFORTABLE", "SPACIOUS"]:
            response = client.patch(
                "/settings",
                json={"interface_density": density},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert response.status_code == 200
            assert response.json()["interface_density"] == density


class TestSecurityAndOwnership:
    """Tests for security and authorization."""

    def test_user_gets_own_settings_not_others(self, client: TestClient, db: Session):
        """Authenticated user gets their own settings, not another user's settings."""
        # Create two users
        user_a_id = uuid.uuid4()
        user_a = User(
            id=user_a_id,
            email="user_a@example.com",
            password_hash=get_password_hash("password123"),
            full_name="User A",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True,
        )
        profile_a = Profile(id=uuid.uuid4(), user_id=user_a_id, is_test_data=True)
        db.add(user_a)
        db.add(profile_a)

        user_b_id = uuid.uuid4()
        user_b = User(
            id=user_b_id,
            email="user_b@example.com",
            password_hash=get_password_hash("password123"),
            full_name="User B",
            role="EMPLOYEE",
            approval_status="APPROVED",
            is_active=True,
        )
        profile_b = Profile(id=uuid.uuid4(), user_id=user_b_id, is_test_data=True)
        db.add(user_b)
        db.add(profile_b)

        # Create settings ONLY for User B (with custom values to distinguish)
        settings_b = UserSettings(
            user_id=user_b_id,
            break_reminders=False,  # Different from default
            break_interval_minutes=60  # Different from default
        )
        db.add(settings_b)
        db.commit()

        # Login as User A (who has NO settings initially)
        response = client.post("/auth/login", json={
            "email": "user_a@example.com",
            "password": "password123"
        })
        assert response.status_code == 200
        token_a = response.json()["access_token"]

        # User A accesses /settings - should get THEIR OWN newly created settings (defaults)
        response = client.get(
            "/settings",
            headers={"Authorization": f"Bearer {token_a}"}
        )
        assert response.status_code == 200
        data = response.json()

        # User A should get THEIR OWN settings (defaults), not User B's settings
        assert data["break_reminders"] is True  # Default value
        assert data["break_interval_minutes"] == 30  # Default value
        # Verify these are NOT User B's settings
        assert data["break_reminders"] != False  # User B's value
        assert data["break_interval_minutes"] != 60  # User B's value

        # Verify User A's settings were created in DB
        settings_a_in_db = db.query(UserSettings).filter(UserSettings.user_id == user_a_id).first()
        assert settings_a_in_db is not None
        assert settings_a_in_db.break_reminders is True
        assert settings_a_in_db.break_interval_minutes == 30

        # Verify User B's settings are unchanged
        settings_b_in_db = db.query(UserSettings).filter(UserSettings.user_id == user_b_id).first()
        assert settings_b_in_db is not None
        assert settings_b_in_db.break_reminders is False
        assert settings_b_in_db.break_interval_minutes == 60
