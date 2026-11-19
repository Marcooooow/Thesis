import os
import sys
import uuid
import hashlib
import random
from datetime import datetime, date, time, timedelta, timezone
from typing import Dict, Any, List
from sqlalchemy.orm import Session
from sqlalchemy import func, and_

from ..models import (
    User, Profile, Organization, Team, TeamMembership,
    WorkSession, Break, Task, Recommendation, RecommendationFeedback,
    SessionWellbeingCheckin
)
from .diverse_provisioning_service import provision_diverse_defense_organization


def generate_historical_behavioral_dataset(
    db: Session,
    *,
    current_user: User,
    organization_name: str = "IntelliBreak Defense Organization",
    start_date: date = date(2026, 8, 1),
    end_date: date = date(2026, 11, 16),
    num_managers: int = 5,
    num_employees: int = 24,
    num_teams: int = 5,
) -> Dict[str, Any]:
    """
    Generate realistic, chronologically consistent historical behavioral records
    with robust incomplete-run child repair and bounded per-day transaction commits.
    """
    provision_summary = provision_diverse_defense_organization(
        db,
        current_user=current_user,
        organization_name=organization_name,
        num_managers=num_managers,
        num_employees=num_employees,
        num_teams=num_teams
    )

    org = db.query(Organization).filter(Organization.name == organization_name).first()
    if not org:
        raise ValueError("Defense organization not found after provisioning")

    employee_profiles = (
        db.query(Profile)
        .join(User, Profile.user_id == User.id)
        .join(TeamMembership, TeamMembership.profile_id == Profile.id)
        .join(Team, TeamMembership.team_id == Team.id)
        .filter(Team.organization_id == org.id, User.role == "EMPLOYEE")
        .all()
    )

    if not employee_profiles:
        employee_profiles = (
            db.query(Profile)
            .join(User, Profile.user_id == User.id)
            .filter(User.role == "EMPLOYEE", Profile.is_test_data == True)
            .all()
        )

    counts = {
        "work_sessions": 0,
        "breaks": 0,
        "lunch_breaks": 0,
        "tasks": 0,
        "recommendations": 0,
        "recommendation_feedback": 0,
        "wellbeing_checkins": 0,
    }

    current_day = start_date
    day_delta = timedelta(days=1)

    behavioral_archetypes = {}
    for idx, p in enumerate(employee_profiles):
        archetype_keys = ["balanced", "extended_work", "missed_breaks", "irregular", "high_workload"]
        behavioral_archetypes[p.id] = archetype_keys[idx % len(archetype_keys)]

    while current_day <= end_date:
        if current_day.weekday() >= 5:
            current_day += day_delta
            continue

        day_start_dt = datetime.combine(current_day, time.min, tzinfo=timezone.utc)
        day_end_dt = datetime.combine(current_day, time.max, tzinfo=timezone.utc)

        try:
            for profile in employee_profiles:
                day_profile_seed = int(hashlib.sha256(f"{profile.id}-{current_day.isoformat()}".encode('utf-8')).hexdigest(), 16) % (2**31)
                random.seed(day_profile_seed)

                existing_session = db.query(WorkSession).filter(
                    WorkSession.profile_id == profile.id,
                    WorkSession.started_at >= day_start_dt,
                    WorkSession.started_at <= day_end_dt
                ).first()

                if existing_session is not None:
                    # Interrupted-run recovery: inspect child records and create only what is missing
                    session_id = existing_session.id

                    has_breaks = db.query(Break).filter_by(work_session_id=session_id).first() is not None
                    has_tasks = db.query(Task).filter_by(work_session_id=session_id).first() is not None
                    has_recs = db.query(Recommendation).filter_by(profile_id=profile.id).filter(
                        Recommendation.generated_at >= day_start_dt, Recommendation.generated_at <= day_end_dt
                    ).first() is not None
                    has_fb = db.query(RecommendationFeedback).filter_by(work_session_id=session_id).first() is not None
                    has_wb = db.query(SessionWellbeingCheckin).filter_by(work_session_id=session_id).first() is not None

                    if has_breaks and has_tasks and has_recs and has_fb and has_wb:
                        continue

                    archetype = behavioral_archetypes.get(profile.id, "balanced")
                    shift_start = profile.shift_start_time or time(9, 0)
                    shift_end = profile.shift_end_time or time(17, 0)
                    start_dt = datetime.combine(current_day, shift_start, tzinfo=timezone.utc)
                    if archetype == "extended_work":
                        shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc) + timedelta(hours=random.choice([1, 1.5]))
                    elif archetype == "irregular":
                        random_offset = timedelta(minutes=random.choice([-45, -30, 15, 30, 60]))
                        start_dt += random_offset
                        shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc) + random_offset
                    else:
                        shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc)

                    if not has_breaks:
                        if archetype != "missed_breaks" or random.random() > 0.6:
                            b_start = start_dt + timedelta(hours=1.5)
                            b_end = b_start + timedelta(minutes=random.choice([10, 15]))
                            if b_end < shift_end_dt:
                                db.add(Break(work_session_id=session_id, break_type="SHORT_BREAK", started_at=b_start, ended_at=b_end))
                                counts["breaks"] += 1
                        lunch_start = start_dt + timedelta(hours=3.5)
                        lunch_dur = random.choice([30, 45, 60])
                        lunch_end = lunch_start + timedelta(minutes=lunch_dur)
                        if lunch_end < shift_end_dt:
                            db.add(Break(work_session_id=session_id, break_type="LUNCH", started_at=lunch_start, ended_at=lunch_end))
                            counts["lunch_breaks"] += 1

                    if not has_tasks:
                        num_tasks = 3 if archetype == "high_workload" else 2
                        for t_idx in range(num_tasks):
                            t_status = "DONE" if archetype != "high_workload" or random.random() > 0.3 else "IN_PROGRESS"
                            db.add(Task(
                                profile_id=profile.id,
                                work_session_id=session_id,
                                title=f"Sprint Task {current_day.strftime('%b %d')} #{t_idx+1}",
                                description=f"Generated historical simulation task for {profile.job_role or 'Employee'}",
                                status=t_status,
                                priority="HIGH" if archetype == "high_workload" else "MEDIUM",
                                category="Development" if t_idx % 2 == 0 else "Planning",
                                estimated_minutes=60,
                                actual_minutes=random.choice([45, 60, 75]),
                                scheduled_start_date=start_dt
                            ))
                            counts["tasks"] += 1

                    if not has_recs or not has_fb:
                        rec_type = random.choice(["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH"])
                        rec = Recommendation(
                            profile_id=profile.id,
                            recommendation_text=f"Synthetic historical recommendation: Take a {rec_type.lower().replace('_', ' ')}.",
                            recommendation_type=rec_type,
                            generated_at=start_dt + timedelta(hours=2.5),
                            is_viewed=True
                        )
                        db.add(rec)
                        db.flush()
                        counts["recommendations"] += 1

                        if not has_fb:
                            action_weights = {"accepted": 0.6, "dismissed": 0.3, "ignored": 0.1}
                            if archetype == "missed_breaks":
                                action_weights = {"accepted": 0.2, "dismissed": 0.5, "ignored": 0.3}
                            elif archetype == "balanced":
                                action_weights = {"accepted": 0.75, "dismissed": 0.2, "ignored": 0.05}
                            action = random.choices(list(action_weights.keys()), weights=list(action_weights.values()))[0]

                            # Phase 8 remediation: populate full V2 wellbeing features in context_features
                            dyn_session_length = random.randint(120, 360)
                            dyn_time_since_break = random.randint(30, 180)
                            dyn_completion_rate = round(random.uniform(0.50, 0.98), 2)

                            # Archetype-dependent wellbeing check-in values with noise
                            if archetype == "balanced":
                                wb_overall = random.choice([3, 4, 5])
                                wb_fatigue = random.choice([1, 2, 3])
                                wb_workload = random.choice([3, 4, 5])
                                wb_focus = random.choice([3, 4, 5])
                                wb_recovery = random.choice([3, 4, 5])
                                wb_stress = 0
                            elif archetype == "missed_breaks":
                                wb_overall = random.choice([1, 2, 3])
                                wb_fatigue = random.choice([3, 4, 5])
                                wb_workload = random.choice([2, 3, 4])
                                wb_focus = random.choice([2, 3])
                                wb_recovery = random.choice([1, 2])
                                wb_stress = 1
                            else:
                                wb_overall = random.randint(1, 5)
                                wb_fatigue = random.randint(1, 5)
                                wb_workload = random.randint(1, 5)
                                wb_focus = random.randint(1, 5)
                                wb_recovery = random.randint(1, 5)
                                wb_stress = random.choice([0, 1])

                            db.add(RecommendationFeedback(
                                user_id=profile.user_id,
                                recommendation_id=rec.id,
                                model_version="synthetic-v2-remediated",
                                recommendation_type=rec_type,
                                recommendation_score=round(random.uniform(0.40, 0.98), 2),
                                context_features={
                                    "session_length": dyn_session_length,
                                    "time_since_break": dyn_time_since_break,
                                    "completion_rate": dyn_completion_rate,
                                    "wellbeing_overall": wb_overall,
                                    "wellbeing_fatigue": wb_fatigue,
                                    "wellbeing_workload": wb_workload,
                                    "wellbeing_focus": wb_focus,
                                    "wellbeing_recovery": wb_recovery,
                                    "wellbeing_stress": wb_stress,
                                    "is_test_data": True,
                                    "dev_demo": True
                                },
                                timestamp=rec.generated_at + timedelta(minutes=5),
                                user_action=action,
                                work_session_id=session_id,
                                feature_schema_version="v2-wellbeing",
                                provenance="synthetic-historical"
                            ))
                            counts["recommendation_feedback"] += 1

                    if not has_wb:
                        db.add(SessionWellbeingCheckin(
                            user_id=profile.user_id,
                            work_session_id=session_id,
                            overall_wellbeing=random.choice([3, 4, 5]) if archetype == "balanced" else random.choice([1, 2, 3]),
                            mental_fatigue=random.choice([1, 2, 3]) if archetype == "balanced" else random.choice([3, 4, 5]),
                            workload_manageability=random.choice([3, 4, 5]) if archetype != "high_workload" else 2,
                            perceived_focus=random.choice([3, 4, 5]) if archetype != "extended_work" else 2,
                            break_recovery=random.choice([3, 4, 5]) if archetype != "missed_breaks" else 1,
                            stress_factors=["Deadlines"] if archetype == "high_workload" else []
                        ))
                        counts["wellbeing_checkins"] += 1

                    continue

                archetype = behavioral_archetypes.get(profile.id, "balanced")

                if archetype == "irregular" and random.random() < 0.15:
                    continue
                elif random.random() < 0.05:
                    continue

                shift_start = profile.shift_start_time or time(9, 0)
                shift_end = profile.shift_end_time or time(17, 0)

                start_dt = datetime.combine(current_day, shift_start, tzinfo=timezone.utc)
                if archetype == "extended_work":
                    shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc) + timedelta(hours=random.choice([1, 1.5]))
                elif archetype == "irregular":
                    random_offset = timedelta(minutes=random.choice([-45, -30, 15, 30, 60]))
                    start_dt += random_offset
                    shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc) + random_offset
                else:
                    shift_end_dt = datetime.combine(current_day, shift_end, tzinfo=timezone.utc)

                # 1. Work Session
                work_session = WorkSession(
                    profile_id=profile.id,
                    started_at=start_dt,
                    ended_at=shift_end_dt
                )
                db.add(work_session)
                db.flush()
                counts["work_sessions"] += 1

                # 2. Breaks
                if archetype != "missed_breaks" or random.random() > 0.6:
                    b_start = start_dt + timedelta(hours=1.5)
                    b_end = b_start + timedelta(minutes=random.choice([10, 15]))
                    if b_end < shift_end_dt:
                        db.add(Break(work_session_id=work_session.id, break_type="SHORT_BREAK", started_at=b_start, ended_at=b_end))
                        counts["breaks"] += 1

                lunch_start = start_dt + timedelta(hours=3.5)
                lunch_dur = random.choice([30, 45, 60])
                lunch_end = lunch_start + timedelta(minutes=lunch_dur)
                if lunch_end < shift_end_dt:
                    db.add(Break(work_session_id=work_session.id, break_type="LUNCH", started_at=lunch_start, ended_at=lunch_end))
                    counts["lunch_breaks"] += 1

                if archetype != "missed_breaks" or random.random() > 0.4:
                    a_start = shift_end_dt - timedelta(hours=2.0)
                    a_end = a_start + timedelta(minutes=random.choice([10, 15]))
                    if a_end < shift_end_dt and a_start > lunch_end:
                        db.add(Break(work_session_id=work_session.id, break_type="SHORT_BREAK", started_at=a_start, ended_at=a_end))
                        counts["breaks"] += 1

                # 3. Tasks
                num_tasks = 3 if archetype == "high_workload" else 2
                for t_idx in range(num_tasks):
                    t_status = "DONE" if archetype != "high_workload" or random.random() > 0.3 else "IN_PROGRESS"
                    task = Task(
                        profile_id=profile.id,
                        work_session_id=work_session.id,
                        title=f"Sprint Task {current_day.strftime('%b %d')} #{t_idx+1}",
                        description=f"Generated historical simulation task for {profile.job_role or 'Employee'}",
                        status=t_status,
                        priority="HIGH" if archetype == "high_workload" else "MEDIUM",
                        category="Development" if t_idx % 2 == 0 else "Planning",
                        estimated_minutes=60,
                        actual_minutes=random.choice([45, 60, 75]),
                        scheduled_start_date=start_dt
                    )
                    db.add(task)
                    counts["tasks"] += 1

                # 4. Recommendations & Feedback
                rec_type = random.choice(["SHORT_BREAK", "WALK", "HYDRATE", "STRETCH"])
                recommendation = Recommendation(
                    profile_id=profile.id,
                    recommendation_text=f"Synthetic historical recommendation: Take a {rec_type.lower().replace('_', ' ')}.",
                    recommendation_type=rec_type,
                    generated_at=start_dt + timedelta(hours=2.5),
                    is_viewed=True
                )
                db.add(recommendation)
                db.flush()
                counts["recommendations"] += 1

                action_weights = {"accepted": 0.6, "dismissed": 0.3, "ignored": 0.1}
                if archetype == "missed_breaks":
                    action_weights = {"accepted": 0.2, "dismissed": 0.5, "ignored": 0.3}
                elif archetype == "balanced":
                    action_weights = {"accepted": 0.75, "dismissed": 0.2, "ignored": 0.05}

                action = random.choices(list(action_weights.keys()), weights=list(action_weights.values()))[0]

                dyn_session_length = random.randint(120, 360)
                dyn_time_since_break = random.randint(30, 180)
                dyn_completion_rate = round(random.uniform(0.50, 0.98), 2)

                if archetype == "balanced":
                    wb_overall = random.choice([3, 4, 5])
                    wb_fatigue = random.choice([1, 2, 3])
                    wb_workload = random.choice([3, 4, 5])
                    wb_focus = random.choice([3, 4, 5])
                    wb_recovery = random.choice([3, 4, 5])
                    wb_stress = 0
                elif archetype == "missed_breaks":
                    wb_overall = random.choice([1, 2, 3])
                    wb_fatigue = random.choice([3, 4, 5])
                    wb_workload = random.choice([2, 3, 4])
                    wb_focus = random.choice([2, 3])
                    wb_recovery = random.choice([1, 2])
                    wb_stress = 1
                else:
                    wb_overall = random.randint(1, 5)
                    wb_fatigue = random.randint(1, 5)
                    wb_workload = random.randint(1, 5)
                    wb_focus = random.randint(1, 5)
                    wb_recovery = random.randint(1, 5)
                    wb_stress = random.choice([0, 1])

                feedback = RecommendationFeedback(
                    user_id=profile.user_id,
                    recommendation_id=recommendation.id,
                    model_version="synthetic-v2-remediated",
                    recommendation_type=rec_type,
                    recommendation_score=round(random.uniform(0.40, 0.98), 2),
                    context_features={
                        "session_length": dyn_session_length,
                        "time_since_break": dyn_time_since_break,
                        "completion_rate": dyn_completion_rate,
                        "wellbeing_overall": wb_overall,
                        "wellbeing_fatigue": wb_fatigue,
                        "wellbeing_workload": wb_workload,
                        "wellbeing_focus": wb_focus,
                        "wellbeing_recovery": wb_recovery,
                        "wellbeing_stress": wb_stress,
                        "is_test_data": True,
                        "dev_demo": True
                    },
                    timestamp=recommendation.generated_at + timedelta(minutes=5),
                    user_action=action,
                    work_session_id=work_session.id,
                    feature_schema_version="v2-wellbeing",
                    provenance="synthetic-historical"
                )
                db.add(feedback)
                counts["recommendation_feedback"] += 1

                # 5. Session Wellbeing Check-In
                wellbeing_checkin = SessionWellbeingCheckin(
                    user_id=profile.user_id,
                    work_session_id=work_session.id,
                    overall_wellbeing=random.choice([3, 4, 5]) if archetype == "balanced" else random.choice([1, 2, 3]),
                    mental_fatigue=random.choice([1, 2, 3]) if archetype == "balanced" else random.choice([3, 4, 5]),
                    workload_manageability=random.choice([3, 4, 5]) if archetype != "high_workload" else 2,
                    perceived_focus=random.choice([3, 4, 5]) if archetype != "extended_work" else 2,
                    break_recovery=random.choice([3, 4, 5]) if archetype != "missed_breaks" else 1,
                    stress_factors=["Deadlines"] if archetype == "high_workload" else []
                )
                db.add(wellbeing_checkin)
                counts["wellbeing_checkins"] += 1

            db.commit()
        except Exception:
            db.rollback()
            raise

        current_day += day_delta

    return {
        "organization_id": str(org.id),
        "organization_name": org.name,
        "date_range": f"{start_date} to {end_date}",
        "total_employees": len(employee_profiles),
        "records_generated": counts,
        "managers_created": provision_summary.get("managers_created", num_managers),
        "employees_created": provision_summary.get("employees_created", num_employees),
        "teams_created": provision_summary.get("teams_created", num_teams),
        "errors": provision_summary.get("errors", [])
    }
