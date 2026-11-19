from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional, List
import secrets
from uuid import UUID

from ..database import get_db
from ..auth.security import get_current_manager_only_user, get_current_admin_user, get_current_active_user, get_password_hash, get_organization_ids_for_user
from ..models import User, Profile, OrganizationMembership, Team, TeamMembership, Organization, WorkSession, Break, Task
from ..schemas.employee import EmployeeCreateRequest, EmployeeCreateResponse, EmployeeListResponse
from ..schemas.auth import UserResponse
from ..schemas.work import SessionHistoryResponse, SessionHistoryBreak, SessionHistoryTask

router = APIRouter(
    prefix="/employees",
    tags=["employees"],
    responses={404: {"description": "Not found"}},
)


@router.post("", response_model=EmployeeCreateResponse, status_code=status.HTTP_201_CREATED)
def create_employee(
    employee_data: EmployeeCreateRequest,
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Create a new employee by a manager.

    Authorization:
    - Must be a MANAGER
    - Manager must have exactly one approved MANAGER organization membership

    Creates:
    - User with role=EMPLOYEE, approval_status=APPROVED, must_change_password=TRUE
    - Profile for the employee
    - OrganizationMembership with role=EMPLOYEE, status=APPROVED
    - Optional TeamMembership if team_id provided and valid

    Returns employee details and temporary password (shown only once).
    """
    # Normalize email
    email = employee_data.email.lower().strip()

    # Check if user already exists
    db_user = db.query(User).filter(User.email == email).first()
    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    # Resolve manager's organization (exact same logic as team creation)
    manager_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role == "MANAGER"
    ).all()

    if len(manager_memberships) == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have an approved MANAGER organization membership to create an employee"
        )
    if len(manager_memberships) > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ambiguous organization: user has multiple approved MANAGER organization memberships"
        )

    organization_id = manager_memberships[0].organization_id

    # Generate cryptographically secure temporary password with >= 128 bits entropy
    # secrets.token_urlsafe(32) uses 32 chars of base64 → 32*6 = 192 bits >= 128
    temp_password = secrets.token_urlsafe(32)

    # Hash the temporary password
    hashed_password = get_password_hash(temp_password)

    try:
        # Create User
        db_user = User(
            email=email,
            full_name=employee_data.full_name,
            role="EMPLOYEE",
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
        from datetime import datetime
        hire_date_parsed = None
        if employee_data.hire_date:
            try:
                hire_date_parsed = datetime.strptime(employee_data.hire_date, "%Y-%m-%d").date()
            except ValueError:
                pass

        db_profile = Profile(
            user_id=db_user.id,
            job_role=employee_data.job_role,
            department=employee_data.department,
            industry=employee_data.industry,
            years_of_experience=employee_data.years_of_experience,
            age=employee_data.age,
            gender=employee_data.gender,
            education_attainment=employee_data.education_attainment,
            marital_status=employee_data.marital_status,
            phone_number=employee_data.phone_number,
            hire_date=hire_date_parsed,
            target_daily_hours=employee_data.target_daily_hours,
            shift_start_time=employee_data.shift_start_time,
            shift_end_time=employee_data.shift_end_time,
            work_days=employee_data.working_days
        )
        db.add(db_profile)
        db.flush()

        # Create OrganizationMembership
        org_membership = OrganizationMembership(
            user_id=db_user.id,
            organization_id=organization_id,
            role="EMPLOYEE",
            status="APPROVED"
        )
        db.add(org_membership)

        # Handle optional team assignment
        team_id_raw = employee_data.team_id
        team_name = None
        team_id = None
        if team_id_raw is not None:
            try:
                team_id = UUID(team_id_raw)
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid team ID format"
                )
            # Verify team exists
            team = db.query(Team).filter(Team.id == team_id).first()
            if not team:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Team not found"
                )

            # Verify team belongs to manager's organization
            if team.organization_id != organization_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Team does not belong to your organization"
                )

            # Create TeamMembership (use current time, not db_user.created_at which may be naive)
            from datetime import datetime, timezone
            team_membership = TeamMembership(
                profile_id=db_profile.id,
                team_id=team.id,
                role="EMPLOYEE",
                joined_at=datetime.now(timezone.utc)
            )
            db.add(team_membership)
            team_name = team.name

        # Commit transaction
        db.commit()
        db.refresh(db_user)
        db.refresh(db_profile)

        # Get organization name for response
        organization = db.query(OrganizationMembership).join(
            OrganizationMembership.organization
        ).filter(
            OrganizationMembership.id == org_membership.id
        ).first()

        organization_name = None
        if organization and organization.organization:
            organization_name = organization.organization.name

        # Build response
        return EmployeeCreateResponse(
            id=db_user.id,
            email=db_user.email,
            full_name=db_user.full_name,
            is_active=db_user.is_active,
            role=db_user.role,
            approval_status=db_user.approval_status,
            must_change_password=db_user.must_change_password,
            temporary_password=temp_password,  # Return only once
            organization_id=organization_id,
            organization_name=organization_name,
            team_id=team_id,
            team_name=team_name
        )

    except Exception as e:
        db.rollback()
        raise e


@router.get("", response_model=list[EmployeeListResponse])
def list_employees(
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """List employees in manager's organization."""
    manager_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role == "MANAGER"
    ).all()

    if len(manager_memberships) == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have an approved MANAGER organization membership to list employees"
        )
    if len(manager_memberships) > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ambiguous organization: user has multiple approved MANAGER organization memberships"
        )

    organization_id = manager_memberships[0].organization_id

    # Scope to employees in teams managed by this manager, plus org employees
    # with no team membership (unassigned). Employees in another manager's team
    # must not be visible.
    managed_team_ids = [t.id for t in db.query(Team).filter(
        Team.manager_user_id == current_user.id,
        Team.organization_id == organization_id
    ).all()]
    managed_profile_ids = []
    if managed_team_ids:
        managed_profile_ids = [m[0] for m in db.query(TeamMembership.profile_id).filter(
            TeamMembership.team_id.in_(managed_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()]

    # Employee users with approved EMPLOYEE membership in manager's org
    employee_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.organization_id == organization_id,
        OrganizationMembership.role == "EMPLOYEE",
        OrganizationMembership.status == "APPROVED"
    ).all()

    result = []
    for mem in employee_memberships:
        user = db.query(User).filter(User.id == mem.user_id).first()
        if not user or user.role != "EMPLOYEE":
            continue

        # Clean team info via TeamMembership -> Team (first current membership)
        team_name = None
        team_id = None
        if user.profile:
            team_membership = db.query(TeamMembership).filter(
                TeamMembership.profile_id == user.profile.id,
                TeamMembership.left_at.is_(None)
            ).first()
            if team_membership:
                team = db.query(Team).filter(Team.id == team_membership.team_id).first()
                if team:
                    team_id = team.id
                    team_name = team.name

        result.append(EmployeeListResponse(
            id=user.id,
            full_name=user.full_name,
            email=user.email,
            is_active=user.is_active,
            team_id=team_id,
            team_name=team_name,
        ))

    return result




@router.get("/{employee_id}/work-sessions", response_model=List[SessionHistoryResponse])
def get_employee_work_sessions(
    employee_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Get work sessions for a specific employee (Admin or Manager)."""
    try:
        employee_uuid = UUID(employee_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid employee ID format")
    db_employee = verify_manager_or_admin_employee_access(db, current_user, employee_uuid)
    if not db_employee.profile:
        return []
    sessions = db.query(WorkSession).filter(
        WorkSession.profile_id == db_employee.profile.id,
        WorkSession.ended_at.isnot(None)
    ).order_by(WorkSession.ended_at.desc()).all()
    response_sessions = []
    for session in sessions:
        duration_minutes = int((session.ended_at - session.started_at).total_seconds() / 60) if session.ended_at else None
        breaks = db.query(Break).filter(Break.work_session_id == session.id).order_by(Break.started_at).all()
        breaks_response = []
        for break_ in breaks:
            break_duration = int((break_.ended_at - break_.started_at).total_seconds() / 60) if break_.ended_at else None
            breaks_response.append(SessionHistoryBreak(
                id=break_.id, break_type=break_.break_type, started_at=break_.started_at,
                ended_at=break_.ended_at, duration_minutes=break_duration
            ))
        tasks = db.query(Task).filter(Task.work_session_id == session.id).all()
        tasks_response = []
        for task in tasks:
            tasks_response.append(SessionHistoryTask(
                id=task.id, title=task.title, description=task.description,
                category=task.category, priority=task.priority, status=task.status,
                estimated_minutes=task.estimated_minutes, actual_minutes=task.actual_minutes,
                started_at=task.started_at, ended_at=task.ended_at
            ))
        response_sessions.append(SessionHistoryResponse(
            id=session.id, started_at=session.started_at, ended_at=session.ended_at,
            duration_minutes=duration_minutes, breaks=breaks_response, tasks=tasks_response
        ))
    return response_sessions


@router.get("/{employee_id}/manager", response_model=EmployeeListResponse)
def get_employee_manager(
    employee_id: str,
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """Get employee detail for manager (manager-only, same org scoping as list/deactivate)."""
    try:
        employee_uuid = UUID(employee_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid employee ID format"
        )
    manager_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role == "MANAGER"
    ).all()
    if len(manager_memberships) == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have an approved MANAGER organization membership"
        )
    if len(manager_memberships) > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ambiguous organization: user has multiple approved MANAGER organization memberships"
        )
    organization_id = manager_memberships[0].organization_id
    db_employee = db.query(User).filter(User.id == employee_uuid).first()
    if not db_employee:
        profile = db.query(Profile).filter(Profile.id == employee_uuid).first()
        if profile and profile.user:
            db_employee = profile.user
    if not db_employee or db_employee.role != "EMPLOYEE":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")
    membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_employee.id,
        OrganizationMembership.organization_id == organization_id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role == "EMPLOYEE"
    ).first()
    if not membership:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Employee does not belong to your organization")
    team_name = None
    team_id = None
    if db_employee.profile:
        tm = db.query(TeamMembership).filter(
            TeamMembership.profile_id == db_employee.profile.id,
            TeamMembership.left_at.is_(None)
        ).first()
        if tm:
            team = db.query(Team).filter(Team.id == tm.team_id).first()
            if team:
                team_id = team.id
                team_name = team.name
    return EmployeeListResponse(
        id=db_employee.id,
        full_name=db_employee.full_name,
        email=db_employee.email,
        is_active=db_employee.is_active,
        team_id=team_id,
        team_name=team_name,
    )


@router.patch("/{employee_id}/deactivate", response_model=UserResponse)
def deactivate_employee(
    employee_id: str,
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Deactivate an employee by a manager (set is_active=False).

    Authorization:
    - Must be a MANAGER
    - Manager must have exactly one approved MANAGER organization membership

    Validates:
    - Target employee exists
    - Target employee has role=EMPLOYEE
    - Target employee has approved EMPLOYEE OrganizationMembership in same organization as manager
    - Managers and admins cannot be deactivated through this endpoint

    Action:
    - Sets User.is_active = False
    - Preserves all other data (Profile, OrganizationMembership, historical data)
    """
    # Normalize employee ID format
    try:
        employee_uuid = UUID(employee_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid employee ID format"
        )

    # Find the target employee
    db_employee = db.query(User).filter(User.id == employee_uuid).first()
    if not db_employee:
        profile = db.query(Profile).filter(Profile.id == employee_uuid).first()
        if profile and profile.user:
            db_employee = profile.user
    if not db_employee:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Employee not found"
        )

    # Validate target is an employee (not manager/admin)
    if db_employee.role != "EMPLOYEE":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Can only deactivate employees with role=EMPLOYEE"
        )

    # Resolve manager's organization (same logic as in create_employee)
    manager_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role == "MANAGER"
    ).all()

    if len(manager_memberships) == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have an approved MANAGER organization membership to deactivate an employee"
        )
    if len(manager_memberships) > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ambiguous organization: user has multiple approved MANAGER organization memberships"
        )

    manager_organization_id = manager_memberships[0].organization_id

    # Validate employee belongs to manager's organization
    employee_membership = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == db_employee.id,
        OrganizationMembership.organization_id == manager_organization_id,
        OrganizationMembership.role == "EMPLOYEE",
        OrganizationMembership.status == "APPROVED"
    ).first()

    if not employee_membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Employee does not belong to your organization or is not an active employee"
        )

    # Deactivate the employee (set is_active=False)
    db_employee.is_active = False
    db.add(db_employee)
    db.commit()
    db.refresh(db_employee)

    return db_employee


def verify_manager_or_admin_employee_access(db: Session, current_user: User, employee_id: UUID) -> User:
    db_employee = db.query(User).filter(User.id == employee_id).first()
    if not db_employee:
        profile = db.query(Profile).filter(Profile.id == employee_id).first()
        if profile and profile.user:
            db_employee = profile.user
    if not db_employee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")

    user_role = (current_user.role or "").strip().upper()
    admin_org_ids = get_organization_ids_for_user(db, current_user.id) if user_role == "ADMIN" else []
    global_admin_branch = (user_role == "ADMIN" and not admin_org_ids)
    emp_org_mems = get_organization_ids_for_user(db, db_employee.id)
    org_matched = any(org_id in admin_org_ids for org_id in emp_org_mems) if user_role == "ADMIN" else False

    print(f"[AUTH_DIAG] user_id={current_user.id} normalized_role={user_role} org_membership_count={len(admin_org_ids) if user_role == 'ADMIN' else 'N/A'} global_admin_branch={global_admin_branch} org_matched={org_matched}")

    if user_role == "ADMIN":
        if admin_org_ids:
            emp_membership = db.query(OrganizationMembership).filter(
                OrganizationMembership.user_id == db_employee.id,
                OrganizationMembership.organization_id.in_(admin_org_ids),
                OrganizationMembership.status == "APPROVED"
            ).first()
            if not emp_membership:
                print(f"[AUTH_DIAG] DECISION: REJECTED (Reason: Employee does not belong to admin's organization, org-scoped admin restriction)")
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Employee does not belong to your organization")
        print(f"[AUTH_DIAG] DECISION: APPROVED (Admin access granted)")
    elif user_role == "MANAGER":
        manager_memberships = db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == current_user.id,
            OrganizationMembership.status == "APPROVED",
            OrganizationMembership.role == "MANAGER"
        ).all()
        if not manager_memberships:
            print(f"[AUTH_DEBUG] Manager 403: user {current_user.id} has no approved MANAGER organization memberships")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User must have an approved MANAGER organization membership")
        org_ids = [m.organization_id for m in manager_memberships]

        # Check organization membership (approved, matching org_ids)
        emp_membership = db.query(OrganizationMembership).filter(
            OrganizationMembership.user_id == db_employee.id,
            OrganizationMembership.organization_id.in_(org_ids),
            OrganizationMembership.status == "APPROVED"
        ).first()

        # Check if employee is in a team managed by this manager
        manager_team_ids = [t.id for t in db.query(Team).filter(
            Team.manager_user_id == current_user.id,
            Team.organization_id.in_(org_ids)
        ).all()]

        is_in_manager_team = False
        if db_employee.profile and manager_team_ids:
            team_mem = db.query(TeamMembership).filter(
                TeamMembership.profile_id == db_employee.profile.id,
                TeamMembership.team_id.in_(manager_team_ids),
                TeamMembership.left_at.is_(None)
            ).first()
            if team_mem:
                is_in_manager_team = True

        # A manager may only access employees in their own organization AND their own managed teams.
        # Org membership alone is not sufficient; otherwise any org member bypasses team scoping.
        is_self = db_employee.id == current_user.id
        if not emp_membership or (not is_in_manager_team and not is_self):
            print(f"[AUTH_DEBUG] Manager 403: Employee {db_employee.id} is not in manager's team scope (emp_membership={emp_membership is not None}, is_in_manager_team={is_in_manager_team})")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Employee does not belong to your team")

        if not db_employee.profile:
            db_profile = Profile(
                user_id=db_employee.id,
                target_daily_hours=8,
                shift_start_time="09:00",
                shift_end_time="17:00",
                work_days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
            )
            db.add(db_profile)
            db.commit()
            db.refresh(db_employee)
    else:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized role")
    return db_employee


@router.get("/{employee_id}/live-status")
def get_employee_live_status(
    employee_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Get live shift status, active session, breaks, tasks, and schedule for an employee (Manager or Admin)."""
    try:
        employee_uuid = UUID(employee_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid employee ID format")

    db_employee = verify_manager_or_admin_employee_access(db, current_user, employee_uuid)
    profile = db_employee.profile
    if not profile:
        profile = Profile(
            user_id=db_employee.id,
            target_daily_hours=8,
            shift_start_time="09:00",
            shift_end_time="17:00",
            work_days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        )
        db.add(profile)
        db.commit()
        db.refresh(db_employee)
        profile = db_employee.profile

    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    active_break = None
    completed_breaks = []
    tasks = []

    if active_session:
        active_break = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.ended_at.is_(None)
        ).first()

        breaks = db.query(Break).filter(Break.work_session_id == active_session.id).all()
        for b in breaks:
            completed_breaks.append({
                "id": str(b.id),
                "break_type": b.break_type,
                "started_at": b.started_at.isoformat() if b.started_at else None,
                "ended_at": b.ended_at.isoformat() if b.ended_at else None,
            })

        t_list = db.query(Task).filter(Task.work_session_id == active_session.id).all()
        for t in t_list:
            tasks.append({
                "id": str(t.id),
                "title": t.title,
                "category": t.category,
                "status": t.status,
                "started_at": t.started_at.isoformat() if t.started_at else None,
                "ended_at": t.ended_at.isoformat() if t.ended_at else None,
            })

    status_category = "Not Started"
    if active_break:
        b_type = active_break.break_type
        if b_type == 'break1':
            status_category = "Break 1"
        elif b_type == 'break2':
            status_category = "Break 2"
        elif b_type == 'lunch':
            status_category = "Lunch"
        else:
            status_category = "Break"
    elif active_session:
        active_meeting = next((t for t in tasks if t['category'] == 'Meeting' and t['status'] == 'IN_PROGRESS'), None)
        if active_meeting:
            status_category = "Meeting"
        else:
            status_category = "Working / On Shift"
    else:
        last_session = db.query(WorkSession).filter(
            WorkSession.profile_id == profile.id
        ).order_by(WorkSession.started_at.desc()).first()
        if last_session and last_session.ended_at:
            status_category = "Shift Ended"
        else:
            status_category = "Not Started"

    print(f"[SHIFT_PREVIEW_DEBUG] get_employee_live_status: employee_id={db_employee.id}, email={db_employee.email}, active_session_exists={active_session is not None}, active_session_id={active_session.id if active_session else None}, started_at={active_session.started_at if active_session else None}, status_category={status_category}")

    return {
        "user_id": str(db_employee.id),
        "full_name": db_employee.full_name,
        "email": db_employee.email,
        "role": db_employee.role,
        "profile_image_url": profile.profile_image_url,
        "active_work_session": {
            "id": str(active_session.id),
            "started_at": active_session.started_at.isoformat(),
        } if active_session else None,
        "active_break": {
            "id": str(active_break.id),
            "break_type": active_break.break_type,
            "started_at": active_break.started_at.isoformat(),
        } if active_break else None,
        "completed_breaks": completed_breaks,
        "tasks": tasks,
        "schedule": {
            "shift_start_time": profile.shift_start_time.strftime("%H:%M") if hasattr(profile.shift_start_time, "strftime") else (str(profile.shift_start_time)[:5] if profile.shift_start_time else None),
            "shift_end_time": profile.shift_end_time.strftime("%H:%M") if hasattr(profile.shift_end_time, "strftime") else (str(profile.shift_end_time)[:5] if profile.shift_end_time else None),
            "work_days": profile.work_days,
        },
        "status_category": status_category,
    }


@router.get("/{employee_id}", response_model=UserResponse)
def get_employee(
    employee_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """Get details for a specific employee (Admin or Manager)."""
    try:
        employee_uuid = UUID(employee_id)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid employee ID format")
    db_employee = verify_manager_or_admin_employee_access(db, current_user, employee_uuid)
    return db_employee
