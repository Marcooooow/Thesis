import uuid
import pytest
from fastapi import HTTPException

from app.models import Organization, OrganizationMembership, Profile, Team, TeamMembership, User
from app.services.diverse_provisioning_service import provision_diverse_defense_organization


def test_provision_diverse_defense_organization_readiness(test_db):
    admin = User(
        email=f"org-admin-{uuid.uuid4()}@test.local",
        full_name="Org Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name=f"Defense Org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    summary = provision_diverse_defense_organization(
        test_db,
        current_user=admin,
        organization_name=org.name,
        num_managers=4,
        num_employees=20,
        num_teams=5,
    )

    assert summary["managers_created"] == 4
    assert summary["employees_created"] == 20
    assert summary["teams_created"] >= 1
    assert not summary["errors"]

    # Verify idempotency (rerun should not duplicate or error)
    summary_rerun = provision_diverse_defense_organization(
        test_db,
        current_user=admin,
        organization_name=org.name,
        num_managers=4,
        num_employees=20,
        num_teams=5,
    )
    assert summary_rerun["managers_created"] == 4
    assert summary_rerun["employees_created"] == 20

    # Verify profile completeness, schedule diversity, and test data flags
    profiles = test_db.query(Profile).join(User, Profile.user_id == User.id).filter(User.role == "EMPLOYEE").all()
    assert len(profiles) == 20

    start_times = set()
    for p in profiles:
        assert p.is_test_data is True
        assert p.age is not None
        assert p.gender is not None
        assert p.education_attainment is not None
        assert p.marital_status is not None
        assert p.job_role is not None
        assert p.industry is not None
        assert p.years_of_experience is not None
        assert p.shift_start_time is not None
        assert p.shift_end_time is not None
        assert p.work_days is not None
        start_times.add(p.shift_start_time)

    # Ensure schedule variation exists across the 20 employees
    assert len(start_times) > 1
