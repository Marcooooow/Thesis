from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from uuid import UUID
from ..schemas.profile import ProfileResponse, ProfileUpdateRequest
from ..models import User, Profile, EmployeeSchedule
from ..database import get_db
from ..auth.security import get_current_active_user
from ..services.cache_service import analytics_cache
from datetime import datetime, timezone, time, date
from urllib.parse import urlparse

router = APIRouter(
    prefix="/profile",
    tags=["profile"],
    responses={404: {"description": "Not found"}},
)


def _build_profile_response(profile: Profile, current_user: User) -> dict:
    """
    Build a profile response dictionary from Profile and User objects.
    """
    def fmt_time(val):
        if not val:
            return None
        if hasattr(val, 'strftime'):
            return val.strftime('%H:%M')
        return str(val)[:5]

    def fmt_date(val):
        if not val:
            return None
        if hasattr(val, 'strftime'):
            return val.strftime('%Y-%m-%d')
        return str(val)[:10]

    return {
        "id": str(profile.id),
        "full_name": current_user.full_name,
        "phone_number": profile.phone_number,
        "job_role": profile.job_role,
        "industry": profile.industry,
        "years_of_experience": profile.years_of_experience,
        "age": profile.age,
        "gender": profile.gender,
        "education_attainment": profile.education_attainment,
        "marital_status": profile.marital_status,
        "target_daily_hours": profile.target_daily_hours,
        "shift_start_time": fmt_time(profile.shift_start_time),
        "shift_end_time": fmt_time(profile.shift_end_time),
        "work_days": profile.work_days,
        "hire_date": fmt_date(profile.hire_date),
        "department": profile.department,
        "is_test_data": profile.is_test_data,
        "created_at": profile.created_at.isoformat(),
        "updated_at": profile.updated_at.isoformat(),
        "profile_image_url": profile.profile_image_url,
    }


@router.get("/me", response_model=ProfileResponse)
def get_current_user_profile(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get current user's profile.
    """
    # Get the profile via the relationship
    profile = current_user.profile
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )
    return _build_profile_response(profile, current_user)


@router.patch("/me", response_model=ProfileResponse)
def update_current_user_profile(
    profile_update: ProfileUpdateRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Update current user's profile.
    Only non-sensitive fields can be updated.
    Auth-controlled fields (email, role, approval_status, etc.) are protected.
    """
    # Get the profile via the relationship
    profile = current_user.profile
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Update only the fields that were provided
    update_data = profile_update.model_dump(exclude_unset=True)

    # Handle full_name: update the User's full_name
    if 'full_name' in update_data:
        current_user.full_name = update_data['full_name']
        # Remove full_name from update_data so we don't try to set it on the Profile
        del update_data['full_name']

    is_sqlite = False
    try:
        if db.bind and hasattr(db.bind, 'dialect') and db.bind.dialect:
            is_sqlite = (db.bind.dialect.name == 'sqlite')
    except Exception:
        pass

    # Validate shift times if provided
    if 'shift_start_time' in update_data and update_data['shift_start_time'] is not None:
        try:
            t_obj = time.fromisoformat(update_data['shift_start_time']) if isinstance(update_data['shift_start_time'], str) else update_data['shift_start_time']
            update_data['shift_start_time'] = t_obj
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid start time format. Expected HH:MM"
            )

    if 'shift_end_time' in update_data and update_data['shift_end_time'] is not None:
        try:
            t_obj = time.fromisoformat(update_data['shift_end_time']) if isinstance(update_data['shift_end_time'], str) else update_data['shift_end_time']
            update_data['shift_end_time'] = t_obj
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid end time format. Expected HH:MM"
            )

    if 'shift_start_time' in update_data or 'shift_end_time' in update_data:
        start_time = update_data.get('shift_start_time', profile.shift_start_time)
        end_time = update_data.get('shift_end_time', profile.shift_end_time)
        if start_time is not None and end_time is not None and start_time == end_time:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Start time cannot equal end time"
            )

    # Validate work days if provided
    if 'work_days' in update_data and update_data['work_days'] is not None:
        valid_days = {'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'}
        for day in update_data['work_days']:
            if day.lower() not in valid_days:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Invalid work day: {day}. Must be one of {valid_days}"
                )

    # Validate hire date format if provided
    if 'hire_date' in update_data and update_data['hire_date'] is not None:
        hire_date_str = update_data['hire_date']
        try:
            hire_date = date.fromisoformat(hire_date_str)
            update_data['hire_date'] = hire_date
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="hire_date must be in YYYY-MM-DD format"
            )

    # Validate profile_image_url if provided
    if 'profile_image_url' in update_data:
        image_url = update_data['profile_image_url']
        # Allow null/None values (for removing profile image)
        if image_url is not None:
            # Parse the URL to validate it's from our Firebase Storage bucket
            try:
                parsed_url = urlparse(image_url)
                # Must be HTTPS
                if parsed_url.scheme != 'https':
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Profile image URL must use HTTPS"
                    )
                # Must be from Firebase Storage
                if parsed_url.netloc != 'firebasestorage.googleapis.com':
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Profile image URL must be from Firebase Storage"
                    )
                # Must be from our specific bucket
                expected_buckets = {
                    'intellibreak-9a933.firebasestorage.app',
                    'intellibreak-829de.firebasestorage.app',
                }
                # Firebase Storage URLs have format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{object}
                if not any(parsed_url.path.startswith(f'/v0/b/{bucket}/o/') for bucket in expected_buckets):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Profile image URL must be from the configured Firebase Storage bucket"
                    )
            except Exception as e:
                if isinstance(e, HTTPException):
                    raise e
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid profile image URL format"
                )

    # Apply updates to the profile
    for field, value in update_data.items():
        setattr(profile, field, value)

    # Sync EmployeeSchedule if schedule fields were updated
    if any(k in update_data for k in ['shift_start_time', 'shift_end_time', 'work_days', 'hire_date']):
        today = date.today()
        active_sched = db.query(EmployeeSchedule).filter(
            EmployeeSchedule.profile_id == profile.id,
            EmployeeSchedule.effective_from <= today,
            (EmployeeSchedule.effective_until.is_(None) | (EmployeeSchedule.effective_until >= today))
        ).order_by(EmployeeSchedule.effective_from.desc()).first()

        if active_sched:
            if profile.shift_start_time is not None:
                active_sched.shift_start = time.fromisoformat(profile.shift_start_time) if isinstance(profile.shift_start_time, str) else profile.shift_start_time
            if profile.shift_end_time is not None:
                active_sched.shift_end = time.fromisoformat(profile.shift_end_time) if isinstance(profile.shift_end_time, str) else profile.shift_end_time
            if profile.work_days is not None:
                active_sched.work_days = profile.work_days
            active_sched.updated_at = datetime.now(timezone.utc)
        else:
            start_t = time.fromisoformat(profile.shift_start_time) if isinstance(profile.shift_start_time, str) else (profile.shift_start_time or time(8, 0))
            end_t = time.fromisoformat(profile.shift_end_time) if isinstance(profile.shift_end_time, str) else (profile.shift_end_time or time(17, 0))
            new_sched = EmployeeSchedule(
                profile_id=profile.id,
                effective_from=profile.hire_date or today,
                effective_until=None,
                work_days=profile.work_days or ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'],
                shift_start=start_t,
                shift_end=end_t,
                timezone='Asia/Manila',
                created_by=current_user.id
            )
            db.add(new_sched)

    db.commit()
    analytics_cache.invalidate()
    db.refresh(profile)
    return _build_profile_response(profile, current_user)
