from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session, selectinload
from sqlalchemy import or_, and_
from typing import List, Optional
import uuid
from datetime import datetime, timezone

from ..database import get_db
from ..auth.security import get_current_active_user, get_current_admin_user, log_system_activity
from ..models import User, Profile, WorkSession, Task, Break, RecommendationFeedback, UserSettings, Team, TeamMembership, TaskCategory
from ..services.cache_service import analytics_cache
from ..schemas.work import (
    WorkSessionStartResponse,
    WorkSessionEndResponse,
    TaskCreateRequest,
    ManagerTaskAssignRequest,
    TaskResponse,
    TaskStatusUpdateRequest,
    BreakResponse,
    BreakStartRequest,
    BreakExtendRequest,
    SessionHistoryResponse,
    SessionHistoryBreak,
    SessionHistoryTask,
    RecommendationHistoryResponse,
    RecommendationHistoryItem,
    TaskCategoryResponse,
    TaskCategoryCreate,
    TaskCategoryUpdate,
    ManagerWorkloadResponse,
    ManagerTaskAssignResponse,
    ShiftPolicyStatus,
    TaskUpdateRequest,
    TaskGroupUpdateRequest,
    AssigneeManageRequest
)
from ..services.workload_service import (
    calculate_workload_for_assignment,
    get_team_workload_overview
)
from ..services.shift_policy_service import check_shift_policy_compliance

router = APIRouter(
    prefix="/work",
    tags=["work"],
    responses={404: {"description": "Not found"}},
)

@router.post("/session/start", response_model=WorkSessionStartResponse)
def start_work_session(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Start a new work session for the current user.
    Always ends any existing active session before creating a new one.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Check if there's already an active session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if active_session:
        # End the existing active session
        now = datetime.now(timezone.utc)
        active_session.ended_at = now

        # Close any active break belonging to this session
        active_break = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.ended_at.is_(None)
        ).first()
        if active_break:
            active_break.ended_at = now
            db.add(active_break)

        db.add(active_session)

        # Log the activity
        log_system_activity(
            db=db,
            user_id=current_user.id,
            action_type="WORK_SESSION_ENDED",
            action_details={
                "session_id": str(active_session.id),
                "reason": "Ended to start new session"
            }
        )

    # Create new work session
    new_session = WorkSession(
        profile_id=profile.id,
        started_at=datetime.now(timezone.utc)
    )

    db.add(new_session)

    # Reset manual DND override on starting a new shift
    user_settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    if user_settings:
        user_settings.manual_dnd_override = None
        db.add(user_settings)

    db.commit()
    db.refresh(new_session)

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="WORK_SESSION_STARTED",
        action_details={"session_id": str(new_session.id)}
    )

    policy_status = check_shift_policy_compliance(db, profile.id, new_session)

    return WorkSessionStartResponse(
        id=new_session.id,
        profile_id=new_session.profile_id,
        started_at=new_session.started_at,
        ended_at=new_session.ended_at,
        shift_status=ShiftPolicyStatus.model_validate(policy_status)
    )


@router.get("/session/active", response_model=WorkSessionStartResponse)
def get_active_work_session(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get the currently active work session for the user, if any.
    Returns 404 if no active session.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active work session found"
        )

    return active_session


@router.post("/session/end", response_model=WorkSessionEndResponse)
def end_work_session(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    End the current active work session.
    Calculates and returns the session duration.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the active session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active work session found"
        )

    # Prevent ending the shift while a break is still active, which would
    # orphan an open break and corrupt break duration tracking.
    active_break = db.query(Break).filter(
        Break.work_session_id == active_session.id,
        Break.ended_at.is_(None)
    ).first()
    if active_break:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot end shift while a break is active. End the current break first."
        )

    # End the session
    now = datetime.now(timezone.utc)
    active_session.ended_at = now

    # Finalize any active tasks associated with this session
    active_tasks = db.query(Task).filter(
        Task.work_session_id == active_session.id,
        Task.status == 'IN_PROGRESS',
        Task.started_at.isnot(None)
    ).all()

    for task in active_tasks:
        session_ended = now
        session_seconds = (session_ended - task.started_at).total_seconds()
        session_minutes = int(session_seconds / 60)

        breaks_during_task = db.query(Break).filter(
            Break.work_session_id == active_session.id,
            Break.started_at >= task.started_at,
            Break.ended_at.isnot(None),
            Break.ended_at <= session_ended
        ).all()

        total_break_minutes = sum(
            int((break_.ended_at - break_.started_at).total_seconds() / 60)
            for break_ in breaks_during_task
        )

        session_actual_minutes = max(0, session_minutes - total_break_minutes)
        current_actual = task.actual_minutes or 0
        task.actual_minutes = current_actual + session_actual_minutes
        task.started_at = None
        db.add(task)

    # If manual override was FALSE (forced off during work), reset to NULL so automatic off-shift DND takes over
    user_settings = db.query(UserSettings).filter(UserSettings.user_id == current_user.id).first()
    if user_settings and user_settings.manual_dnd_override is False:
        user_settings.manual_dnd_override = None
        db.add(user_settings)

    # Calculate duration in minutes
    duration_minutes = int((now - active_session.started_at).total_seconds() / 60)

    db.add(active_session)
    db.commit()
    db.refresh(active_session)

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="WORK_SESSION_ENDED",
        action_details={
            "session_id": str(active_session.id),
            "duration_minutes": duration_minutes
        }
    )

    return WorkSessionEndResponse(
        id=active_session.id,
        profile_id=active_session.profile_id,
        started_at=active_session.started_at,
        ended_at=active_session.ended_at,
        duration_minutes=duration_minutes
    )


@router.post("/tasks", response_model=TaskResponse)
def create_task(
    task_data: TaskCreateRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Create a new task for the current user.
    If there's an active work session, associate the task with it.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find active work session to associate task with (optional for pre-shift task creation)
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    # Validate priority if provided
    if task_data.priority and task_data.priority not in ['LOW', 'MEDIUM', 'HIGH', 'URGENT']:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Priority must be LOW, MEDIUM, HIGH, or URGENT"
        )

    # Create new task
    new_task = Task(
        profile_id=profile.id,
        work_session_id=active_session.id if active_session else None,
        title=task_data.title,
        description=task_data.description,
        category=task_data.category,
        priority=task_data.priority,
        deadline=task_data.deadline,
        estimated_minutes=task_data.estimated_minutes,
        status="TODO"  # Default status for new tasks
    )

    db.add(new_task)
    db.commit()
    db.refresh(new_task)

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="TASK_CREATED",
        action_details={
            "task_id": str(new_task.id),
            "title": new_task.title,
            "work_session_id": str(new_task.work_session_id) if new_task.work_session_id else None
        }
    )

    return TaskResponse(
        id=new_task.id,
        profile_id=new_task.profile_id,
        work_session_id=new_task.work_session_id,
        title=new_task.title,
        description=new_task.description,
        status=new_task.status,
        category=new_task.category,
        priority=new_task.priority,
        deadline=new_task.deadline,
        estimated_minutes=new_task.estimated_minutes,
        actual_minutes=new_task.actual_minutes,
        started_at=new_task.started_at,
        ended_at=new_task.ended_at
    )


@router.patch("/tasks/{task_id}", response_model=TaskResponse)
def update_task_status(
    task_id: uuid.UUID,
    status_data: TaskStatusUpdateRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Update the status of a task owned by the current user.
    Validates task ownership before applying the change.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the task and verify ownership
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Task not found"
        )
    if task.profile_id != profile.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Task does not belong to the current user"
        )

    # Apply the status change with automatic time tracking
    old_status = task.status
    new_status = status_data.status
    now = datetime.now(timezone.utc)

    # Validate status transitions to enforce task lifecycle integrity
    # Allowed transitions:
    #   TODO → IN_PROGRESS
    #   IN_PROGRESS → DONE
    #   IN_PROGRESS → TODO (reset)
    #   IN_PROGRESS → BLOCKED
    #   BLOCKED → IN_PROGRESS
    #   BLOCKED → TODO
    #   TODO → BLOCKED
    #   DONE is terminal (no transitions out of DONE)
    invalid_transitions = {
        ('TODO', 'DONE'): "Cannot transition directly from TODO to DONE. Must go through IN_PROGRESS first.",
        ('DONE', 'TODO'): "DONE is a terminal status. Cannot transition out of DONE.",
        ('DONE', 'IN_PROGRESS'): "DONE is a terminal status. Cannot transition out of DONE.",
        ('DONE', 'BLOCKED'): "DONE is a terminal status. Cannot transition out of DONE.",
        ('BLOCKED', 'DONE'): "Cannot transition from BLOCKED directly to DONE. Must go through IN_PROGRESS first.",
    }
    transition_key = (old_status, new_status)
    if transition_key in invalid_transitions:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=invalid_transitions[transition_key]
        )

    # Track when task work begins
    if new_status == 'IN_PROGRESS':
        # Only set started_at if it's not already set (preserves original start time for cumulative tracking)
        if task.started_at is None:
            task.started_at = now
        # Associate task with current work session if one exists
        active_session = db.query(WorkSession).filter(
            WorkSession.profile_id == profile.id,
            WorkSession.ended_at.is_(None)
        ).first()
        if active_session:
            task.work_session_id = active_session.id

    # Handle transitioning TO BLOCKED (pausing work)
    if old_status == 'IN_PROGRESS' and new_status == 'BLOCKED':
        # Calculate and accumulate time worked in this session before blocking
        if task.started_at is not None:
            # Calculate session time
            session_ended = now
            session_seconds = (session_ended - task.started_at).total_seconds()
            session_minutes = int(session_seconds / 60)

            # Subtract break time if task is associated with a work session
            if task.work_session_id:
                # Get all breaks for this work session that occurred during task work
                breaks_during_task = db.query(Break).filter(
                    Break.work_session_id == task.work_session_id,
                    Break.started_at >= task.started_at,
                    Break.ended_at.isnot(None),
                    Break.ended_at <= session_ended
                ).all()

                # Sum up break durations
                total_break_minutes = sum(
                    int((break_.ended_at - break_.started_at).total_seconds() / 60)
                    for break_ in breaks_during_task
                )

                # Actual work time = elapsed time - break time
                session_actual_minutes = max(0, session_minutes - total_break_minutes)
            else:
                # No work session, use elapsed time directly
                session_actual_minutes = session_minutes

            # Add to existing actual_minutes (treat None as 0)
            current_actual = task.actual_minutes or 0
            task.actual_minutes = current_actual + session_actual_minutes

        task.started_at = None
        task.ended_at = None
        # Note: work_session_id is intentionally preserved to show which session this task was last worked in

    # Calculate actual_minutes when task is completed
    if new_status == 'DONE':
        # Validate: started_at must be set for DONE tasks
        if task.started_at is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot mark task as DONE: started_at is not set. Task must be IN_PROGRESS first."
            )

        task.ended_at = now

        # Calculate total elapsed time in this session
        elapsed_seconds = (task.ended_at - task.started_at).total_seconds()
        elapsed_minutes = int(elapsed_seconds / 60)

        # Subtract break time if task is associated with a work session
        if task.work_session_id:
            # Get all breaks for this work session that occurred during task work
            breaks_during_task = db.query(Break).filter(
                Break.work_session_id == task.work_session_id,
                Break.started_at >= task.started_at,
                Break.ended_at.isnot(None),
                Break.ended_at <= task.ended_at
            ).all()

            # Sum up break durations
            total_break_minutes = sum(
                int((break_.ended_at - break_.started_at).total_seconds() / 60)
                for break_ in breaks_during_task
            )

            # Actual work time = elapsed time - break time
            session_actual_minutes = max(0, elapsed_minutes - total_break_minutes)
        else:
            # No work session, use elapsed time directly
            session_actual_minutes = elapsed_minutes

        # Add to existing actual_minutes (treat None as 0)
        current_actual = task.actual_minutes or 0
        task.actual_minutes = current_actual + session_actual_minutes

        # Enforce: ended_at > started_at
        if task.ended_at <= task.started_at:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Task ended_at must be after started_at"
            )
        # Note: work_session_id is intentionally preserved to show which session this task was last worked in

    # If transitioning TO TODO, clear lifecycle timestamps but preserve actual_minutes and work_session_id
    if new_status == 'TODO':
        # Calculate and accumulate time worked in this session before clearing
        if task.started_at is not None and old_status == 'IN_PROGRESS':
            # Calculate session time
            session_ended = now
            session_seconds = (session_ended - task.started_at).total_seconds()
            session_minutes = int(session_seconds / 60)

            # Subtract break time if task is associated with a work session
            if task.work_session_id:
                # Get all breaks for this work session that occurred during task work
                breaks_during_task = db.query(Break).filter(
                    Break.work_session_id == task.work_session_id,
                    Break.started_at >= task.started_at,
                    Break.ended_at.isnot(None),
                    Break.ended_at <= session_ended
                ).all()

                # Sum up break durations
                total_break_minutes = sum(
                    int((break_.ended_at - break_.started_at).total_seconds() / 60)
                    for break_ in breaks_during_task
                )

                # Actual work time = elapsed time - break time
                session_actual_minutes = max(0, session_minutes - total_break_minutes)
            else:
                # No work session, use elapsed time directly
                session_actual_minutes = session_minutes

            # Add to existing actual_minutes (treat None as 0)
            current_actual = task.actual_minutes or 0
            task.actual_minutes = current_actual + session_actual_minutes

        task.started_at = None
        task.ended_at = None
        # Note: work_session_id is intentionally preserved to show which session this task was last worked in

    task.status = new_status
    db.add(task)
    db.commit()
    db.refresh(task)

    return TaskResponse(
        id=task.id,
        profile_id=task.profile_id,
        work_session_id=task.work_session_id,
        title=task.title,
        description=task.description,
        status=task.status,
        category=task.category,
        priority=task.priority,
        deadline=task.deadline,
        estimated_minutes=task.estimated_minutes,
        actual_minutes=task.actual_minutes,
        started_at=task.started_at,
        ended_at=task.ended_at
    )


@router.get("/session/active", response_model=WorkSessionStartResponse)
def get_active_work_session(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get the current active work session for the user.
    Returns the session details if active, otherwise raises 404.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the active session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active work session found"
        )

    policy_status = check_shift_policy_compliance(db, profile.id, active_session)

    return WorkSessionStartResponse(
        id=active_session.id,
        profile_id=active_session.profile_id,
        started_at=active_session.started_at,
        ended_at=active_session.ended_at,
        shift_status=ShiftPolicyStatus.model_validate(policy_status)
    )



@router.get("/session/{session_id}/breaks", response_model=List[BreakResponse])
def get_session_breaks(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get all breaks for a specific work session.
    Validates that the session belongs to the current user.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the session and verify it belongs to the user
    session = db.query(WorkSession).filter(WorkSession.id == session_id).first()
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Work session not found"
        )
    if session.profile_id != profile.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Work session does not belong to the current user"
        )

    # Get breaks for this session
    breaks = db.query(Break).filter(Break.work_session_id == session_id).order_by(Break.started_at).all()

    return [
        BreakResponse(
            id=break_.id,
            work_session_id=break_.work_session_id,
            break_type=break_.break_type,
            started_at=break_.started_at,
            ended_at=break_.ended_at,
            duration_minutes=int((break_.ended_at - break_.started_at).total_seconds() / 60) if break_.ended_at else None
        )
        for break_ in breaks
    ]


@router.get("/tasks/active", response_model=List[TaskResponse])
def get_active_session_tasks(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get all tasks for the current active work session.
    Returns 404 (matching /work/session/active) when no session is active,
    so the frontend can treat "no active session" as a non-error signal.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the active session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    # Preserve existing active-resource behavior: no active session -> 404
    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active work session found"
        )

    # Query the active session's tasks
    tasks = db.query(Task).filter(
        Task.work_session_id == active_session.id
    ).all()

    return [
        TaskResponse(
            id=task.id,
            profile_id=task.profile_id,
            work_session_id=task.work_session_id,
            assigned_by_user_id=task.assigned_by_user_id,
            task_type=task.task_type,
            title=task.title,
            description=task.description,
            status=task.status,
            category=task.category,
            priority=task.priority,
            deadline=task.deadline,
            estimated_minutes=task.estimated_minutes,
            actual_minutes=task.actual_minutes,
            started_at=task.started_at,
            ended_at=task.ended_at
        )
        for task in tasks
    ]


@router.post("/break/start", response_model=BreakResponse)
def start_break(
    break_data: BreakStartRequest,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Start a break for the current user.
    Validates that there's an active work session and no active break.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the active work session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active work session found. Please start a work session first."
        )

    # Check if there's already an active break
    active_break = db.query(Break).filter(
        Break.work_session_id == active_session.id,
        Break.ended_at.is_(None)
    ).first()

    if active_break:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot start a new break while another break is active. Please end the current break first."
        )

    # Fetch this session's persisted breaks to enforce workflow sequence
    # and prevent duplicate starts of the same break type.
    session_breaks = db.query(Break).filter(
        Break.work_session_id == active_session.id
    ).all()
    break_by_type = {b.break_type: b for b in session_breaks}

    # Duplicate prevention: scheduled legacy breaks (BREAK_1, BREAK_2, LUNCH) are one-per-session.
    # COACH_BREAK, MEAL, BREAK, and OTHER (Away) are repeatable.
    multi_allowed = {"COACH_BREAK", "MEAL", "OTHER", "BREAK"}
    if break_data.break_type not in multi_allowed and break_data.break_type in break_by_type:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"A break of type {break_data.break_type} has already been started for this session."
        )

    # Sequence enforcement: legacy LUNCH and BREAK_2 require a completed BREAK_1.
    # BREAK, MEAL, OTHER, and COACH_BREAK have no prerequisites.
    predecessor_type = {"LUNCH": "BREAK_1", "BREAK_2": "BREAK_1"}.get(break_data.break_type)
    if predecessor_type is not None:
        predecessor = break_by_type.get(predecessor_type)
        if predecessor is None or predecessor.ended_at is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot start {break_data.break_type} before {predecessor_type} is completed."
            )

    # Create new break
    new_break = Break(
        work_session_id=active_session.id,
        break_type=break_data.break_type,
        started_at=datetime.now(timezone.utc),
        notes=break_data.notes
    )

    db.add(new_break)
    db.commit()
    db.refresh(new_break)

    if break_data.recommendation_id:
        rec_feedback = db.query(RecommendationFeedback).filter(
            RecommendationFeedback.recommendation_id == break_data.recommendation_id,
            RecommendationFeedback.user_id == current_user.id
        ).first()
        if rec_feedback:
            rec_feedback.user_action = "accepted"
            rec_feedback.break_started_at = new_break.started_at
            rec_feedback.break_type = new_break.break_type
            db.commit()

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="BREAK_STARTED",
        action_details={
            "break_id": str(new_break.id),
            "break_type": new_break.break_type,
            "session_id": str(active_session.id)
        }
    )

    return BreakResponse(
        id=new_break.id,
        work_session_id=new_break.work_session_id,
        break_type=new_break.break_type,
        started_at=new_break.started_at,
        ended_at=new_break.ended_at
    )


@router.post("/break/end/{break_id}", response_model=BreakResponse)
def end_break(
    break_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    End a specific break by ID.
    Validates that the break belongs to the current user's active session and is currently active.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Find the break
    break_record = db.query(Break).filter(Break.id == break_id).first()
    if not break_record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Break not found"
        )

    # Verify the break belongs to the user's active session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session or break_record.work_session_id != active_session.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Break does not belong to your active work session"
        )

    # Verify the break is currently active
    if break_record.ended_at is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Break is already ended"
        )

    # End the break
    now = datetime.now(timezone.utc)
    break_record.ended_at = now

    # Calculate duration in minutes
    duration_minutes = int((now - break_record.started_at).total_seconds() / 60)

    db.add(break_record)
    db.commit()
    db.refresh(break_record)

    # Log the activity
    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="BREAK_ENDED",
        action_details={
            "break_id": str(break_record.id),
            "break_type": break_record.break_type,
            "session_id": str(active_session.id),
            "duration_minutes": duration_minutes
        }
    )

    return BreakResponse(
        id=break_record.id,
        work_session_id=break_record.work_session_id,
        break_type=break_record.break_type,
        started_at=break_record.started_at,
        ended_at=break_record.ended_at,
        duration_minutes=duration_minutes
    )


@router.post("/break/extend/{break_id}", response_model=BreakResponse)
def extend_break(
    break_id: uuid.UUID,
    extend_data: BreakExtendRequest = BreakExtendRequest(),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Record an extension for an active break (Overbreak / Overmeal / Overaway).
    Updates break notes with extension reason and extension duration.
    """
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    break_record = db.query(Break).filter(Break.id == break_id).first()
    if not break_record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Break not found"
        )

    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session or break_record.work_session_id != active_session.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Break does not belong to your active work session"
        )

    if break_record.ended_at is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot extend an already ended break"
        )

    current_notes = break_record.notes or ""
    ext_msg = f"[Extended +{extend_data.extension_minutes}m"
    if extend_data.reason:
        ext_msg += f": {extend_data.reason}"
    ext_msg += "]"
    break_record.notes = f"{current_notes} {ext_msg}".strip()

    db.add(break_record)
    db.commit()
    db.refresh(break_record)

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="BREAK_EXTENDED",
        action_details={
            "break_id": str(break_record.id),
            "break_type": break_record.break_type,
            "extension_minutes": extend_data.extension_minutes,
            "reason": extend_data.reason
        }
    )

    current_duration = int((datetime.now(timezone.utc) - break_record.started_at).total_seconds() / 60)

    return BreakResponse(
        id=break_record.id,
        work_session_id=break_record.work_session_id,
        break_type=break_record.break_type,
        started_at=break_record.started_at,
        ended_at=break_record.ended_at,
        duration_minutes=current_duration
    )


@router.get("/break/active", response_model=BreakResponse)
def get_active_break(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get the currently active break for the user's active work session.
    """
    # Get the user's profile using direct relationship access
    if not current_user.profile:
        # Fallback to query if relationship isn't loaded
        profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Profile not found"
            )
    else:
        profile = current_user.profile

    # Find the active work session
    active_session = db.query(WorkSession).filter(
        WorkSession.profile_id == profile.id,
        WorkSession.ended_at.is_(None)
    ).first()

    if not active_session:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No active work session found"
        )

    # Find the active break
    active_break = db.query(Break).filter(
        Break.work_session_id == active_session.id,
        Break.ended_at.is_(None)
    ).first()

    if not active_break:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No active break found"
        )

    # Calculate duration in minutes
    now = datetime.now(timezone.utc)
    duration_minutes = int((now - active_break.started_at).total_seconds() / 60)

    return BreakResponse(
        id=active_break.id,
        work_session_id=active_break.work_session_id,
        break_type=active_break.break_type,
        started_at=active_break.started_at,
        ended_at=active_break.ended_at,
        duration_minutes=duration_minutes
    )


@router.get("/sessions/history", response_model=List[SessionHistoryResponse])
def get_sessions_history(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    date_from: Optional[datetime] = None,
    date_to: Optional[datetime] = None,
    status: Optional[str] = Query(None, pattern="^(completed|active|all)$"),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get the authenticated user's work session history with eager loading,
    pagination, and optional date/status filters.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    query = db.query(WorkSession).filter(WorkSession.profile_id == profile.id)

    # Status filter
    if status == "completed":
        query = query.filter(WorkSession.ended_at.isnot(None))
    elif status == "active":
        query = query.filter(WorkSession.ended_at.is_(None))
    else:
        # Default/all behavior for history: completed sessions (or all if specified)
        query = query.filter(WorkSession.ended_at.isnot(None))

    if date_from:
        query = query.filter(WorkSession.started_at >= date_from)
    if date_to:
        query = query.filter(WorkSession.started_at <= date_to)

    # Eager load breaks and tasks to eliminate N+1 queries
    query = query.options(
        selectinload(WorkSession.breaks),
        selectinload(WorkSession.tasks)
    ).order_by(WorkSession.ended_at.desc())

    sessions = query.offset(offset).limit(limit).all()

    # Build response with associated breaks and tasks
    response_sessions = []
    for session in sessions:
        # Calculate session duration in minutes
        duration_minutes = int((session.ended_at - session.started_at).total_seconds() / 60) if session.ended_at else None

        breaks_response = [
            SessionHistoryBreak(
                id=break_.id,
                break_type=break_.break_type,
                started_at=break_.started_at,
                ended_at=break_.ended_at,
                duration_minutes=int((break_.ended_at - break_.started_at).total_seconds() / 60) if break_.ended_at else None
            )
            for break_ in sorted(session.breaks, key=lambda b: b.started_at)
        ]

        tasks_response = [
            SessionHistoryTask(
                id=task.id,
                title=task.title,
                description=task.description,
                category=task.category,
                status=task.status,
                priority=task.priority,
                estimated_minutes=task.estimated_minutes,
                actual_minutes=task.actual_minutes,
                started_at=task.started_at,
                ended_at=task.ended_at
            )
            for task in sorted(session.tasks, key=lambda t: t.created_at if hasattr(t, 'created_at') else t.started_at or session.started_at)
        ]

        response_sessions.append(
            SessionHistoryResponse(
                id=session.id,
                started_at=session.started_at,
                ended_at=session.ended_at,
                duration_minutes=duration_minutes,
                breaks=breaks_response,
                tasks=tasks_response
            )
        )

    return response_sessions


@router.get("/sessions/{session_id}/recommendations", response_model=RecommendationHistoryResponse)
def get_session_recommendations(
    session_id: uuid.UUID,
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get recommendations for a specific work session. Only returns recommendations scoped to this session."""
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    session = db.query(WorkSession).filter(WorkSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Work session not found")
    if session.profile_id != profile.id:
        raise HTTPException(status_code=403, detail="Work session does not belong to the current user")

    recommendations = db.query(RecommendationFeedback).filter(
        or_(
            RecommendationFeedback.work_session_id == session_id,
            and_(
                RecommendationFeedback.user_id == current_user.id,
                RecommendationFeedback.timestamp >= session.started_at,
                RecommendationFeedback.timestamp <= (session.ended_at or datetime.now(timezone.utc))
            )
        )
    ).order_by(RecommendationFeedback.timestamp).all()

    if not recommendations and session.ended_at:
        try:
            from ..services.historical_recommendation_backfill import reconstruct_historical_recommendations_for_session
            new_rec = reconstruct_historical_recommendations_for_session(db, profile, session)
            if new_rec:
                db.commit()
                recommendations = [new_rec]
        except Exception:
            db.rollback()

    items = []
    for r in recommendations:
        items.append(RecommendationHistoryItem(
            recommendation_id=r.recommendation_id,
            recommendation_type=r.recommendation_type,
            recommendation_text=r.recommendation_text if hasattr(r, 'recommendation_text') else None,
            reason=r.reason,
            recommendation_score=r.recommendation_score,
            timestamp=r.timestamp,
            user_action=r.user_action,
            model_version=r.model_version,
            work_session_id=r.work_session_id,
            provenance=getattr(r, 'provenance', 'live'),
        ))

    return RecommendationHistoryResponse(
        session_id=session_id,
        items=items
    )


@router.get("/tasks/history", response_model=List[TaskResponse])
def get_tasks_history(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get all tasks for the current user across all work sessions.
    Returns tasks ordered by most recent first (by ended_at, then started_at).
    Supports task history view with filtering on the frontend.
    """
    # Get the user's profile
    profile = db.query(Profile).filter(Profile.user_id == current_user.id).first()
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found"
        )

    # Query all tasks for this profile, ordered by most recent first
    tasks = db.query(Task).filter(
        Task.profile_id == profile.id
    ).order_by(
        Task.ended_at.desc().nullslast(),
        Task.started_at.desc().nullslast(),
        Task.created_at.desc()
    ).all()

    return [
        TaskResponse(
            id=task.id,
            profile_id=task.profile_id,
            work_session_id=task.work_session_id,
            assigned_by_user_id=task.assigned_by_user_id,
            task_type=task.task_type,
            title=task.title,
            description=task.description,
            status=task.status,
            category=task.category,
            priority=task.priority,
            deadline=task.deadline,
            estimated_minutes=task.estimated_minutes,
            actual_minutes=task.actual_minutes,
            started_at=task.started_at,
            ended_at=task.ended_at
        )
        for task in tasks
    ]


@router.get("/admin/active-sessions-count")
def get_admin_active_sessions_count(
    _current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Get count of currently active work sessions across the organization.
    Only accessible by ADMIN.
    """
    # Count all active work sessions (where ended_at is NULL)
    active_sessions_count = db.query(WorkSession).filter(
        WorkSession.ended_at.is_(None)
    ).count()

    return {"active_sessions": active_sessions_count}


@router.get("/admin/active-breaks-count")
def get_admin_active_breaks_count(
    _current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """
    Get count of currently active breaks across the organization.
    Only accessible by ADMIN.
    """
    # Count all active breaks (where ended_at is NULL)
    active_breaks_count = db.query(Break).filter(
        Break.ended_at.is_(None)
    ).count()

    return {"active_breaks": active_breaks_count}


def _get_current_manager_or_admin(current_user: User = Depends(get_current_active_user)) -> User:
    if current_user.role.upper() not in ["MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to managers and administrators",
        )
    return current_user


def _validate_manager_team_access(db: Session, manager: User, profile_id: uuid.UUID) -> Profile:
    target_profile = db.query(Profile).filter(Profile.id == profile_id).first()
    if not target_profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Target employee profile not found"
        )

    if manager.role.upper() == "ADMIN":
        return target_profile

    manager_teams = db.query(Team).filter(Team.manager_user_id == manager.id).all()
    manager_team_ids = [t.id for t in manager_teams]

    if not manager_team_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Manager does not manage any teams"
        )

    membership = db.query(TeamMembership).filter(
        TeamMembership.team_id.in_(manager_team_ids),
        TeamMembership.profile_id == target_profile.id,
        TeamMembership.left_at.is_(None)
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Target employee is not in an authorized team managed by this manager"
        )

    return target_profile


@router.get("/manager/workload/{profile_id}", response_model=ManagerWorkloadResponse)
def get_employee_workload(
    profile_id: uuid.UUID,
    new_task_estimated_minutes: Optional[int] = Query(None, ge=0),
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Get workload analysis for an employee, optionally simulating a new task assignment.
    Accessible only by authorized managers or admins.
    """
    target_profile = _validate_manager_team_access(db, current_user, profile_id)
    est_mins = new_task_estimated_minutes or 0
    return calculate_workload_for_assignment(db, target_profile.id, est_mins)


@router.post("/manager/tasks", response_model=ManagerTaskAssignResponse, status_code=status.HTTP_201_CREATED)
def assign_manager_task(
    task_data: ManagerTaskAssignRequest,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Create and assign a WORK task to an employee with real-time workload impact analysis.
    Accessible only by authorized Managers (within their teams) or Admins.
    Does not reject assignments solely on workload conflicts, but returns explainable warnings.
    """
    target_profile = _validate_manager_team_access(db, current_user, task_data.profile_id)

    if task_data.priority and task_data.priority not in ['LOW', 'MEDIUM', 'HIGH', 'URGENT']:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Priority must be LOW, MEDIUM, HIGH, or URGENT"
        )

    new_task = Task(
        profile_id=target_profile.id,
        assigned_by_user_id=current_user.id,
        task_type="WORK",
        title=task_data.title,
        description=task_data.description,
        category=task_data.category,
        priority=task_data.priority,
        deadline=task_data.deadline,
        scheduled_start_date=task_data.scheduled_start_date,
        estimated_minutes=task_data.estimated_minutes,
        status="TODO"
    )

    db.add(new_task)
    db.commit()
    db.refresh(new_task)

    # Calculate workload impact including the newly assigned task
    workload_analysis = calculate_workload_for_assignment(
        db,
        target_profile.id,
        task_data.estimated_minutes or 0,
        task_data.deadline
    )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="MANAGER_TASK_ASSIGNED",
        action_details={
            "task_id": str(new_task.id),
            "profile_id": str(target_profile.id),
            "title": new_task.title,
            "workload_status": workload_analysis["status"],
            "utilization_pct": workload_analysis["utilization_pct"]
        }
    )

    # Construct response with workload analysis
    response_data = TaskResponse.model_validate(new_task).model_dump()
    response_data["workload_analysis"] = workload_analysis
    return response_data



@router.get("/manager/tasks", response_model=List[TaskResponse])
def get_manager_team_tasks(
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Get tasks assigned to employees within the manager's authorized teams.
    """
    if current_user.role.upper() == "ADMIN":
        tasks = db.query(Task).filter(Task.task_type == "WORK").order_by(Task.created_at.desc()).all()
        return tasks

    manager_teams = db.query(Team).filter(Team.manager_user_id == current_user.id).all()
    manager_team_ids = [t.id for t in manager_teams]

    if not manager_team_ids:
        return []

    team_memberships = db.query(TeamMembership).filter(
        TeamMembership.team_id.in_(manager_team_ids),
        TeamMembership.left_at.is_(None)
    ).all()
    profile_ids = [m.profile_id for m in team_memberships]

    if not profile_ids:
        return []

    tasks = db.query(Task).filter(
        Task.profile_id.in_(profile_ids)
    ).order_by(Task.created_at.desc()).all()

    return tasks


@router.get("/categories", response_model=List[TaskCategoryResponse])
def get_task_categories(
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get task categories. Admins see all; managers and employees see active categories.
    """
    query = db.query(TaskCategory)
    if current_user.role.upper() != "ADMIN":
        query = query.filter(TaskCategory.is_active == True)
    return query.order_by(TaskCategory.name.asc()).all()


@router.post("/categories", response_model=TaskCategoryResponse, status_code=status.HTTP_201_CREATED)
def create_task_category(
    category_data: TaskCategoryCreate,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Create a new task category (Admin only).
    """
    existing = db.query(TaskCategory).filter(TaskCategory.name == category_data.name).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Category with this name already exists"
        )
    cat = TaskCategory(name=category_data.name, is_active=True)
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return cat


@router.patch("/categories/{category_id}", response_model=TaskCategoryResponse)
def update_task_category(
    category_id: uuid.UUID,
    update_data: TaskCategoryUpdate,
    current_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    Update a task category (Admin only).
    """
    cat = db.query(TaskCategory).filter(TaskCategory.id == category_id).first()
    if not cat:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    if update_data.name is not None:
        conflict = db.query(TaskCategory).filter(TaskCategory.name == update_data.name, TaskCategory.id != category_id).first()
        if conflict:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Category with this name already exists"
            )
        cat.name = update_data.name
    if update_data.is_active is not None:
        cat.is_active = update_data.is_active

    db.commit()
    db.refresh(cat)
    return cat


@router.patch("/manager/tasks/{task_id}", response_model=TaskResponse)
def update_manager_task(
    task_id: uuid.UUID,
    update_data: TaskUpdateRequest,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Update an existing manager-assigned task.
    """
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    _validate_manager_team_access(db, current_user, task.profile_id)

    if update_data.title is not None:
        task.title = update_data.title
    if update_data.description is not None:
        task.description = update_data.description
    if update_data.category is not None:
        task.category = update_data.category
    if update_data.priority is not None:
        if update_data.priority not in ['LOW', 'MEDIUM', 'HIGH', 'URGENT']:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid priority")
        task.priority = update_data.priority
    if update_data.deadline is not None:
        task.deadline = update_data.deadline
    if update_data.scheduled_start_date is not None:
        task.scheduled_start_date = update_data.scheduled_start_date
    if update_data.estimated_minutes is not None:
        task.estimated_minutes = update_data.estimated_minutes

    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@router.patch("/manager/tasks/group", response_model=List[TaskResponse])
def update_manager_task_group(
    update_data: TaskGroupUpdateRequest,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Update all tasks belonging to a group (matched by old title, category, deadline) across authorized team members.
    """
    if current_user.role.upper() == "ADMIN":
        profile_ids = None
    else:
        manager_teams = db.query(Team).filter(Team.manager_user_id == current_user.id).all()
        manager_team_ids = [t.id for t in manager_teams]
        if not manager_team_ids:
            return []
        team_memberships = db.query(TeamMembership).filter(
            TeamMembership.team_id.in_(manager_team_ids),
            TeamMembership.left_at.is_(None)
        ).all()
        profile_ids = [m.profile_id for m in team_memberships]

    query = db.query(Task).filter(Task.title == update_data.old_title)
    if update_data.old_category is not None:
        query = query.filter(Task.category == update_data.old_category)
    if profile_ids is not None:
        query = query.filter(Task.profile_id.in_(profile_ids))

    tasks = query.all()
    if not tasks:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No matching tasks found for group")

    for task in tasks:
        task.title = update_data.title
        if update_data.description is not None:
            task.description = update_data.description
        if update_data.category is not None:
            task.category = update_data.category
        if update_data.priority is not None:
            task.priority = update_data.priority
        if update_data.deadline is not None:
            task.deadline = update_data.deadline
        if update_data.scheduled_start_date is not None:
            task.scheduled_start_date = update_data.scheduled_start_date
        if update_data.estimated_minutes is not None:
            task.estimated_minutes = update_data.estimated_minutes
        db.add(task)

    db.commit()
    for task in tasks:
        db.refresh(task)
    return tasks


@router.post("/manager/tasks/assignees", response_model=ManagerTaskAssignResponse, status_code=status.HTTP_201_CREATED)
def add_assignee_to_task_group(
    assign_data: AssigneeManageRequest,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Add an employee to a task assignment group (create task assignment for employee).
    """
    target_profile = _validate_manager_team_access(db, current_user, assign_data.profile_id)

    duplicate = db.query(Task).filter(
        Task.profile_id == target_profile.id,
        Task.title == assign_data.title,
        Task.status.in_(['TODO', 'IN_PROGRESS'])
    ).first()

    if duplicate:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Employee is already assigned to this active task."
        )

    new_task = Task(
        profile_id=target_profile.id,
        assigned_by_user_id=current_user.id,
        task_type="WORK",
        title=assign_data.title,
        description=assign_data.description,
        category=assign_data.category,
        priority=assign_data.priority or 'MEDIUM',
        deadline=assign_data.deadline,
        scheduled_start_date=assign_data.scheduled_start_date,
        estimated_minutes=assign_data.estimated_minutes,
        status="TODO"
    )

    db.add(new_task)
    db.commit()
    db.refresh(new_task)

    workload_analysis = calculate_workload_for_assignment(
        db,
        target_profile.id,
        assign_data.estimated_minutes or 0,
        assign_data.deadline
    )

    response_data = TaskResponse.model_validate(new_task).model_dump()
    response_data["workload_analysis"] = workload_analysis
    return response_data


@router.delete("/manager/tasks/{task_id}", status_code=status.HTTP_200_OK)
def remove_manager_task(
    task_id: uuid.UUID,
    current_user: User = Depends(_get_current_manager_or_admin),
    db: Session = Depends(get_db)
):
    """
    Remove an employee's task assignment. Preserves historical work sessions and actual working time.
    If TODO, deletes the task record. If IN_PROGRESS or DONE, marks as CANCELLED (or preserves completed history).
    """
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")

    _validate_manager_team_access(db, current_user, task.profile_id)

    if task.status == 'TODO' and (task.actual_minutes or 0) == 0:
        db.delete(task)
    elif task.status == 'DONE':
        # Preserve completed task record and history as per business rules
        task.status = 'CANCELLED'
        db.add(task)
    else:
        task.status = 'CANCELLED'
        db.add(task)

    db.commit()
    return {"message": "Assignment removed successfully", "task_id": str(task_id)}



