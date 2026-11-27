from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from .database import test_connection
from .routers import auth, admin, work, analytics, team, profile, notification, employee, settings, session_wellbeing, presence, wellbeing_monitoring, manager_analytics, reports, wlb, messaging, schedule, leave, absence, return_to_work, attendance, user_work_profile, behavioral_snapshot
from .services import recommendation_service, ml_service
from .routers import ml_admin
from .scheduler import create_scheduler, run_absence_scan, retry_pending_notifications, expire_unanswered_recommendations, auto_close_stale_sessions

app = FastAPI(
    title="IntelliBreak API",
    description="Backend API for IntelliBreak application",
    version="1.0.0"
)

import os
from typing import List, Optional

# Load .env (local dev) — ignore failure in production
try:
    if os.getenv("RENDER") != "true":
        from dotenv import load_dotenv
        load_dotenv()
except Exception:
    pass

# Read CORS allowed origins from environment
cors_allowed_origins = os.getenv("CORS_ALLOWED_ORIGINS", "").strip()
is_production = os.getenv("RENDER", "false") == "true" or os.getenv("ENVIRONMENT", "").lower() == "production"

if not cors_allowed_origins:
    if is_production:
        allow_origins = [
            "https://intellibreak-829de.web.app",
            "https://intellibreak-829de.firebaseapp.com",
            "https://intellibreak-9a933.web.app",
        ]
    else:
        allow_origins = ["http://localhost:3000", "http://127.0.0.1:3000", "http://localhost:8080"]
else:
    allow_origins = [o.strip() for o in cors_allowed_origins.split(",") if o.strip()]

# Always support dynamic localhost and 127.0.0.1 ports for Flutter Web development
allow_origin_regex = r"^https?://(?:localhost|127\.0\.0\.1)(?::\d+)?$"

class SecurityHeadersMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_wrapper(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.append((b"x-content-type-options", b"nosniff"))
                headers.append((b"referrer-policy", b"strict-origin-when-cross-origin"))
                headers.append((b"x-frame-options", b"DENY"))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_wrapper)

app.add_middleware(SecurityHeadersMiddleware)

# Add CORSMiddleware last so it is the outermost middleware and wraps all error/500 responses
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_origin_regex=allow_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth.router)
app.include_router(admin.router)
app.include_router(work.router)
app.include_router(analytics.router)
app.include_router(team.router)
app.include_router(profile.router)
app.include_router(settings.router)
app.include_router(notification.router)
app.include_router(employee.router)
app.include_router(ml_service.router)
app.include_router(recommendation_service.router)
app.include_router(session_wellbeing.router)
app.include_router(presence.router)
app.include_router(ml_admin.router)
app.include_router(wellbeing_monitoring.router)
app.include_router(manager_analytics.router)
app.include_router(reports.router)
app.include_router(wlb.router)
app.include_router(messaging.router)
app.include_router(schedule.router)
app.include_router(leave.admin_router)
app.include_router(leave.leave_router)
app.include_router(leave.manager_leave_router)
app.include_router(absence.router)
app.include_router(return_to_work.rtw_router)
app.include_router(return_to_work.manager_rtw_router)
app.include_router(attendance.router)
app.include_router(user_work_profile.router)
app.include_router(behavioral_snapshot.router)

# APScheduler singleton — initialized on startup, shutdown on exit
_scheduler = None

def _validate_secret_key() -> None:
    """Validate JWT secret key at startup.

    Raises:
        RuntimeError: If SECRET_KEY is missing, empty, or insecure in production.
    """
    from .auth.security import SECRET_KEY

    is_production = os.getenv("RENDER", "false") == "true" or os.getenv("ENVIRONMENT", "").lower() == "production"

    if not SECRET_KEY or not SECRET_KEY.strip():
        raise RuntimeError("SECRET_KEY environment variable is required but not set")

    # Check for common placeholder/insecure values
    insecure_values = {
        "default", "changeme", "secret", "test", "insecure",
        "your-secret-key", "your_secret_key", "changeme_in_production"
    }

    secret_lower = SECRET_KEY.strip().lower()
    if secret_lower in insecure_values:
        if is_production:
            raise RuntimeError(
                "SECRET_KEY is set to a known insecure placeholder value. "
                "Please set a strong random secret for production."
            )
        else:
            # In development, warn but allow
            import warnings
            warnings.warn(
                f"SECRET_KEY is set to an insecure placeholder value ('{SECRET_KEY}'). "
                "This is acceptable for development but MUST be changed for production.",
                RuntimeWarning,
                stacklevel=2
            )

    # In production, enforce minimum entropy (at least 32 chars, not all same char)
    if is_production:
        if len(SECRET_KEY) < 32:
            raise RuntimeError(
                "SECRET_KEY must be at least 32 characters long in production. "
                f"Current length: {len(SECRET_KEY)}"
            )
        if len(set(SECRET_KEY)) < 8:
            raise RuntimeError(
                "SECRET_KEY appears to have insufficient entropy (too few unique characters). "
                "Please use a cryptographically secure random secret."
            )


@app.on_event("startup")
async def startup_scheduler():
    # Validate JWT secret before starting any services
    _validate_secret_key()

    global _scheduler
    _scheduler = create_scheduler()
    _scheduler.add_job(
        run_absence_scan,
        'interval',
        minutes=30,
        id='absence_detection_scan',
        replace_existing=True,
        coalesce=True,
        max_instances=1,
        misfire_grace_time=1800
    )
    _scheduler.add_job(
        retry_pending_notifications,
        'interval',
        hours=1,
        id='notification_retry',
        replace_existing=True,
        coalesce=True,
        max_instances=1
    )
    _scheduler.add_job(
        expire_unanswered_recommendations,
        'interval',
        hours=1,
        id='recommendation_expiration',
        replace_existing=True,
        coalesce=True,
        max_instances=1
    )
    _scheduler.add_job(
        auto_close_stale_sessions,
        'interval',
        hours=1,
        id='auto_close_stale_sessions',
        replace_existing=True,
        coalesce=True,
        max_instances=1
    )
    _scheduler.start()

@app.on_event("shutdown")
async def shutdown_scheduler():
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None

@app.get("/")
async def root():
    return {"message": "Welcome to IntelliBreak API"}

@app.get("/health/live")
async def health_live():
    """Liveness probe: verifies FastAPI application is running."""
    return {"status": "alive"}

@app.get("/health/ready")
async def health_ready():
    """Readiness probe: verifies database connectivity using SELECT 1."""
    connected = test_connection()
    if not connected:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=503,
            detail={"status": "unhealthy", "database": "disconnected"}
        )
    return {"status": "ready", "database": "connected"}

@app.get("/health")
async def health_check():
    """Comprehensive health check endpoint."""
    connected = test_connection()
    if not connected:
        from fastapi import HTTPException
        raise HTTPException(
            status_code=503,
            detail={"status": "unhealthy", "database": "disconnected"}
        )
    return {
        "status": "healthy",
        "database": "connected"
    }

if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
