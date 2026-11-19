import pytest
from sqlalchemy.orm import Session
from app.models import User, Organization, OrganizationMembership
from app.auth.security import should_include_test_data, get_password_hash

def test_defense_manager_can_include_test_data(test_db: Session):
    org = Organization(name="IntelliBreak Defense Organization")
    test_db.add(org)
    test_db.commit()

    manager = User(
        email="defense.manager@intellibreak.local",
        full_name="Defense Manager",
        role="MANAGER",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass123")
    )
    test_db.add(manager)
    test_db.commit()

    membership = OrganizationMembership(
        user_id=manager.id,
        organization_id=org.id,
        role="MANAGER",
        status="APPROVED"
    )
    test_db.add(membership)
    test_db.commit()

    assert should_include_test_data(test_db, manager) is True

def test_unrelated_user_cannot_include_test_data(test_db: Session):
    org_defense = Organization(name="IntelliBreak Defense Organization")
    org_other = Organization(name="Other Organization")
    test_db.add_all([org_defense, org_other])
    test_db.commit()

    user = User(
        email="other.user@intellibreak.local",
        full_name="Other User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass123")
    )
    test_db.add(user)
    test_db.commit()

    membership = OrganizationMembership(
        user_id=user.id,
        organization_id=org_other.id,
        role="EMPLOYEE",
        status="APPROVED"
    )
    test_db.add(membership)
    test_db.commit()

    assert should_include_test_data(test_db, user) is False

def test_pending_membership_cannot_include_test_data(test_db: Session):
    org = Organization(name="IntelliBreak Defense Organization")
    test_db.add(org)
    test_db.commit()

    user = User(
        email="pending.user@intellibreak.local",
        full_name="Pending User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("testpass123")
    )
    test_db.add(user)
    test_db.commit()

    membership = OrganizationMembership(
        user_id=user.id,
        organization_id=org.id,
        role="EMPLOYEE",
        status="PENDING"
    )
    test_db.add(membership)
    test_db.commit()

    assert should_include_test_data(test_db, user) is False
