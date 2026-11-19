"""
Benchmark script for compute_team_analytics query count and execution time.
"""
import time
import uuid
from datetime import date, datetime, timezone, timedelta
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, Session
from app.database import Base
from app.models import User, Profile, Organization, OrganizationMembership, WorkSession, Break, Task, RecommendationFeedback, Team
from app.services.team_analytics_service import compute_team_analytics
from app.auth.security import get_password_hash
from tests.conftest import _fix_sqlite_incompatibility

def run_benchmark():
    _fix_sqlite_incompatibility()
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    org = Organization(id=uuid.uuid4(), name="Benchmark Org")
    db.add(org)
    db.flush()

    manager = User(
        id=uuid.uuid4(),
        email="manager@benchmark.local",
        password_hash=get_password_hash("password"),
        full_name="Manager User",
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True
    )
    db.add(manager)
    db.flush()

    org_mem = OrganizationMembership(id=uuid.uuid4(), organization_id=org.id, user_id=manager.id, status="APPROVED")
    db.add(org_mem)
    db.commit()

    # Test across 10, 50, 100 sessions
    for session_count in [10, 50, 100, 500]:
        # Reset database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        db.rollback()

        org = Organization(id=uuid.uuid4(), name="Benchmark Org")
        db.add(org)
        db.flush()

        manager = User(
            id=uuid.uuid4(),
            email="manager@benchmark.local",
            password_hash=get_password_hash("password"),
            full_name="Manager User",
            role="MANAGER",
            approval_status="APPROVED",
            is_active=True
        )
        db.add(manager)
        db.flush()

        org_mem = OrganizationMembership(id=uuid.uuid4(), organization_id=org.id, user_id=manager.id, status="APPROVED")
        db.add(org_mem)

        profile = Profile(
            id=uuid.uuid4(),
            user_id=manager.id,
            job_role="Manager",
            industry="Tech",
            is_test_data=False
        )
        db.add(profile)
        db.flush()

        # Create sessions and breaks
        breaks_per_session = 2
        for j in range(session_count):
            ws = WorkSession(
                profile_id=profile.id,
                started_at=datetime.now(timezone.utc) - timedelta(hours=session_count - j),
                ended_at=datetime.now(timezone.utc) - timedelta(hours=session_count - j) + timedelta(minutes=30)
            )
            db.add(ws)
            db.flush()

            for k in range(breaks_per_session):
                br = Break(
                    work_session_id=ws.id,
                    break_type="SHORT_BREAK",
                    started_at=ws.started_at + timedelta(minutes=5 * (k+1)),
                    ended_at=ws.started_at + timedelta(minutes=5 * (k+1), seconds=60)
                )
                db.add(br)
        db.commit()

        # Track SELECT queries
        query_count = 0
        @event.listens_for(engine, "before_cursor_execute")
        def receive_before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            nonlocal query_count
            if statement.strip().upper().startswith("SELECT"):
                query_count += 1

        start_time = time.perf_counter()
        result = compute_team_analytics(db=db, current_user=manager)
        end_time = time.perf_counter()
        duration_ms = (end_time - start_time) * 1000.0

        # Remove listener to avoid accumulation across loop iterations
        event.remove(engine, "before_cursor_execute", receive_before_cursor_execute)

        print(f"SESSIONS={result['session_count']} | BREAKS={session_count * breaks_per_session} | SELECT_QUERIES={query_count} | DURATION={duration_ms:.2f}ms")

if __name__ == "__main__":
    run_benchmark()
