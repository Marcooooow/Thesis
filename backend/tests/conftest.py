"""
Pytest configuration and fixtures for backend tests.
"""
import pytest
from sqlalchemy import create_engine, String, Text, event, StaticPool, JSON, Time
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID as PG_UUID
from sqlalchemy.sql.sqltypes import DateTime as SADateTime
from sqlalchemy.types import TypeDecorator
from fastapi.testclient import TestClient
from app.database import Base, get_db
from app.main import app
from app.models import User, Profile, Team, TeamMembership, WorkSession, Break, Task, \
    Recommendation, RecommendationFeedback, SystemActivityLog, TeamInvitation, Notification, Group, Organization, OrganizationMembership, UserSettings, \
    EmployeeSchedule, LeaveType, LeaveRequest, AbsenceRecord, ReturnToWorkCheckin, ManagerAlertReview, SessionWellbeingCheckin, MonitoringThresholds, MLTrainingJob, MLModel
from app.models_presence import UserPresence

from app.auth.security import get_password_hash
from httpx import AsyncClient
import uuid
from datetime import timezone
import os


def _fix_sqlite_incompatibility():
    """Fix SQLite incompatibility for PostgreSQL-specific types."""
    if "sqlite" in DATABASE_URL:
        # Patch the table definitions to replace ARRAY and JSONB with SQLite compatible types
        print("DIAG: Tables before fix:", sorted(Base.metadata.tables.keys()))
        from sqlalchemy import UUID  # Import UUID here to avoid scope issues
        for table in Base.metadata.tables.values():
            # Remove PostgreSQL-specific partial unique indexes that SQLite treats as global unique constraints
            indexes_to_remove = [idx for idx in table.indexes if idx.name in ('ix_breaks_active', 'ix_work_sessions_active', 'ix_team_membership_current')]
            for idx in indexes_to_remove:
                table.indexes.remove(idx)
                print(f"DIAG: Removed PostgreSQL-specific partial unique index {idx.name} for SQLite compatibility")

            for column in table.columns:
                if isinstance(column.type, JSONB):
                    column.type = JSON()
                elif isinstance(column.type, UUID):
                    # Ensure it's set up for SQLite with as_uuid=True
                    if not column.type.as_uuid:
                        column.type = UUID(as_uuid=True)
                        print(f"DIAG: Fixed {table.name}.{column.name}: {column.type} -> UUID(as_uuid=True)")
                elif "postgresql" in str(column.type) and "UUID" in str(column.type) or 'postgresql' in column.type.__class__.__module__ and 'UUID' in type(column.type).__name__:
                    # Replace PostgreSQL-specific UUID with SQLAlchemy's UUID for SQLite
                    old_type = column.type
                    column.type = UUID(as_uuid=True)
                    print(f"DIAG: Fixed PostgreSQL UUID {table.name}.{column.name}: {old_type} -> {column.type}")
                # Remove server_default for id column in SQLite because we are using an event listener
                if column.name == "id" and column.server_default is not None:
                    column.server_default = None
                # Fix SQLite's handling of timezone-aware DateTime columns
                # SQLite ignores timezone=True and returns naive datetimes, but our app expects timezone-aware
                elif isinstance(column.type, SADateTime) and getattr(column.type, 'timezone', False):
                    # Replace the column type to ensure timezone-aware datetimes are preserved
                    # We create a simple wrapper that processes result values to attach timezone

                    class DateTimeWithTimezone(TypeDecorator):
                        """Ensures DateTime values from SQLite are timezone-aware."""
                        impl = SADateTime(timezone=True)
                        cache_ok = True

                        def process_result_value(self, value, dialect):
                            # When loading from SQLite, attach UTC timezone if naive
                            if value is not None and value.tzinfo is None:
                                return value.replace(tzinfo=timezone.utc)
                            return value

                    # Replace the column type with our timezone-aware wrapper
                    old_type = column.type
                    column.type = DateTimeWithTimezone()
                    print(f"DIAG: Fixed {table.name}.{column.name}: {old_type} -> DateTimeWithTimezone")
        print("DIAG: Tables after fix:", sorted(Base.metadata.tables.keys()))
        # Debug: print columns of recommendation_feedback
        if 'recommendation_feedback' in Base.metadata.tables:
            cols = [c.name for c in Base.metadata.tables['recommendation_feedback'].columns]
            print(f"DIAG: recommendation_feedback columns: {cols}")


# Use in-memory SQLite for testing with StaticPool to ensure all connections see the same database
# Override with POSTGRES_TEST_DATABASE_URL environment variable for PostgreSQL testing
DATABASE_URL = os.getenv("POSTGRES_TEST_DATABASE_URL", "sqlite:///:memory:")

# Apply the fix before tests run
_fix_sqlite_incompatibility()


@pytest.fixture(scope="function", autouse=True)
def test_db() -> Session:
    """Create a fresh database for each test."""
    is_postgres = "postgresql" in DATABASE_URL
    connect_args = {"check_same_thread": False} if not is_postgres else {}
    poolclass = StaticPool if not is_postgres else None

    engine = create_engine(DATABASE_URL, connect_args=connect_args, poolclass=poolclass)

    print(f"DEBUG: Engine id: {id(engine)}")
    print(f"DEBUG: Engine pool class: {engine.pool.__class__.__name__ if poolclass else 'Default'}")
    print(f"DEBUG: Engine URL: {engine.url}")
    print(f"DEBUG: Tables to create: {Base.metadata.tables.keys()}")
    # DIAG: Check if 'users' table is in metadata before create_all
    print("DIAG: 'users' in Base.metadata.tables before create_all:", 'users' in Base.metadata.tables)

    # Listeners for UUID v4 generation in SQLite
    def receive_before_insert(mapper, connection, target):
        if hasattr(target, 'id') and target.id is None:
            target.id = uuid.uuid4()

    for model in [User, Profile, Team, TeamMembership, WorkSession, Break, Task,
                  Recommendation, RecommendationFeedback, SystemActivityLog, TeamInvitation, Notification, Group, Organization, OrganizationMembership, UserSettings, UserPresence,
                  EmployeeSchedule, LeaveType, LeaveRequest, AbsenceRecord, ReturnToWorkCheckin, ManagerAlertReview, SessionWellbeingCheckin, MonitoringThresholds, MLTrainingJob, MLModel]:
        event.listen(model, 'before_insert', receive_before_insert)

    try:
        Base.metadata.create_all(bind=engine)
    except Exception as e:
        raise

    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    from app import database as app_database
    original_session_local = app_database.SessionLocal
    app_database.SessionLocal = TestingSessionLocal

    db = TestingSessionLocal()

    # Override the get_db dependency
    def override_get_db():
        yield db

    app.dependency_overrides[get_db] = override_get_db

    try:
        yield db
    finally:
        # Cleanup
        app_database.SessionLocal = original_session_local
        db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()

        # Remove listeners
        for model in [User, Profile, Team, TeamMembership, WorkSession, Break, Task,
                      Recommendation, RecommendationFeedback, SystemActivityLog, TeamInvitation, Notification, Group, Organization, OrganizationMembership, UserSettings, UserPresence,
                      EmployeeSchedule, LeaveType, LeaveRequest, AbsenceRecord, ReturnToWorkCheckin]:
            event.remove(model, 'before_insert', receive_before_insert)


@pytest.fixture
def test_user(test_db: Session) -> User:
    """Create a test user in the database with a profile."""
    user = User(
        email="testuser@example.com",
        password_hash=get_password_hash("testpassword123"),
        full_name="Test User",
        account_type="solo",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(user)
    test_db.commit()
    test_db.refresh(user)

    # Create a profile for the user
    profile = Profile(
        user_id=user.id,
    )
    test_db.add(profile)
    test_db.commit()
    test_db.refresh(profile)

    return user


@pytest.fixture
def db(test_db: Session):
    """Alias for test_db for backward compatibility."""
    return test_db


@pytest.fixture
def test_client(test_db: Session):
    """Create a synchronous test client."""
    print(f"DEBUG: test_client fixture called. app.dependency_overrides keys: {list(app.dependency_overrides.keys())}")
    return TestClient(app)


@pytest.fixture
async def client(test_db: Session):
    """Create an async test client for @pytest.mark.asyncio tests."""
    print(f"DEBUG: client (async) fixture called. app.dependency_overrides keys: {list(app.dependency_overrides.keys())}")
    # Clear rate-limit state before test
    from app.routers import auth
    auth._login_failures.clear()
    async with AsyncClient(app=app, base_url="http://test") as async_client:
        yield async_client
    # Clear rate-limit state after test
    auth._login_failures.clear()


def get_test_db():
    """Helper to get test database - for backward compatibility."""
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    return TestingSessionLocal()