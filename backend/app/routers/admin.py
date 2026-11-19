from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
import uuid
from datetime import datetime
from uuid import UUID
import secrets

from ..database import get_db
from ..auth.security import get_current_admin_user, get_password_hash, log_system_activity, get_organization_ids_for_user
from ..models import User, Profile, OrganizationMembership, Organization, SystemActivityLog, RecommendationFeedback, SessionWellbeingCheckin
from ..services.dataset_export_service import DatasetExportService
from sqlalchemy.orm import joinedload
from ..schemas.auth import UserResponse, AuditLogResponse
from ..schemas.manager import ManagerCreateRequest, ManagerCreateResponse

router = APIRouter(
    prefix="/admin",
    tags=["admin"],
    responses={404: {"description": "Not found"}},
)


@router.get("/pending-users", response_model=List[UserResponse])
def get_pending_users(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Get a list of all users with approval_status = PENDING.
    Only accessible by ADMIN.
    """
    pending_users = db.query(User).options(joinedload(User.profile)).filter(User.approval_status == "PENDING").all()
    return [
        UserResponse(
            id=user.id,
            email=user.email,
            full_name=user.full_name,
            account_type=user.account_type,
            role=user.role,
            approval_status=user.approval_status,
            is_active=user.is_active,
            must_change_password=user.must_change_password,
            job_role=user.profile.job_role if user.profile else None,
            password_change_token_version=user.password_change_token_version,
            created_at=user.created_at,
            updated_at=user.updated_at,
        )
        for user in pending_users
    ]


@router.patch("/approve-user/{user_id}", response_model=UserResponse)
def approve_user(
    user_id: str,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Approve a pending user by setting approval_status to APPROVED.
    Only accessible by ADMIN.
    Logs the action in system_activity_logs.
    """
    # Validate UUID format
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    user = db.query(User).filter(User.id == user_uuid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    if user.approval_status != "PENDING":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"User is not pending (current status: {user.approval_status})",
        )

    user.approval_status = "APPROVED"
    db.add(user)
    db.commit()
    db.refresh(user)

    # Log the action
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="USER_APPROVED",
        category="ACCOUNT",
        target_type="user",
        target_id=str(user.id),
        target_display_label=user.email,
        outcome="SUCCESS",
        summary=f"Approved user {user.email}",
        action_details={"approved_user_id": str(user.id), "user_email": user.email},
    )

    return user


@router.patch("/reject-user/{user_id}", response_model=UserResponse)
def reject_user(
    user_id: str,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Reject a pending user by setting approval_status to REJECTED.
    Only accessible by ADMIN.
    Logs the action in system_activity_logs.
    """
    # Validate UUID format
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format",
        )

    user = db.query(User).filter(User.id == user_uuid).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    if user.approval_status != "PENDING":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"User is not pending (current status: {user.approval_status})",
        )

    user.approval_status = "REJECTED"
    db.add(user)
    db.commit()
    db.refresh(user)

    # Log the action
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="USER_REJECTED",
        category="ACCOUNT",
        target_type="user",
        target_id=str(user.id),
        target_display_label=user.email,
        outcome="SUCCESS",
        summary=f"Rejected user {user.email}",
        action_details={"rejected_user_id": str(user.id), "user_email": user.email},
    )

    return user


@router.get("/audit-logs/summary")
def get_audit_logs_summary(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
    action_type: Optional[str] = None,
    category: Optional[str] = None,
    outcome: Optional[str] = None,
    user_id: Optional[uuid.UUID] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    search: Optional[str] = None,
):
    """
    Get summary KPI metrics for audit logs matching filters.
    Only accessible by ADMIN.
    """
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        raise HTTPException(status_code=403, detail="Admin has no approved organization membership")
    query = db.query(SystemActivityLog).join(
        User, SystemActivityLog.user_id == User.id
    ).join(
        OrganizationMembership, OrganizationMembership.user_id == User.id
    ).filter(
        OrganizationMembership.organization_id.in_(org_ids),
        OrganizationMembership.status == "APPROVED",
    ).distinct()

    if action_type:
        query = query.filter(SystemActivityLog.action_type == action_type)
    if category:
        query = query.filter(SystemActivityLog.action_details['category'].as_string() == category)
    if outcome:
        query = query.filter(SystemActivityLog.action_details['outcome'].as_string() == outcome)
    if user_id:
        query = query.filter(SystemActivityLog.user_id == user_id)
    if start_date:
        query = query.filter(SystemActivityLog.created_at >= start_date)
    if end_date:
        query = query.filter(SystemActivityLog.created_at <= end_date)
    if search:
        search_pattern = f"%{search}%"
        query = query.filter(
            or_(
                SystemActivityLog.action_type.ilike(search_pattern),
                SystemActivityLog.action_details['summary'].as_string().ilike(search_pattern),
                SystemActivityLog.action_details['target_display_label'].as_string().ilike(search_pattern)
            )
        )

    total_events = query.count()

    auth_query = query.filter(
        or_(
            SystemActivityLog.action_details['category'].as_string().in_(['SECURITY', 'AUTHENTICATION']),
            SystemActivityLog.action_type.in_(['LOGIN', 'LOGOUT', 'LOGIN_SUCCESS', 'LOGIN_FAILED', 'LOGIN_CHALLENGE_REQUIRED', 'LOGIN_PASSWORD_CHANGE_REQUIRED', 'PASSWORD_CHANGED', 'PASSWORD_RESET'])
        )
    )
    auth_security_events = auth_query.count()

    failed_query = query.filter(SystemActivityLog.action_details['outcome'].as_string() == 'FAILURE')
    failed_events = failed_query.count()

    from sqlalchemy import func as sa_func
    min_max = query.with_entities(sa_func.min(SystemActivityLog.created_at), sa_func.max(SystemActivityLog.created_at)).first()
    earliest_date = min_max[0].isoformat() if min_max and min_max[0] else None
    latest_date = min_max[1].isoformat() if min_max and min_max[1] else None

    return {
        "total_events": total_events,
        "auth_security_events": auth_security_events,
        "failed_events": failed_events,
        "earliest_date": earliest_date,
        "latest_date": latest_date,
    }


@router.get("/audit-logs", response_model=List[AuditLogResponse])
def get_audit_logs(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
    page: int = Query(1, ge=1),
    limit: int = Query(25, ge=1, le=100),
    action_type: Optional[str] = None,
    category: Optional[str] = None,
    outcome: Optional[str] = None,
    user_id: Optional[uuid.UUID] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    search: Optional[str] = None,
):
    """
    Get system activity logs with pagination and filtering.
    Only accessible by ADMIN.
    Returns newest records first.
    """
    org_ids = get_organization_ids_for_user(db, current_user.id)
    if not org_ids:
        raise HTTPException(status_code=403, detail="Admin has no approved organization membership")

    query = db.query(SystemActivityLog).\
        join(User, SystemActivityLog.user_id == User.id).\
        join(OrganizationMembership, OrganizationMembership.user_id == User.id).\
        filter(
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED",
        ).\
        add_columns(User.full_name, User.email)

    # Apply filters
    if action_type:
        query = query.filter(SystemActivityLog.action_type == action_type)
    if category:
        query = query.filter(SystemActivityLog.action_details['category'].as_string() == category)
    if outcome:
        query = query.filter(SystemActivityLog.action_details['outcome'].as_string() == outcome)
    if user_id:
        query = query.filter(SystemActivityLog.user_id == user_id)
    if start_date:
        query = query.filter(SystemActivityLog.created_at >= start_date)
    if end_date:
        query = query.filter(SystemActivityLog.created_at <= end_date)
    if search:
        search_pattern = f"%{search}%"
        query = query.filter(
            or_(
                SystemActivityLog.action_type.ilike(search_pattern),
                SystemActivityLog.action_details['summary'].as_string().ilike(search_pattern),
                SystemActivityLog.action_details['target_display_label'].as_string().ilike(search_pattern)
            )
        )

    # Order by newest first
    query = query.order_by(SystemActivityLog.created_at.desc())

    # Pagination
    offset = (page - 1) * limit
    results = query.offset(offset).limit(limit).all()

    # Map to AuditLogResponse
    logs = []
    for log, full_name, email in results:
        details = log.action_details or {}
        logs.append(AuditLogResponse(
            id=str(log.id),
            user_id=str(log.user_id) if log.user_id else None,
            user_full_name=full_name,
            user_email=email,
            action_type=log.action_type,
            category=details.get("category", "SYSTEM"),
            target_type=details.get("target_type"),
            target_id=details.get("target_id"),
            target_display_label=details.get("target_display_label"),
            outcome=details.get("outcome", "UNKNOWN" if not log.action_details or "outcome" not in log.action_details else "SUCCESS"),
            summary=details.get("summary", log.action_type.replace("_", " ").title()),
            action_details=details,
            ip_address=log.ip_address,
            user_agent=log.user_agent,
            created_at=log.created_at
        ))

    return logs


@router.post("/managers", response_model=ManagerCreateResponse, status_code=status.HTTP_201_CREATED)
def create_manager(
    manager_data: ManagerCreateRequest,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Create a new manager by an admin.

    Authorization:
    - Must be an ADMIN

    Creates:
    - User with role=MANAGER, approval_status=APPROVED, must_change_password=TRUE
    - Profile for the manager
    - OrganizationMembership with role=MANAGER, status=APPROVED

    Returns manager details and temporary password (shown only once).
    """
    # Normalize email
    email = manager_data.email.lower().strip()

    # Check if user already exists
    db_user = db.query(User).filter(User.email == email).first()
    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    # Validate organization exists
    organization = db.query(Organization).filter(Organization.id == manager_data.organization_id).first()
    if not organization:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Organization not found"
        )

    # Generate cryptographically secure temporary password with >= 128 bits entropy
    # secrets.token_urlsafe(32) uses 32 chars of base64 → 32*6 = 192 bits >= 128
    temp_password = secrets.token_urlsafe(32)

    # Hash the temporary password
    hashed_password = get_password_hash(temp_password)

    try:
        # Create User
        db_user = User(
            email=email,
            full_name=manager_data.full_name,
            role="MANAGER",
            account_type="organization",
            approval_status="APPROVED",
            is_active=True,
            must_change_password=True,
            password_change_token_version=0,
            password_hash=hashed_password
        )
        db.add(db_user)
        db.flush()  # Get the user ID

        # Create Profile (following existing patterns)
        db_profile = Profile(
            user_id=db_user.id,
            job_role=None,  # Optional, not provided in request
            industry=None,
            years_of_experience=None,
            age=None,
            gender=None,
            education_attainment=None,
            marital_status=None,
            target_daily_hours=None,
            shift_start_time=None,
            shift_end_time=None,
            work_days=None
        )
        db.add(db_profile)
        db.flush()

        # Create OrganizationMembership
        org_membership = OrganizationMembership(
            user_id=db_user.id,
            organization_id=manager_data.organization_id,
            role="MANAGER",
            status="APPROVED"
        )
        db.add(org_membership)

        # Commit transaction
        db.commit()
        db.refresh(db_user)
        db.refresh(db_profile)

        # Log action
        log_system_activity(
            db=db,
            user_id=current_user.id,
            request=request,
            action_type="USER_CREATED",
            category="ACCOUNT",
            target_type="user",
            target_id=str(db_user.id),
            target_display_label=db_user.email,
            outcome="SUCCESS",
            summary=f"Created manager user {db_user.email}",
            action_details={"created_user_id": str(db_user.id), "email": db_user.email, "role": db_user.role, "organization_id": str(manager_data.organization_id)}
        )

        # Build response
        return ManagerCreateResponse(
            id=db_user.id,
            email=db_user.email,
            full_name=db_user.full_name,
            is_active=db_user.is_active,
            role=db_user.role,
            approval_status=db_user.approval_status,
            must_change_password=db_user.must_change_password,
            temporary_password=temp_password,  # Return only once
            organization_id=manager_data.organization_id,
            organization_name=organization.name
        )

    except Exception as e:
        db.rollback()
        raise e


@router.get("/users/{user_id}/recommendations")
def get_user_recommendations(
    user_id: str,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Get recommendation history for a specific user. Admin only; same org."""
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID")

    target_user = db.query(User).filter(User.id == user_uuid).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids:
        raise HTTPException(status_code=403, detail="Admin has no approved organization membership")
    emp_membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == target_user.id,
        OrganizationMembership.organization_id.in_(admin_org_ids),
        OrganizationMembership.status == "APPROVED"
    ).first()
    if not emp_membership:
        raise HTTPException(status_code=403, detail="User does not belong to your organization")

    # Log sensitive data access
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="ADMIN_ACCESSED_RECOMMENDATIONS",
        category="DATA_ACCESS",
        target_type="user",
        target_id=str(target_user.id),
        target_display_label=target_user.email,
        outcome="SUCCESS",
        summary=f"Admin accessed recommendation history for {target_user.email}",
        action_details={"target_user_id": str(target_user.id), "target_email": target_user.email}
    )

    feedback = db.query(RecommendationFeedback).filter(
        RecommendationFeedback.user_id == user_uuid
    ).order_by(RecommendationFeedback.timestamp.desc()).all()
    return [
        {
            "recommendation_id": str(f.recommendation_id),
            "recommendation_type": f.recommendation_type,
            "recommendation_score": f.recommendation_score,
            "model_version": f.model_version,
            "user_action": f.user_action,
            "timestamp": f.timestamp.isoformat() if f.timestamp else None,
            "reason": f.context_features.get("reason") if isinstance(f.context_features, dict) else None,
        }
        for f in feedback
    ]


@router.get("/users/{user_id}/wellbeing")
def get_user_wellbeing(
    user_id: str,
    request: Request,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Get wellbeing check-ins for a specific user. Admin only; same org."""
    try:
        user_uuid = uuid.UUID(user_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user ID")

    target_user = db.query(User).filter(User.id == user_uuid).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids:
        raise HTTPException(status_code=403, detail="Admin has no approved organization membership")
    emp_membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == target_user.id,
        OrganizationMembership.organization_id.in_(admin_org_ids),
        OrganizationMembership.status == "APPROVED"
    ).first()
    if not emp_membership:
        raise HTTPException(status_code=403, detail="User does not belong to your organization")

    # Log sensitive data access
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="ADMIN_ACCESSED_WELLBEING",
        category="DATA_ACCESS",
        target_type="user",
        target_id=str(target_user.id),
        target_display_label=target_user.email,
        outcome="SUCCESS",
        summary=f"Admin accessed wellbeing check-ins for {target_user.email}",
        action_details={"target_user_id": str(target_user.id), "target_email": target_user.email}
    )

    checkins = db.query(SessionWellbeingCheckin).filter(
        SessionWellbeingCheckin.user_id == user_uuid
    ).order_by(SessionWellbeingCheckin.created_at.desc()).all()
    return [
        {
            "id": str(c.id),
            "work_session_id": str(c.work_session_id) if c.work_session_id else None,
            "overall_wellbeing": c.overall_wellbeing,
            "mental_fatigue": c.mental_fatigue,
            "workload_manageability": c.workload_manageability,
            "perceived_focus": c.perceived_focus,
            "break_recovery": c.break_recovery,
            "stress_factors": c.stress_factors or [],
            "notes": c.notes,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        }
        for c in checkins
    ]


@router.get("/user-counts")
def get_user_counts(
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Get counts of users by approval status and role.
    Only accessible by ADMIN.
    Returns counts for employees, managers, and pending approvals.
    """
    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="ADMIN_USER_COUNTS_ACCESSED",
        action_details={}
    )

    org_ids = get_organization_ids_for_user(db, current_user.id)
    def _apply_org_filter(q):
        if org_ids:
            return q.join(
                OrganizationMembership, OrganizationMembership.user_id == User.id
            ).filter(
                OrganizationMembership.organization_id.in_(org_ids),
                OrganizationMembership.status == "APPROVED"
            ).distinct()
        return q

    # Count employees (EMPLOYEE role, APPROVED status)
    employees_count = _apply_org_filter(db.query(User)).filter(
        User.role == "EMPLOYEE",
        User.approval_status == "APPROVED",
        User.is_active == True
    ).count()

    # Count managers (MANAGER role, APPROVED status)
    managers_count = _apply_org_filter(db.query(User)).filter(
        User.role == "MANAGER",
        User.approval_status == "APPROVED",
        User.is_active == True
    ).count()

    # Count pending approvals (any role, PENDING status)
    pending_count = _apply_org_filter(db.query(User)).filter(
        User.approval_status == "PENDING",
        User.is_active == True
    ).count()

    return {
        "employees": employees_count,
        "managers": managers_count,
        "pending": pending_count
    }


@router.get("/dataset/export")
def export_ml_dataset(
    request: Request,
    include_demo_data: bool = Query(True, description="Include or exclude demo/test data records."),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Export actual IntelliBreak PostgreSQL records into a multi-sheet Excel workbook (.xlsx)
    for ML research, experimentation, and thesis analysis.
    Only accessible by ADMIN.
    """
    try:
        service = DatasetExportService(db)
        file_stream = service.generate_excel_workbook(include_demo_data=include_demo_data)

        # Log admin export action
        log_system_activity(
            db=db,
            user_id=current_user.id,
            request=request,
            action_type="ADMIN_DATASET_EXPORTED",
            category="ADMIN",
            target_type="dataset",
            target_id="ml_dataset_export",
            target_display_label=current_user.email,
            outcome="SUCCESS",
            summary=f"Admin exported ML dataset workbook (include_demo_data={include_demo_data})",
            action_details={"include_demo_data": include_demo_data},
        )

        file_stream.seek(0)
        headers = {
            "Content-Disposition": 'attachment; filename="intellibreak_ml_dataset.xlsx"',
        }
        return StreamingResponse(
            file_stream,
            headers=headers,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Dataset export failed: {str(e)}"
        )
