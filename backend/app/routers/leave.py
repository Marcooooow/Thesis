from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import date

from ..database import get_db
from ..auth.security import get_current_active_user, get_current_manager_user, get_current_admin_user
from ..models import User, Profile, LeaveType, LeaveRequest, OrganizationMembership
from ..schemas.absence import (
    LeaveTypeCreate, LeaveTypeUpdate, LeaveTypeResponse,
    LeaveRequestCreate, LeaveRequestReview, LeaveRequestResponse
)
from ..services.leave_service import LeaveService

router = APIRouter(
    tags=["leave"],
)

admin_router = APIRouter(
    prefix="/admin/leave-types",
    tags=["admin-leave-types"],
    responses={404: {"description": "Not found"}},
)

leave_router = APIRouter(
    prefix="/leave",
    tags=["leave"],
    responses={404: {"description": "Not found"}},
)

manager_leave_router = APIRouter(
    prefix="/manager/leave",
    tags=["manager-leave"],
    responses={404: {"description": "Not found"}},
)

# Admin Leave Types Endpoints
@admin_router.get("", response_model=List[LeaveTypeResponse])
def list_leave_types(
    include_inactive: bool = False,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    membership = db.query(OrganizationMembership).filter(OrganizationMembership.user_id == current_user.id).first()
    org_id = membership.organization_id if membership else None

    query = db.query(LeaveType)
    if org_id:
        query = query.filter(LeaveType.organization_id == org_id)
    if not include_inactive:
        query = query.filter(LeaveType.is_active == True)
    return query.order_by(LeaveType.sort_order, LeaveType.name).all()

@admin_router.post("", response_model=LeaveTypeResponse, status_code=status.HTTP_201_CREATED)
def create_leave_type(
    data: LeaveTypeCreate,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    membership = db.query(OrganizationMembership).filter(OrganizationMembership.user_id == current_user.id).first()
    if not membership:
        org = db.query(LeaveType).first()
        org_id = org.organization_id if org else uuid.uuid4()
    else:
        org_id = membership.organization_id

    leave_type = LeaveType(
        organization_id=org_id,
        name=data.name,
        requires_documentation=data.requires_documentation,
        is_active=data.is_active,
        sort_order=data.sort_order
    )
    db.add(leave_type)
    db.commit()
    db.refresh(leave_type)
    return leave_type

@admin_router.patch("/{leave_type_id}", response_model=LeaveTypeResponse)
def update_leave_type(
    leave_type_id: uuid.UUID,
    data: LeaveTypeUpdate,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    leave_type = db.query(LeaveType).filter(LeaveType.id == leave_type_id).first()
    if not leave_type:
        raise HTTPException(status_code=404, detail="Leave type not found")

    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(leave_type, field, value)

    db.commit()
    db.refresh(leave_type)
    return leave_type

# Employee Leave Endpoints
@leave_router.get("/types", response_model=List[LeaveTypeResponse])
def list_active_leave_types(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    membership = db.query(OrganizationMembership).filter(OrganizationMembership.user_id == current_user.id).first()
    org_id = membership.organization_id if membership else None

    query = db.query(LeaveType).filter(LeaveType.is_active == True)
    if org_id:
        query = query.filter(LeaveType.organization_id == org_id)
    return query.order_by(LeaveType.sort_order, LeaveType.name).all()

@leave_router.post("/requests", response_model=LeaveRequestResponse, status_code=status.HTTP_201_CREATED)
def submit_leave_request(
    data: LeaveRequestCreate,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    leave_type = db.query(LeaveType).filter(LeaveType.id == data.leave_type_id).first()
    if not leave_type or not leave_type.is_active:
        raise HTTPException(status_code=400, detail="Invalid or inactive leave type")

    leave_svc = LeaveService(db)
    try:
        req = leave_svc.submit_request(
            profile_id=profile.id,
            leave_type_id=data.leave_type_id,
            start_date=data.start_date,
            end_date=data.end_date,
            reason=data.reason
        )
        return req
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@leave_router.get("/requests/my", response_model=List[LeaveRequestResponse])
def list_my_leave_requests(
    status_filter: Optional[str] = Query(None, alias="status"),
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        return []

    query = db.query(LeaveRequest).filter(LeaveRequest.profile_id == profile.id)
    if status_filter:
        query = query.filter(LeaveRequest.status == status_filter.upper())
    return query.order_by(LeaveRequest.created_at.desc()).offset(offset).limit(limit).all()

@leave_router.patch("/requests/{request_id}/cancel", response_model=LeaveRequestResponse)
def cancel_leave_request(
    request_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    leave_svc = LeaveService(db)
    try:
        return leave_svc.cancel_request(request_id, profile.id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

# Manager Leave Endpoints
@manager_leave_router.get("/requests", response_model=List[LeaveRequestResponse])
def list_team_leave_requests(
    status_filter: Optional[str] = Query(None, alias="status"),
    profile_id: Optional[uuid.UUID] = None,
    limit: int = 50,
    offset: int = 0,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    leave_svc = LeaveService(db)
    if current_user.role and current_user.role.strip().upper() == "ADMIN":
        query = db.query(LeaveRequest)
        if status_filter:
            query = query.filter(LeaveRequest.status == status_filter.upper())
        if profile_id:
            query = query.filter(LeaveRequest.profile_id == profile_id)
        return query.order_by(LeaveRequest.created_at.desc()).offset(offset).limit(limit).all()
    else:
        pending = leave_svc.get_pending_for_manager(current_user.id)
        if status_filter:
            pending = [r for r in pending if r.status == status_filter.upper()]
        if profile_id:
            pending = [r for r in pending if r.profile_id == profile_id]
        return pending[offset:offset+limit]

@manager_leave_router.patch("/requests/{request_id}/review", response_model=LeaveRequestResponse)
def review_leave_request(
    request_id: uuid.UUID,
    data: LeaveRequestReview,
    current_user: User = Depends(get_current_manager_user),
    db: Session = Depends(get_db)
):
    leave_svc = LeaveService(db)
    try:
        return leave_svc.review_request(
            request_id=request_id,
            reviewer_user_id=current_user.id,
            approve=data.approve,
            reviewer_note=data.reviewer_note
        )
    except ValueError as e:
        err_msg = str(e)
        if "cannot approve" in err_msg.lower():
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=err_msg)
        raise HTTPException(status_code=400, detail=err_msg)
