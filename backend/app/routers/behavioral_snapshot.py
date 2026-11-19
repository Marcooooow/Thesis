from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional

from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User
from ..services.behavioral_snapshot_service import (
    generate_daily_snapshot, get_latest_snapshot, get_snapshot_history, serialize_snapshot
)

router = APIRouter(
    prefix="/behavioral-snapshots",
    tags=["behavioral-snapshots"],
    responses={404: {"description": "Not found"}},
)

@router.get("/me")
def get_my_latest_snapshot(
    window_days: int = Query(30, description="Observation window in days (7, 14, 30)"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Retrieve the latest behavioral observation snapshot for the authenticated employee."""
    snapshot = get_latest_snapshot(db, current_user.id, window_days=window_days)
    if not snapshot:
        snapshot = generate_daily_snapshot(db, current_user.id, window_days=window_days)
    return serialize_snapshot(snapshot)

@router.get("/me/history")
def get_my_snapshot_history(
    limit: int = Query(10, ge=1, le=50),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Retrieve historical behavioral observation snapshots for the authenticated employee."""
    history = get_snapshot_history(db, current_user.id, limit=limit)
    return [serialize_snapshot(s) for s in history]

@router.post("/generate")
def trigger_generate_snapshot(
    window_days: int = Query(30, description="Observation window in days (7, 14, 30)"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Manually trigger (or update) the daily behavioral observation snapshot idempotently."""
    snapshot = generate_daily_snapshot(db, current_user.id, window_days=window_days)
    return serialize_snapshot(snapshot)
