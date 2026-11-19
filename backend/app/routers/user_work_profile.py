from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional

from ..database import get_db
from ..auth.security import get_current_active_user
from ..models import User
from ..schemas.user_work_profile import UserWorkProfileCreate, UserWorkProfileUpdate, UserWorkProfileResponse
from ..services.work_profile_service import get_work_profile, create_or_update_work_profile, serialize_work_profile

router = APIRouter(
    prefix="/work-profile",
    tags=["work-profile"],
    responses={404: {"description": "Not found"}},
)

@router.get("/me", response_model=UserWorkProfileResponse)
def get_my_work_profile(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Get the authenticated employee's self-reported work profile / onboarding questionnaire."""
    profile = get_work_profile(db, current_user.id)
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Work profile not found. Please complete the onboarding questionnaire.",
        )
    return serialize_work_profile(profile)

@router.post("", response_model=UserWorkProfileResponse, status_code=status.HTTP_201_CREATED)
def create_work_profile(
    data: UserWorkProfileCreate,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Create or submit the authenticated employee's work profile / onboarding questionnaire."""
    profile = create_or_update_work_profile(db, current_user.id, data)
    return serialize_work_profile(profile)

@router.patch("/me", response_model=UserWorkProfileResponse)
def update_my_work_profile(
    data: UserWorkProfileUpdate,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Update the authenticated employee's work profile."""
    profile = get_work_profile(db, current_user.id)
    if not profile:
        profile = create_or_update_work_profile(db, current_user.id, UserWorkProfileCreate(**data.model_dump(exclude_unset=True)))
    else:
        profile = create_or_update_work_profile(db, current_user.id, data)
    return serialize_work_profile(profile)
