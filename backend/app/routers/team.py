from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
import os
import hashlib
import hmac
from datetime import datetime, timezone, timedelta
from pydantic import BaseModel
import secrets

from ..database import get_db
from ..auth.security import get_current_manager_only_user, get_current_active_user, get_current_admin_user, log_system_activity, pwd_context, verify_password, get_organization_ids_for_user, should_include_test_data
from ..models import User, Team, TeamMembership, Profile, WorkSession, Break, TeamInvitation, Notification, Group, Organization, OrganizationMembership
from ..schemas.auth import UserResponse
from ..schemas.work import WorkSessionStartResponse, BreakResponse
from ..schemas.team import (
    TeamCreateRequest,
    TeamResponse,
    TeamMemberResponse,
    TeamInvitationCreateRequest,
    TeamInvitationResponse,
    TeamInvitationListResponse,
    NotificationResponse,
    InvitationValidationResponse,
    UserSearchResult,
)
from ..services.email_service import EmailService
from ..services.notification_dispatch_service import NotificationDispatchService

router = APIRouter(
    prefix="/teams",
    tags=["teams"],
    responses={404: {"description": "Not found"}},
)


class TeamMemberResponse(UserResponse):
    """Extended user response for team members with additional team-related info."""
    profile_id: Optional[uuid.UUID] = None


class TeamMemberWithActivity(UserResponse):
    """Team member data with current work and break activity."""
    profile_id: Optional[uuid.UUID] = None
    active_work_session: Optional[WorkSessionStartResponse] = None
    active_break: Optional[BreakResponse] = None
    team_name: Optional[str] = None
    manager_name: Optional[str] = None


class TeamUpdateRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None

class TeamManagerUpdateRequest(BaseModel):
    manager_user_id: Optional[uuid.UUID] = None


class TeamBasicInfo(BaseModel):
    """Basic team information for group/team listings."""
    id: uuid.UUID
    name: str
    description: Optional[str] = None
    member_count: int
    is_active: bool
    manager_id: Optional[uuid.UUID] = None
    manager_name: Optional[str] = None


@router.get("/my-members", response_model=List[TeamMemberResponse])
def get_my_team_members(
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Get the current manager's team members.
    Only accessible by MANAGER (not ADMIN).
    Returns list of team members with basic user information.
    """
    # Get the manager's team
    manager_team = db.query(Team).filter(Team.manager_user_id == current_user.id).first()

    if not manager_team:
        # Manager doesn't manage any team
        return []

    include_test = should_include_test_data(db, current_user)

    # Get current team members (where left_at is NULL)
    team_memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id == manager_team.id,
        TeamMembership.left_at.is_(None)
    ).all()

    # Get the user profiles and then the users
    members = []
    for membership in team_memberships:
        profile = db.query(Profile).filter(Profile.id == membership.profile_id).first()
        if profile:
            if not include_test and profile.is_test_data:
                continue
            user = db.query(User).filter(User.id == profile.user_id).first()
            if user:
                member_data = TeamMemberResponse.model_validate(user)
                member_data.profile_id = profile.id
                members.append(member_data)

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_MEMBERS_ACCESSED",
        action_details={"team_id": str(manager_team.id) if manager_team else None, "member_count": len(members)}
    )

    return members


@router.get("/{team_id}/activity-summary")
def get_team_activity_summary(
    team_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get bulk activity summary for a team, returning members and their work sessions and breaks in one efficient query.
    """
    team = db.query(Team).filter(Team.id == team_id, Team.is_active == True).first()
    if not team:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Team not found")

    if current_user.role.upper() == "MANAGER" and team.manager_user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this team")
    elif current_user.role.upper() == "ADMIN":
        admin_org_ids = get_organization_ids_for_user(db, current_user.id)
        if team.organization_id not in admin_org_ids:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized for this team")
    elif current_user.role.upper() != "MANAGER" and current_user.role.upper() != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    include_test = should_include_test_data(db, current_user)
    memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id == team.id,
        TeamMembership.left_at.is_(None)
    ).all()

    profile_ids = []
    profile_map = {}
    for m in memberships:
        profile = db.query(Profile).filter(Profile.id == m.profile_id).first()
        if profile:
            if not include_test and profile.is_test_data:
                continue
            user = db.query(User).filter(User.id == profile.user_id).first()
            if user:
                profile_ids.append(profile.id)
                profile_map[profile.id] = {
                    "employee_id": str(user.id),
                    "id": str(user.id),
                    "profile_id": str(profile.id),
                    "full_name": user.full_name,
                    "email": user.email,
                    "work_sessions": []
                }

    if profile_ids:
        sessions = db.query(WorkSession).filter(
            WorkSession.profile_id.in_(profile_ids)
        ).order_by(WorkSession.started_at.desc()).all()

        session_ids = [s.id for s in sessions]
        breaks_map = {}
        if session_ids:
            breaks = db.query(Break).filter(Break.work_session_id.in_(session_ids)).all()
            for b in breaks:
                breaks_map.setdefault(b.work_session_id, []).append({
                    "id": str(b.id),
                    "started_at": b.started_at.isoformat() if b.started_at else None,
                    "ended_at": b.ended_at.isoformat() if b.ended_at else None,
                    "break_type": b.break_type,
                })

        for s in sessions:
            profile = db.query(Profile).filter(Profile.id == s.profile_id).first()
            if profile and profile.id in profile_map:
                duration_mins = 0
                if s.started_at and s.ended_at:
                    duration_mins = int((s.ended_at - s.started_at).total_seconds() / 60)
                elif s.started_at:
                    duration_mins = int((datetime.now(timezone.utc) - s.started_at).total_seconds() / 60)

                profile_map[profile.id]["work_sessions"].append({
                    "id": str(s.id),
                    "started_at": s.started_at.isoformat() if s.started_at else None,
                    "ended_at": s.ended_at.isoformat() if s.ended_at else None,
                    "duration_minutes": max(0, duration_mins),
                    "status": "completed" if s.ended_at else "active",
                    "breaks": breaks_map.get(s.id, [])
                })

    return list(profile_map.values())


@router.get("/my-team-view", response_model=List[TeamMemberWithActivity])
def get_my_team_view(
    request: Request,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get team view information based on user role.
    Accessible by all authenticated users.
    Returns appropriate team information based on user's role:
    - MANAGER: Their team members with activity status
    - EMPLOYEE: Their team basic info (if part of a team)
    - ADMIN: All teams with basic info (administrative oversight)
    """
    team = None
    if current_user.role.upper() == "MANAGER":
        team = db.query(Team).filter(Team.manager_user_id == current_user.id).first()
    elif current_user.role.upper() == "EMPLOYEE" and current_user.profile:
        membership = db.query(TeamMembership).filter(TeamMembership.profile_id == current_user.profile.id, TeamMembership.left_at == None).first()
        if membership:
            team = db.query(Team).filter(Team.id == membership.team_id).first()

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="TEAM_VIEW_ACCESSED",
        category="TEAM",
        target_type="team" if team else "organization",
        target_id=str(team.id) if team else None,
        target_display_label=team.name if team else "All Teams / Organization",
        outcome="SUCCESS",
        summary=f"Accessed team view for {team.name if team else 'organization'}",
        action_details={"user_role": current_user.role, "team_id": str(team.id) if team else None}
    )

    # Handle different user roles
    if current_user.role.upper() == "MANAGER":
        # MANAGER: Return their team members with activity status (existing behavior)
        # Get the manager's team
        manager_team = db.query(Team).filter(Team.manager_user_id == current_user.id).first()

        if not manager_team:
            # Manager doesn't manage any team
            return []

        include_test = should_include_test_data(db, current_user)

        # Get current team members (where left_at is NULL)
        team_memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id == manager_team.id,
            TeamMembership.left_at.is_(None)
        ).all()

        # Get the user profiles and then the users
        members_with_activity = []
        for membership in team_memberships:
            profile = db.query(Profile).filter(Profile.id == membership.profile_id).first()
            if profile:
                if not include_test and profile.is_test_data:
                    continue
                user = db.query(User).filter(User.id == profile.user_id).first()
                if user:
                    # Check for active work session for this profile
                    active_work_session = db.query(WorkSession).filter(
                        WorkSession.profile_id == profile.id,
                        WorkSession.ended_at.is_(None)
                    ).first()

                    active_break = None
                    if active_work_session:
                        # Check for active break in this work session
                        active_break = db.query(Break).filter(
                            Break.work_session_id == active_work_session.id,
                            Break.ended_at.is_(None)
                        ).first()

                    # Create the response object using model_validate
                    member_data = TeamMemberWithActivity.model_validate(user)
                    member_data.profile_id = profile.id
                    member_data.active_work_session = WorkSessionStartResponse.from_orm(active_work_session) if active_work_session else None
                    member_data.active_break = BreakResponse.from_orm(active_break) if active_break else None
                    member_data.team_name = manager_team.name
                    member_data.manager_name = current_user.full_name
                    members_with_activity.append(member_data)

        return members_with_activity

    elif current_user.role.upper() == "EMPLOYEE":
        # EMPLOYEE: Return their team basic info (if part of a team)
        # Get the employee's profile
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            return []

        # Get the employee's team memberships (where left_at is NULL)
        team_memberships = db.query(TeamMembership).filter(
            TeamMembership.profile_id == profile.id,
            TeamMembership.left_at.is_(None)
        ).all()

        if not team_memberships:
            # Employee is not part of any team
            return []

        # For simplicity, if employee is part of multiple teams, return the first one's members
        # In a more complex system, we might want to handle this differently
        team_membership = team_memberships[0]
        team = db.query(Team).filter(Team.id == team_membership.team_id).first()
        if not team:
            return []

        # Get current team members (where left_at is NULL) - basic info only, no activity status
        team_memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.left_at.is_(None)
        ).all()

        # Get basic team member info (without activity status for privacy)
        members_basic = []
        for membership in team_memberships:
            profile = db.query(Profile).filter(Profile.id == membership.profile_id).first()
            if profile:
                user = db.query(User).filter(User.id == profile.user_id).first()
                if user:
                    # Get manager of the team
                    manager = db.query(User).filter(User.id == team.manager_user_id).first()
                    manager_name = manager.full_name if manager else None
                    # Create response object with model_validate
                    member_data = TeamMemberWithActivity.model_validate(user)
                    member_data.active_work_session = None
                    member_data.active_break = None
                    member_data.team_name = team.name
                    member_data.manager_name = manager_name
                    members_basic.append(member_data)

        return members_basic

    elif current_user.role == "ADMIN":
        # ADMIN: Return all teams with active session/break status for org-wide monitoring
        admin_org_ids = get_organization_ids_for_user(db, current_user.id)
        teams = db.query(Team).filter(
            Team.is_active == True,
            Team.organization_id.in_(admin_org_ids) if admin_org_ids else True
        ).all()

        members_with_activity = []

        for team in teams:
            team_memberships = db.query(TeamMembership).filter(
                TeamMembership.team_id == team.id,
                TeamMembership.left_at.is_(None)
            ).all()

            for membership in team_memberships:
                profile = db.query(Profile).filter(Profile.id == membership.profile_id).first()
                if profile:
                    user = db.query(User).filter(User.id == profile.user_id).first()
                    if user:
                        manager = db.query(User).filter(User.id == team.manager_user_id).first()
                        manager_name = manager.full_name if manager else None

                        active_work_session = db.query(WorkSession).filter(
                            WorkSession.profile_id == profile.id,
                            WorkSession.ended_at.is_(None)
                        ).first()

                        active_break = None
                        if active_work_session:
                            active_break = db.query(Break).filter(
                                Break.work_session_id == active_work_session.id,
                                Break.ended_at.is_(None)
                            ).first()

                        member_data = TeamMemberWithActivity.model_validate(user)
                        member_data.active_work_session = WorkSessionStartResponse.from_orm(active_work_session) if active_work_session else None
                        member_data.active_break = BreakResponse.from_orm(active_break) if active_break else None
                        member_data.team_name = team.name
                        member_data.manager_name = manager_name
                        members_with_activity.append(member_data)

        return members_with_activity

    else:
        # Other roles (e.g., GUEST) - return empty list
        return []


@router.get("/my-teams", response_model=List[TeamBasicInfo])
def get_my_teams(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get teams information for the current user.
    Accessible by all authenticated users.
    Returns different information based on user role:
    - MANAGER: Teams they manage
    - EMPLOYEE: Teams they belong to
    - ADMIN: All teams (administrative oversight)
    """
    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="MY_TEMS_ACCESSED",
        action_details={"user_role": current_user.role}
    )

    teams_info = []

    if current_user.role == "MANAGER":
        # MANAGER: Get teams they manage
        managed_teams = db.query(Team).filter(
            Team.manager_user_id == current_user.id,
            Team.is_active == True
        ).all()

        for team in managed_teams:
            # Get member count
            member_count = db.query(TeamMembership).filter(
                TeamMembership.team_id == team.id,
                TeamMembership.left_at.is_(None)
            ).count()

            # Get manager name
            manager = db.query(User).filter(User.id == team.manager_user_id).first()
            manager_name = manager.full_name if manager else None

            team_info = TeamBasicInfo(
                id=team.id,
                name=team.name,
                description=team.description,
                member_count=member_count,
                is_active=team.is_active,
                manager_id=team.manager_user_id,
                manager_name=manager_name
            )
            teams_info.append(team_info)

    elif current_user.role == "EMPLOYEE":
        # EMPLOYEE: Get teams they belong to
        # Get employee's profile
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            return []

        # Get team memberships (where left_at is NULL)
        team_memberships = db.query(TeamMembership).filter(
            TeamMembership.profile_id == profile.id,
            TeamMembership.left_at.is_(None)
        ).all()

        for membership in team_memberships:
            team = db.query(Team).filter(Team.id == membership.team_id).first()
            if team and team.is_active:
                # Get member count
                member_count = db.query(TeamMembership).filter(
                    TeamMembership.team_id == team.id,
                    TeamMembership.left_at.is_(None)
                ).count()

                # Get manager name
                manager = db.query(User).filter(User.id == team.manager_user_id).first()
                manager_name = manager.full_name if manager else None

                team_info = TeamBasicInfo(
                    id=team.id,
                    name=team.name,
                    description=team.description,
                    member_count=member_count,
                    is_active=team.is_active,
                    manager_id=team.manager_user_id,
                    manager_name=manager_name
                )
                teams_info.append(team_info)

    elif current_user.role == "ADMIN":
        # ADMIN: Get all teams
        teams = db.query(Team).filter(Team.is_active == True).all()

        for team in teams:
            # Get member count
            member_count = db.query(TeamMembership).filter(
                TeamMembership.team_id == team.id,
                TeamMembership.left_at.is_(None)
            ).count()

            # Get manager name
            manager = db.query(User).filter(User.id == team.manager_user_id).first()
            manager_name = manager.full_name if manager else None

            team_info = TeamBasicInfo(
                id=team.id,
                name=team.name,
                description=team.description,
                member_count=member_count,
                is_active=team.is_active,
                manager_id=team.manager_user_id,
                manager_name=manager_name
            )
            teams_info.append(team_info)

    return teams_info


@router.post("", response_model=TeamResponse, status_code=status.HTTP_201_CREATED)
def create_team(
    team_data: TeamCreateRequest,
    request: Request,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Create a new team. Only MANAGER or ADMIN users who have been approved can create teams.
    Creator must already be a global MANAGER or ADMIN (promotion occurs via admin approval).

    Authorization:
    - User must be a MANAGER or ADMIN
    - User account must be approved
    - User must not already manage a team
    """
    if current_user.role not in ["MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only managers and admins can create teams",
        )

    # Verify approval status
    if current_user.approval_status != "APPROVED":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account must be approved before creating a team",
        )

    # Check if user already manages a team
    existing_team = db.query(Team).filter(Team.manager_user_id == current_user.id).first()
    if existing_team:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User already manages a team",
        )

    # Resolve organization from approved OrganizationMembership (MANAGER or ADMIN)
    org_memberships = db.query(OrganizationMembership).filter(
        OrganizationMembership.user_id == current_user.id,
        OrganizationMembership.status == "APPROVED",
        OrganizationMembership.role.in_(["MANAGER", "ADMIN"])
    ).all()
    if len(org_memberships) == 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have an approved organization membership (MANAGER or ADMIN) to create a team",
        )
    if len(org_memberships) > 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ambiguous organization: user has multiple approved organization memberships",
        )
    organization_id = org_memberships[0].organization_id

    # Check if team name is unique
    duplicate_name = db.query(Team).filter(Team.name == team_data.name).first()
    if duplicate_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Team name already exists",
        )

    # Create team with current user as manager and resolved organization
    new_team = Team(
        name=team_data.name,
        description=team_data.description,
        manager_user_id=current_user.id,
        organization_id=organization_id,
        is_active=True,
    )
    db.add(new_team)
    db.flush()

    # Create team membership for the creator as MANAGER
    profile = current_user.profile
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User must have a profile to create a team",
        )

    membership = TeamMembership(
        profile_id=profile.id,
        team_id=new_team.id,
        role="MANAGER",
        joined_at=datetime.now(timezone.utc),
    )
    db.add(membership)

    db.commit()
    db.refresh(new_team)

    # Log activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        request=request,
        action_type="TEAM_CREATED",
        category="TEAM",
        target_type="team",
        target_id=str(new_team.id),
        target_display_label=new_team.name,
        outcome="SUCCESS",
        summary=f"Created team {new_team.name}",
        action_details={"team_id": str(new_team.id), "team_name": new_team.name},
    )

    # Build response
    return TeamResponse(
        id=new_team.id,
        name=new_team.name,
        description=new_team.description,
        manager_id=new_team.manager_user_id,
        manager_name=current_user.full_name,
        member_count=1,  # Just the creator
        is_active=new_team.is_active,
        created_at=new_team.created_at,
        updated_at=new_team.updated_at,
    )


@router.get("/me", response_model=Optional[TeamResponse])
def get_my_team(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get the current user's managed team (if they are a manager) OR their membership team (if employee).
    Returns None if user has no team.
    """
    team = None

    if current_user.role == "MANAGER":
        # Manager: get the team they manage
        team = db.query(Team).filter(Team.manager_user_id == current_user.id).first()
    elif current_user.role == "EMPLOYEE":
        # Employee: get their team membership
        if current_user.profile:
            membership = db.query(TeamMembership).filter(
                TeamMembership.profile_id == current_user.profile.id,
                TeamMembership.left_at.is_(None),
            ).first()
            if membership:
                team = db.query(Team).filter(Team.id == membership.team_id).first()

    if not team:
        return None

    # Count members
    member_count = db.query(TeamMembership).filter(
        TeamMembership.team_id == team.id,
        TeamMembership.left_at.is_(None),
    ).count()

    # Get manager
    manager = db.query(User).filter(User.id == team.manager_user_id).first()

    return TeamResponse(
        id=team.id,
        name=team.name,
        description=team.description,
        manager_id=team.manager_user_id,
        manager_name=manager.full_name if manager else "Unknown",
        member_count=member_count,
        is_active=team.is_active,
        created_at=team.created_at,
        updated_at=team.updated_at,
    )


@router.get("/{team_id}", response_model=TeamResponse)
def get_team_detail(
    team_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get details for a specific team.

    Authorization:
    - Manager of the team, ADMIN, or current member
    """
    # Parse team ID
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    # Check authorization
    is_manager = team.manager_user_id == current_user.id
    is_admin = current_user.role == "ADMIN"
    is_member = False

    if current_user.role == "EMPLOYEE" and current_user.profile:
        is_member = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.profile_id == current_user.profile.id,
            TeamMembership.left_at.is_(None),
        ).first() is not None

    if not (is_manager or is_admin or is_member):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this team",
        )

    # Count members
    member_count = db.query(TeamMembership).filter(
        TeamMembership.team_id == team.id,
        TeamMembership.left_at.is_(None),
    ).count()

    manager = db.query(User).filter(User.id == team.manager_user_id).first()

    return TeamResponse(
        id=team.id,
        name=team.name,
        description=team.description,
        manager_id=team.manager_user_id,
        manager_name=manager.full_name if manager else "Unknown",
        member_count=member_count,
        is_active=team.is_active,
        created_at=team.created_at,
        updated_at=team.updated_at,
    )


@router.get("/{team_id}/members", response_model=List[TeamMemberResponse])
def get_team_members(
    team_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Get members of a specific team.

    Authorization:
    - Manager of the team, ADMIN, or current member
    """
    # Parse team ID
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    # Check authorization
    is_manager = team.manager_user_id == current_user.id
    is_admin = current_user.role == "ADMIN"
    is_member = False

    if current_user.role == "EMPLOYEE" and current_user.profile:
        is_member = db.query(TeamMembership).filter(
            TeamMembership.team_id == team.id,
            TeamMembership.profile_id == current_user.profile.id,
            TeamMembership.left_at.is_(None),
        ).first() is not None

    if not (is_manager or is_admin or is_member):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this team",
        )

    # Get current members
    memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id == team.id,
        TeamMembership.left_at.is_(None),
    ).all()

    members = []
    for membership in memberships:
        profile = db.query(Profile).filter(Profile.id == membership.profile_id).first()
        if profile:
            user = db.query(User).filter(User.id == profile.user_id).first()
            if user:
                members.append(user)

    return members


@router.get("/{team_id}/search-users", response_model=List[UserSearchResult])
def search_users_for_invitation(
    team_id: str,
    q: str = Query(..., min_length=2, max_length=100),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Search for users to invite to a team.

    Authorization:
    - Must be the manager of the team

    Returns users matching the search query with their invitation status.
    Excludes:
    - The team manager themselves
    - Users already on the team
    - Users with pending invitations
    """
    # Parse team ID
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    # Verify team exists
    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    # Check authorization - only manager can search
    if team.manager_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the team manager can search for users to invite",
        )

    # Search users by name or email
    search_term = f"%{q.lower()}%"
    users = db.query(User).filter(
        (User.full_name.ilike(search_term)) |
        (User.email.ilike(search_term)),
        User.id != current_user.id,  # Exclude self
    ).limit(20).all()

    results = []
    for user in users:
        # Check if user is already a member
        is_member = False
        if user.profile:
            is_member = db.query(TeamMembership).filter(
                TeamMembership.team_id == team.id,
                TeamMembership.profile_id == user.profile.id,
            ).first() is not None

        if is_member:
            results.append(UserSearchResult(
                id=user.id,
                full_name=user.full_name,
                email=user.email,
                status="already_member",
            ))
            continue

        # Check if invitation is pending
        pending_invite = db.query(TeamInvitation).filter(
            TeamInvitation.team_id == team.id,
            TeamInvitation.email == user.email.lower(),
            TeamInvitation.status == "PENDING",
        ).first()

        if pending_invite:
            results.append(UserSearchResult(
                id=user.id,
                full_name=user.full_name,
                email=user.email,
                status="pending_invitation",
            ))
            continue

        # User is available for invitation
        results.append(UserSearchResult(
            id=user.id,
            full_name=user.full_name,
            email=user.email,
            status="available",
        ))

    return results


@router.post("/{team_id}/invitations", response_model=TeamInvitationResponse, status_code=status.HTTP_201_CREATED)
def create_invitation(
    team_id: str,
    invite_data: TeamInvitationCreateRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Send an invitation to join a team.

    Authorization:
    - Must be the manager of the team
    """
    # Parse team ID
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    # Check authorization - only manager can invite
    if team.manager_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the team manager can send invitations",
        )

    # Normalize email
    normalized_email = invite_data.email.lower()

    # Check for existing pending invitation
    existing = db.query(TeamInvitation).filter(
        TeamInvitation.team_id == team.id,
        TeamInvitation.email == normalized_email,
        TeamInvitation.status == "PENDING",
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Pending invitation already exists for this email",
        )

    # Generate invitation token (using SHA-256 for high-entropy random token)
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode('utf-8')).hexdigest()
    token_prefix = token[:12]  # First 12 chars for lookup

    # Create invitation (expires in 7 days)
    expires_at = datetime.now(timezone.utc) + timedelta(days=7)
    invitation = TeamInvitation(
        team_id=team.id,
        email=normalized_email,
        invited_by=current_user.id,
        role=invite_data.role,
        token_prefix=token_prefix,
        token_hash=token_hash,
        status="PENDING",
        expires_at=expires_at,
    )
    db.add(invitation)
    db.flush()

    # Check if invited email already has an account
    invited_user = db.query(User).filter(User.email == normalized_email).first()

    if invited_user:
        # Create notification for existing user via NotificationDispatchService
        NotificationDispatchService.dispatch(
            db=db,
            recipient_user_id=invited_user.id,
            title=f"You've been invited to join {team.name}",
            message=f"{current_user.full_name} invited you to join {team.name} as {invite_data.role}.",
            notification_type="TEAM_INVITATION",
            priority="STANDARD",
            idempotency_key=f"team_invitation_{invitation.id}_{invited_user.id}",
            related_entity_id=invitation.id,
        )

    db.commit()
    db.refresh(invitation)

    # Send email
    email_service = EmailService()
    invitation_link = f"{os.getenv('FRONTEND_URL', 'http://localhost:3000')}/invitations/{token}"
    email_service.send_invitation_email(
        recipient_email=normalized_email,
        team_name=team.name,
        inviter_name=current_user.full_name,
        invitation_link=invitation_link,
        expires_at=expires_at,
        role=invite_data.role,
    )

    # Log activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_INVITATION_SENT",
        action_details={
            "team_id": str(team.id),
            "invited_email": normalized_email,
            "role": invite_data.role,
        },
    )

    # Return invitation (without token)
    return TeamInvitationResponse(
        id=invitation.id,
        team_id=invitation.team_id,
        team_name=team.name,
        email=invitation.email,
        invited_by=invitation.invited_by,
        inviter_name=current_user.full_name if current_user else "Unknown",
        role=invitation.role,
        status=invitation.status,
        expires_at=invitation.expires_at,
        created_at=invitation.created_at,
        accepted_at=invitation.accepted_at,
        declined_at=invitation.declined_at,
    )


@router.get("/{team_id}/invitations", response_model=TeamInvitationListResponse)
def list_invitations(
    team_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
    status_filter: Optional[str] = Query(None, alias="status"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """
    List invitations for a team.

    Authorization:
    - Must be the manager of the team
    """
    # Parse team ID
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    # Check authorization
    if team.manager_user_id != current_user.id and current_user.role != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view invitations for this team",
        )

    # Build query
    query = db.query(TeamInvitation).filter(TeamInvitation.team_id == team.id)

    if status_filter:
        query = query.filter(TeamInvitation.status == status_filter)

    total = query.count()
    invitations = query.order_by(TeamInvitation.created_at.desc()).offset(offset).limit(limit).all()

    # Build responses
    results = []
    for inv in invitations:
        inviter = db.query(User).filter(User.id == inv.invited_by).first()
        results.append(TeamInvitationResponse(
            id=inv.id,
            team_id=inv.team_id,
            team_name=team.name,
            email=inv.email,
            invited_by=inv.invited_by,
            inviter_name=inviter.full_name if inviter else "Unknown",
            role=inv.role,
            status=inv.status,
            expires_at=inv.expires_at,
            created_at=inv.created_at,
            accepted_at=inv.accepted_at,
            declined_at=inv.declined_at,
        ))

    return TeamInvitationListResponse(
        invitations=results,
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/invitations/validate/{token}", response_model=InvitationValidationResponse)
def validate_invitation(
    token: str,
    db: Session = Depends(get_db),
):
    """
    Validate an invitation token and return safe invitation information.

    Used during registration to verify token validity before account creation.

    Authorization:
    - No authentication required (token is the authorization)

    Returns:
    - valid: true if token is valid, pending, and not expired
    - invitation_id: UUID of the invitation
    - email: invited email address
    - team_name: name of the team
    - role: role in the team
    - expires_at: when the invitation expires
    """
    if not token or len(token) < 12:
        return InvitationValidationResponse(
            valid=False,
            message="Invalid token format"
        )

    token_prefix = token[:12]

    # Find pending invitations with matching token prefix
    candidate_invitations = db.query(TeamInvitation).filter(
        TeamInvitation.token_prefix == token_prefix,
        TeamInvitation.status == "PENDING",
    ).all()

    if not candidate_invitations:
        return InvitationValidationResponse(
            valid=False,
            message="Invitation not found"
        )

    # Verify plaintext token against bcrypt hash
    invitation = None
    for candidate in candidate_invitations:
        if verify_password(token, candidate.token_hash):
            invitation = candidate
            break

    if not invitation:
        return InvitationValidationResponse(
            valid=False,
            message="Invalid token"
        )

    # Check expiration
    if datetime.now(timezone.utc) > invitation.expires_at:
        invitation.status = "EXPIRED"
        db.add(invitation)
        db.commit()
        return InvitationValidationResponse(
            valid=False,
            message="Invitation has expired"
        )

    # Get team information
    team = db.query(Team).filter(Team.id == invitation.team_id).first()
    if not team:
        return InvitationValidationResponse(
            valid=False,
            message="Team not found"
        )

    # Log validation attempt
    log_system_activity(
        db=db,
        user_id=None,
        action_type="INVITATION_VALIDATED",
        action_details={
            "invitation_id": str(invitation.id),
            "team_id": str(team.id),
        }
    )

    return InvitationValidationResponse(
        valid=True,
        invitation_id=invitation.id,
        email=invitation.email,
        team_name=team.name,
        role=invitation.role,
        expires_at=invitation.expires_at,
    )


@router.post("/invitations/{invitation_id}/accept", status_code=status.HTTP_200_OK)
def accept_invitation(
    invitation_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Accept a team invitation.

    Authorization:
    - Must be the invited recipient (email must match)
    """
    # Parse invitation ID
    try:
        inv_id = uuid.UUID(invitation_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid invitation ID format",
        )

    invitation = db.query(TeamInvitation).filter(TeamInvitation.id == inv_id).first()
    if not invitation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invitation not found",
        )

    # Check authorization - email must match
    if invitation.email.lower() != current_user.email.lower():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to accept this invitation",
        )

    # Check if invitation is pending
    if invitation.status != "PENDING":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invitation is already {invitation.status.lower()}",
        )

    # Check if invitation has expired
    if datetime.now(timezone.utc) > invitation.expires_at:
        invitation.status = "EXPIRED"
        db.add(invitation)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invitation has expired",
        )

    # Accept invitation
    invitation.status = "ACCEPTED"
    invitation.accepted_at = datetime.now(timezone.utc)
    db.add(invitation)
    db.flush()

    # Create team membership
    profile = current_user.profile
    if profile:
        membership = TeamMembership(
            profile_id=profile.id,
            team_id=invitation.team_id,
            role="EMPLOYEE",
            joined_at=datetime.now(timezone.utc),
        )
        db.add(membership)

    db.commit()

    # Create notification for manager via NotificationDispatchService
    team = db.query(Team).filter(Team.id == invitation.team_id).first()
    if team:
        NotificationDispatchService.dispatch(
            db=db,
            recipient_user_id=team.manager_user_id,
            title="Invitation accepted",
            message=f"{current_user.full_name} accepted your invitation to join {team.name}.",
            notification_type="TEAM_INVITATION_ACCEPTED",
            priority="STANDARD",
            idempotency_key=f"team_invitation_accepted_{invitation.id}_{team.manager_user_id}",
            related_entity_id=invitation.id,
        )

    # Mark recipient's notification as actioned
    recipient_notif = db.query(Notification).filter(
        Notification.related_entity_id == invitation.id,
        Notification.type == "TEAM_INVITATION",
    ).first()
    if recipient_notif:
        recipient_notif.is_actioned = True
        recipient_notif.actioned_at = datetime.now(timezone.utc)
        db.add(recipient_notif)

    db.commit()

    # Send email to manager
    email_service = EmailService()
    email_service.send_acceptance_notification_email(
        manager_email=team.manager.email if team else "",
        employee_name=current_user.full_name,
        team_name=team.name if team else "",
    )

    # Log activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_INVITATION_ACCEPTED",
        action_details={
            "team_id": str(invitation.team_id),
            "invitation_id": str(invitation.id),
        },
    )

    return {"status": "accepted", "message": "Invitation accepted successfully"}


@router.post("/invitations/{invitation_id}/decline", status_code=status.HTTP_200_OK)
def decline_invitation(
    invitation_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Decline a team invitation.

    Authorization:
    - Must be the invited recipient (email must match)
    """
    # Parse invitation ID
    try:
        inv_id = uuid.UUID(invitation_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid invitation ID format",
        )

    invitation = db.query(TeamInvitation).filter(TeamInvitation.id == inv_id).first()
    if not invitation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invitation not found",
        )

    # Check authorization - email must match
    if invitation.email.lower() != current_user.email.lower():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to decline this invitation",
        )

    # Check if invitation is pending
    if invitation.status != "PENDING":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invitation is already {invitation.status.lower()}",
        )

    # Decline invitation
    invitation.status = "DECLINED"
    invitation.declined_at = datetime.now(timezone.utc)
    db.add(invitation)
    db.flush()

    # Create notification for manager via NotificationDispatchService
    team = db.query(Team).filter(Team.id == invitation.team_id).first()
    if team:
        NotificationDispatchService.dispatch(
            db=db,
            recipient_user_id=team.manager_user_id,
            title="Invitation declined",
            message=f"{current_user.email} declined your invitation to join {team.name}.",
            notification_type="TEAM_INVITATION_DECLINED",
            priority="STANDARD",
            idempotency_key=f"team_invitation_declined_{invitation.id}_{team.manager_user_id}",
            related_entity_id=invitation.id,
        )

    # Mark recipient's notification as actioned
    recipient_notif = db.query(Notification).filter(
        Notification.related_entity_id == invitation.id,
        Notification.type == "TEAM_INVITATION",
    ).first()
    if recipient_notif:
        recipient_notif.is_actioned = True
        recipient_notif.actioned_at = datetime.now(timezone.utc)
        db.add(recipient_notif)

    db.commit()

    # Send email to manager
    email_service = EmailService()
    email_service.send_decline_notification_email(
        manager_email=team.manager.email if team else "",
        employee_email=current_user.email,
        team_name=team.name if team else "",
    )

    # Log activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_INVITATION_DECLINED",
        action_details={
            "team_id": str(invitation.team_id),
            "invitation_id": str(invitation.id),
        },
    )

    return {"status": "declined", "message": "Invitation declined successfully"}


@router.delete("/{team_id}/members/{member_id}", status_code=status.HTTP_200_OK)
def remove_team_member(
    team_id: str,
    member_id: str,
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Remove a member from a team (soft delete via left_at timestamp).
    Only team manager can remove members.
    Does NOT delete user account or work history.
    """
    try:
        team_uuid = uuid.UUID(team_id)
        member_uuid = uuid.UUID(member_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    if team.manager_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only team manager can remove members",
        )

    member = db.query(User).filter(User.id == member_uuid).first()
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        )

    if member.profile:
        membership = db.query(TeamMembership).filter(
            TeamMembership.profile_id == member.profile.id,
            TeamMembership.team_id == team_uuid,
            TeamMembership.left_at.is_(None),
        ).first()

        if membership:
            membership.left_at = datetime.now(timezone.utc)
            db.add(membership)
            db.commit()

            log_system_activity(
                db=db,
                user_id=current_user.id,
                action_type="TEAM_MEMBER_REMOVED",
                action_details={
                    "team_id": str(team_id),
                    "member_id": str(member_id),
                },
            )

            return {"status": "removed", "message": f"Member {member.full_name} removed from team"}

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Member not found in this team",
    )


@router.post("/{team_id}/members/{member_id}/move-to-group", status_code=status.HTTP_200_OK)
def move_member_to_group(
    team_id: str,
    member_id: str,
    group_id: str = Query(...),
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Move a team member to a different group.
    Only team manager can move members.
    """
    try:
        team_uuid = uuid.UUID(team_id)
        member_uuid = uuid.UUID(member_id)
        group_uuid = uuid.UUID(group_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    if team.manager_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only team manager can move members",
        )

    group = db.query(Group).filter(
        Group.id == group_uuid,
        Group.team_id == team_uuid,
    ).first()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Group not found in this team",
        )

    member = db.query(User).filter(User.id == member_uuid).first()
    if not member or not member.profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        )

    membership = db.query(TeamMembership).filter(
        TeamMembership.profile_id == member.profile.id,
        TeamMembership.team_id == team_uuid,
        TeamMembership.left_at.is_(None),
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found in this team",
        )

    membership.group_id = group_uuid
    db.add(membership)
    db.commit()

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_MEMBER_MOVED",
        action_details={
            "team_id": str(team_id),
            "member_id": str(member_id),
            "group_id": str(group_id),
        },
    )

    return {"status": "moved", "message": f"Member moved to {group.name}"}


@router.get("/{team_id}/groups", status_code=status.HTTP_200_OK)
def list_team_groups(
    team_id: str,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    List all groups in a team.
    Authorization: team manager, team member, or admin.
    """
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    is_manager = team.manager_user_id == current_user.id
    is_admin = current_user.role == "ADMIN"
    is_member = False

    if current_user.role == "EMPLOYEE" and current_user.profile:
        is_member = db.query(TeamMembership).filter(
            TeamMembership.team_id == team_uuid,
            TeamMembership.profile_id == current_user.profile.id,
            TeamMembership.left_at.is_(None),
        ).first() is not None

    if not (is_manager or is_admin or is_member):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this team",
        )

    groups = db.query(Group).filter(Group.team_id == team_uuid).all()

    return [
        {
            "id": str(g.id),
            "name": g.name,
            "team_id": str(g.team_id),
            "created_at": g.created_at.isoformat(),
        }
        for g in groups
    ]


@router.post("/{team_id}/groups", status_code=status.HTTP_201_CREATED)
def create_team_group(
    team_id: str,
    name: str = Query(..., min_length=1, max_length=100),
    current_user: User = Depends(get_current_manager_only_user),
    db: Session = Depends(get_db),
):
    """
    Create a new group in a team.
    Only team manager can create groups.
    """
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid team ID format",
        )

    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Team not found",
        )

    if team.manager_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only team manager can create groups",
        )

    existing = db.query(Group).filter(
        Group.team_id == team_uuid,
        Group.name == name,
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Group with this name already exists in the team",
        )

    group = Group(
        team_id=team_uuid,
        name=name,
    )
    db.add(group)
    db.commit()
    db.refresh(group)

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TEAM_GROUP_CREATED",
        action_details={
            "team_id": str(team_id),
            "group_id": str(group.id),
            "group_name": name,
        },
    )

    return {
        "id": str(group.id),
        "name": group.name,
        "team_id": str(group.team_id),
        "created_at": group.created_at.isoformat(),
    }


@router.patch("/{team_id}", response_model=TeamResponse)
def update_team(
    team_id: str,
    team_data: TeamUpdateRequest,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Edit team name/description (Admin only, same org)."""
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")
    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids or team.organization_id not in admin_org_ids:
        raise HTTPException(status_code=403, detail="Not authorized")
    if team_data.name is not None:
        team.name = team_data.name
    if team_data.description is not None:
        team.description = team_data.description
    db.add(team); db.commit(); db.refresh(team)
    manager = db.query(User).filter(User.id == team.manager_user_id).first()
    return TeamResponse(
        id=team.id, name=team.name, description=team.description,
        manager_id=team.manager_user_id, manager_name=manager.full_name if manager else "Unknown",
        member_count=db.query(TeamMembership).filter(TeamMembership.team_id == team.id, TeamMembership.left_at.is_(None)).count(),
        is_active=team.is_active, created_at=team.created_at, updated_at=team.updated_at,
    )


@router.patch("/{team_id}/manager", response_model=TeamResponse)
def change_team_manager(
    team_id: str,
    data: TeamManagerUpdateRequest,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Change team manager (Admin only, same org)."""
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")
    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids or team.organization_id not in admin_org_ids:
        raise HTTPException(status_code=403, detail="Not authorized")
    if data.manager_user_id:
        new_mgr = db.query(User).filter(User.id == data.manager_user_id).first()
        if not new_mgr or new_mgr.role not in ("MANAGER", "ADMIN"):
            raise HTTPException(status_code=400, detail="New manager must be MANAGER or ADMIN")
        team.manager_user_id = data.manager_user_id
    db.add(team); db.commit(); db.refresh(team)
    manager = db.query(User).filter(User.id == team.manager_user_id).first()
    return TeamResponse(
        id=team.id, name=team.name, description=team.description,
        manager_id=team.manager_user_id, manager_name=manager.full_name if manager else "Unknown",
        member_count=db.query(TeamMembership).filter(TeamMembership.team_id == team.id, TeamMembership.left_at.is_(None)).count(),
        is_active=team.is_active, created_at=team.created_at, updated_at=team.updated_at,
    )


@router.delete("/{team_id}", status_code=status.HTTP_200_OK)
def delete_team(
    team_id: str,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Soft-delete team (Admin only, same org)."""
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")
    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids or team.organization_id not in admin_org_ids:
        raise HTTPException(status_code=403, detail="Not authorized")
    team.is_active = False
    db.add(team); db.commit()
    log_system_activity(db=db, user_id=current_user.id, action_type="TEAM_DELETED", action_details={"team_id": str(team_id)})
    return {"status": "deleted", "message": "Team deactivated"}


@router.get("/{team_id}/managers/search", response_model=List[dict])
def search_managers_for_team(
    team_id: str,
    q: str = Query(..., min_length=1, max_length=100),
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Search manager users for change-manager (Admin only)."""
    try:
        team_uuid = uuid.UUID(team_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid team ID")
    team = db.query(Team).filter(Team.id == team_uuid).first()
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    admin_org_ids = get_organization_ids_for_user(db, current_user.id)
    if not admin_org_ids or team.organization_id not in admin_org_ids:
        raise HTTPException(status_code=403, detail="Not authorized")
    search_term = f"%{q.lower()}%"
    users = db.query(User).filter(
        User.role.in_(["MANAGER", "ADMIN"]),
        User.is_active == True,
        (User.full_name.ilike(search_term)) | (User.email.ilike(search_term)),
        User.id != team.manager_user_id,
    ).limit(10).all()
    return [{"id": str(u.id), "full_name": u.full_name, "email": u.email} for u in users]