"""Settings API endpoints for user preferences."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ..schemas.settings import UserSettingsRead, UserSettingsUpdate
from ..models import User, UserSettings
from ..database import get_db
from ..auth.security import get_current_active_user

router = APIRouter(
    prefix="/settings",
    tags=["settings"],
    responses={404: {"description": "Not found"}},
)


@router.get("", response_model=UserSettingsRead)
def get_user_settings(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get current user's settings.
    Returns all saved preferences with defaults for any missing values.
    """
    settings = db.query(UserSettings).filter(
        UserSettings.user_id == current_user.id
    ).first()

    if not settings:
        settings = UserSettings(user_id=current_user.id)
        db.add(settings)
        db.commit()
        db.refresh(settings)

    return settings


@router.post("", response_model=UserSettingsRead, status_code=status.HTTP_201_CREATED)
def create_user_settings(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Initialize settings for current user with defaults.
    Idempotent: returns existing settings if already created.
    """
    # Check if settings already exist
    existing = db.query(UserSettings).filter(
        UserSettings.user_id == current_user.id
    ).first()

    if existing:
        return existing

    # Create with all defaults
    settings = UserSettings(user_id=current_user.id)
    db.add(settings)
    db.commit()
    db.refresh(settings)

    return settings


@router.patch("", response_model=UserSettingsRead)
def update_user_settings(
    settings_update: UserSettingsUpdate,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Update current user's settings.
    Only provided fields are updated; unspecified fields remain unchanged.
    All updates are validated server-side.
    """
    settings = db.query(UserSettings).filter(
        UserSettings.user_id == current_user.id
    ).first()

    if not settings:
        settings = UserSettings(user_id=current_user.id)
        db.add(settings)
        db.flush()

    # Update only provided fields (exclude None values)
    update_data = settings_update.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if value is not None:
            setattr(settings, field, value)

    db.commit()
    db.refresh(settings)

    return settings
