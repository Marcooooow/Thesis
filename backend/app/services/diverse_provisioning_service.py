import uuid
from typing import List, Dict, Any, Optional
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from datetime import time

from .account_provisioning_service import provision_account
from ..models import User, Organization, Team, OrganizationMembership, TeamMembership, Profile
from ..auth.security import get_organization_ids_for_user


def provision_diverse_defense_organization(
    db: Session,
    *,
    current_user: User,
    organization_name: str = "IntelliBreak Defense Organization",
    num_managers: int = 4,
    num_employees: int = 20,
    num_teams: int = 5,
    default_password: str = "DefenseDemo2026!"
) -> Dict[str, Any]:
    """
    Provision 1 organization, `num_managers` managers, `num_teams` teams with globally unique names,
    and `num_employees` employees with diverse, realistic fictional profiles, work schedules, and valid team/org assignments.
    Idempotent and strictly protected against non-admin callers.
    """
    admin_orgs = get_organization_ids_for_user(db, current_user.id)
    if current_user.role.upper() != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only admins can provision defense organizations")

    # Find or create defense organization (Idempotent)
    org = db.query(Organization).filter(Organization.name == organization_name).first()
    if not org:
        org = Organization(name=organization_name)
        db.add(org)
        db.flush()
        membership = db.query(OrganizationMembership).filter_by(user_id=current_user.id, organization_id=org.id).first()
        if not membership:
            db.add(OrganizationMembership(user_id=current_user.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
        db.commit()
        db.refresh(org)

    summary = {
        "organization_id": str(org.id),
        "organization_name": org.name,
        "managers_created": 0,
        "teams_created": 0,
        "employees_created": 0,
        "errors": []
    }

    # Diverse attributes for realistic distribution
    genders = ["Female", "Male", "Non-Binary", "Prefer Not to Say"]
    educations = ["Bachelor's", "Master's", "Doctorate", "Associate's", "High School"]
    marital_statuses = ["Single", "Married", "Partnered", "Divorced"]
    job_roles = [
        "Software Engineer", "Senior Developer", "Product Manager", "UX Designer",
        "Data Analyst", "DevOps Engineer", "QA Specialist", "Frontend Developer",
        "Backend Developer", "Scrum Master", "Security Engineer", "Technical Writer"
    ]
    industries = ["Technology", "SaaS", "Financial Technology", "Enterprise Software", "Cloud Infrastructure"]

    schedule_variants = [
        (time(8, 0), time(16, 0), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]),
        (time(9, 0), time(17, 0), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]),
        (time(10, 0), time(18, 0), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]),
        (time(7, 0), time(15, 0), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]),
        (time(9, 0), time(15, 0), ["Tuesday", "Wednesday", "Thursday"]),
    ]

    teams = db.query(Team).filter(Team.organization_id == org.id, Team.is_active == True).all()

    # 1. Provision Managers
    manager_users = []
    manager_names = ["Elena Vance", "Marcus Chen", "Sarah Jenkins", "David Okafor", "Priya Nair", "Liam O'Connor"]
    for i in range(num_managers):
        m_name = manager_names[i % len(manager_names)]
        m_email = f"manager.{i+1}.{org.id.hex[:6]}@defense.intellibreak.local"
        try:
            mgr = provision_account(
                db,
                current_user=current_user,
                email=m_email,
                full_name=m_name,
                password=default_password,
                role="MANAGER",
                organization_id=org.id
            )
            manager_users.append(mgr)
            summary["managers_created"] += 1
        except Exception as e:
            summary["errors"].append(f"Manager {m_email}: {str(e)}")

    if not teams and manager_users:
        # Use globally unique defense team names to respect uq_teams_name constraint without modifying other orgs
        team_base_names = [
            "Defense Alpha Engineering",
            "Defense Beta Product",
            "Defense Gamma Data",
            "Defense Delta Platform",
            "Defense Omega Security"
        ]
        for i in range(num_teams):
            t_name = f"{team_base_names[i % len(team_base_names)]} ({org.id.hex[:4]})"
            assigned_mgr = manager_users[i % len(manager_users)]
            team = db.query(Team).filter(Team.organization_id == org.id, Team.name == t_name).first()
            if not team:
                team = Team(
                    name=t_name,
                    description=f"Defense simulation team {t_name}",
                    organization_id=org.id,
                    manager_user_id=assigned_mgr.id,
                    is_active=True
                )
                db.add(team)
                db.flush()
                summary["teams_created"] += 1
        db.commit()
        teams = db.query(Team).filter(Team.organization_id == org.id, Team.is_active == True).all()

    # 2. Provision Employees with diverse profiles & schedules
    first_names = ["Alex", "Jordan", "Taylor", "Morgan", "Sam", "Casey", "Riley", "Avery", "Jamie", "Quinn", "Skyler", "Dakota", "Reese", "Rowan", "Emerson", "Finley", "Logan", "Peyton", "Cameron", "Jesse"]
    last_names = ["Smith", "Patel", "Garcia", "Kim", "Mueller", "Johansson", "Wong", "Rossi", "Silva", "Kowalski", "Dubois", "Tanaka", "O'Neill", "Bakker", "Novak", "Santos", "Ali", "Murphy", "Meyer", "Tan"]

    for i in range(num_employees):
        f_name = first_names[i % len(first_names)]
        l_name = last_names[(i * 3) % len(last_names)]
        emp_name = f"{f_name} {l_name} ({i+1})"
        emp_email = f"employee.{i+1}.{org.id.hex[:6]}@defense.intellibreak.local"
        assigned_team = teams[i % len(teams)] if teams else None

        try:
            emp = provision_account(
                db,
                current_user=current_user,
                email=emp_email,
                full_name=emp_name,
                password=default_password,
                role="EMPLOYEE",
                organization_id=org.id,
                team_id=assigned_team.id if assigned_team else None
            )

            profile = db.query(Profile).filter_by(user_id=emp.id).first()
            if profile:
                profile.age = 24 + (i * 3) % 36
                profile.gender = genders[i % len(genders)]
                profile.education_attainment = educations[i % len(educations)]
                profile.marital_status = marital_statuses[i % len(marital_statuses)]
                profile.job_role = job_roles[i % len(job_roles)]
                profile.industry = industries[i % len(industries)]
                profile.years_of_experience = 1 + (i * 2) % 18
                profile.target_daily_hours = 8

                s_start, s_end, w_days = schedule_variants[i % len(schedule_variants)]
                profile.shift_start_time = s_start
                profile.shift_end_time = s_end
                profile.work_days = w_days
                profile.is_test_data = True

                db.commit()

            summary["employees_created"] += 1
        except Exception as e:
            summary["errors"].append(f"Employee {emp_email}: {str(e)}")

    return summary
