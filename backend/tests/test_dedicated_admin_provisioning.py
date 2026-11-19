import uuid
import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models import User, Organization, OrganizationMembership, Profile, Team, TeamMembership
from app.services.diverse_provisioning_service import provision_diverse_defense_organization


def test_dedicated_defense_admin_creation_and_scoping(test_db):
    admin = User(
        email=f"admin-creator-{uuid.uuid4()}@test.local",
        full_name="Creator Admin",
        password_hash="hash",
        role="ADMIN",
        approval_status="APPROVED",
        is_active=True,
    )
    test_db.add(admin)
    test_db.flush()
    org = Organization(name="IntelliBreak Defense Organization")
    test_db.add(org)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    summary = provision_diverse_defense_organization(
        test_db,
        current_user=admin,
        organization_name=org.name,
        num_managers=2,
        num_employees=3,
        num_teams=2,
    )

    assert summary["managers_created"] == 2
    assert summary["employees_created"] == 3

    # Verify admin membership count is exactly 1 for the defense org
    admin_mems = test_db.query(OrganizationMembership).filter_by(organization_id=org.id, role="ADMIN").all()
    assert len(admin_mems) == 1

    # Confirm employees are not admins
    emp_users = test_db.query(User).join(OrganizationMembership).filter(
        OrganizationMembership.organization_id == org.id, OrganizationMembership.role == "EMPLOYEE"
    ).all()
    for eu in emp_users:
        assert eu.role == "EMPLOYEE"
