import uuid

import pytest
from fastapi import HTTPException

from app.models import Organization, OrganizationMembership, Profile, Team, TeamMembership, User
from app.services.account_provisioning_service import provision_account


def _admin_for_org(db, org):
    admin = User(email=f"admin-{uuid.uuid4()}@test.local", full_name="Defense Admin", password_hash="hash", role="ADMIN", approval_status="APPROVED", is_active=True)
    db.add(admin)
    db.flush()
    db.add(OrganizationMembership(user_id=admin.id, organization_id=org.id, role="ADMIN", status="APPROVED"))
    db.commit()
    return admin


def test_provision_account_creates_user_profile_org_and_team_membership(test_db):
    org = Organization(name=f"Provision org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    admin = _admin_for_org(test_db, org)
    manager = User(email=f"manager-{uuid.uuid4()}@test.local", full_name="Manager", password_hash="hash", role="MANAGER", approval_status="APPROVED", is_active=True)
    test_db.add(manager)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=manager.id, organization_id=org.id, role="MANAGER", status="APPROVED"))
    team = Team(name=f"Provision team {uuid.uuid4()}", organization_id=org.id, manager_user_id=manager.id, is_active=True)
    test_db.add(team)
    test_db.commit()

    user = provision_account(
        test_db,
        current_user=admin,
        email=f"employee-{uuid.uuid4()}@test.local",
        full_name="Fictional Employee",
        password="SecureProvisionPass123!",
        role="EMPLOYEE",
        organization_id=org.id,
        team_id=team.id,
    )

    assert test_db.query(User).filter_by(id=user.id).one().role == "EMPLOYEE"
    profile = test_db.query(Profile).filter_by(user_id=user.id).one()
    assert profile.is_test_data is True
    assert test_db.query(OrganizationMembership).filter_by(user_id=user.id, organization_id=org.id, status="APPROVED").count() == 1
    assert test_db.query(TeamMembership).filter_by(profile_id=profile.id, team_id=team.id, left_at=None).count() == 1
    assert user.password_hash != "SecureProvisionPass123!"


def test_provision_account_is_idempotent_when_account_exists(test_db):
    org = Organization(name=f"Idempotent org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    admin = _admin_for_org(test_db, org)
    email = f"idempotent-{uuid.uuid4()}@test.local"

    first = provision_account(
        test_db,
        current_user=admin,
        email=email,
        full_name="Idempotent Person",
        password="SecureProvisionPass123!",
        role="EMPLOYEE",
        organization_id=org.id,
    )
    second = provision_account(
        test_db,
        current_user=admin,
        email=email,
        full_name="Idempotent Person",
        password="SecureProvisionPass123!",
        role="EMPLOYEE",
        organization_id=org.id,
    )
    assert first.id == second.id
    assert test_db.query(User).filter_by(email=email).count() == 1


def test_provision_account_rejects_unauthorized_caller(test_db):
    org_a = Organization(name=f"Org A {uuid.uuid4()}")
    org_b = Organization(name=f"Org B {uuid.uuid4()}")
    test_db.add_all([org_a, org_b])
    test_db.flush()
    outsider = User(email=f"outsider-{uuid.uuid4()}@test.local", full_name="Outsider", password_hash="hash", role="ADMIN", approval_status="APPROVED", is_active=True)
    test_db.add(outsider)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=outsider.id, organization_id=org_b.id, role="ADMIN", status="APPROVED"))
    test_db.commit()

    with pytest.raises(HTTPException) as exc:
        provision_account(
            test_db,
            current_user=outsider,
            email=f"new-{uuid.uuid4()}@test.local",
            full_name="Test",
            password="SecureProvisionPass123!",
            role="EMPLOYEE",
            organization_id=org_a.id,
        )
    assert exc.value.status_code == 403


def test_provision_account_rejects_weak_password(test_db):
    org = Organization(name=f"Weak pwd org {uuid.uuid4()}")
    test_db.add(org)
    test_db.flush()
    admin = _admin_for_org(test_db, org)

    with pytest.raises(ValueError, match="Password must be at least 12 characters"):
        provision_account(
            test_db,
            current_user=admin,
            email=f"weak-{uuid.uuid4()}@test.local",
            full_name="Weak Pwd",
            password="short",
            role="EMPLOYEE",
            organization_id=org.id,
        )


def test_provision_account_rolls_back_when_team_is_from_another_org(test_db):
    org_a = Organization(name=f"Rollback A {uuid.uuid4()}")
    org_b = Organization(name=f"Rollback B {uuid.uuid4()}")
    test_db.add_all([org_a, org_b])
    test_db.flush()
    admin = _admin_for_org(test_db, org_a)
    manager = User(email=f"manager-{uuid.uuid4()}@test.local", full_name="Manager", password_hash="hash", role="MANAGER", approval_status="APPROVED", is_active=True)
    test_db.add(manager)
    test_db.flush()
    test_db.add(OrganizationMembership(user_id=manager.id, organization_id=org_b.id, role="MANAGER", status="APPROVED"))
    team = Team(name=f"Foreign team {uuid.uuid4()}", organization_id=org_b.id, manager_user_id=manager.id, is_active=True)
    test_db.add(team)
    test_db.commit()
    email = f"rollback-{uuid.uuid4()}@test.local"

    with pytest.raises(ValueError, match="organization"):
        provision_account(
            test_db,
            current_user=admin,
            email=email,
            full_name="Rollback Candidate",
            password="SecureProvisionPass123!",
            role="EMPLOYEE",
            organization_id=org_a.id,
            team_id=team.id,
        )
    assert test_db.query(User).filter_by(email=email).count() == 0
    assert test_db.query(Profile).filter(Profile.user_id.in_(test_db.query(User.id).filter_by(email=email))).count() == 0
