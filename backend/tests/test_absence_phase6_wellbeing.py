import pytest
from datetime import date, datetime, timezone, timedelta
import uuid
from app.services.wellbeing_monitoring import WellbeingMonitoringService
from app.schemas.wellbeing_monitoring import RiskTier, EvidenceType
from app import models
from app.auth.security import get_password_hash

def test_phase6_rtw_signal_separation(test_db):
    """Verify signal separation: wants_manager_support generates support recommendations without evidence classification, while work_contributed_to_absence adds supplemental contextual evidence."""
    service = WellbeingMonitoringService(test_db)
    user = models.User(
        email=f"phase6_sep_{uuid.uuid4()}@test.com",
        full_name="Phase6 Signal User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(user)
    test_db.commit()

    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    # Create 3 sessions and 2 check-ins to satisfy data quality gate (Tier 1+)
    sessions = []
    for i in range(3):
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=datetime(2026, 11, 2 + i, 9, 0, tzinfo=timezone.utc),
            ended_at=datetime(2026, 11, 2 + i, 17, 0, tzinfo=timezone.utc)
        )
        test_db.add(session)
        test_db.commit()
        sessions.append(session)
        if i < 2:
            checkin = models.SessionWellbeingCheckin(
                user_id=user.id,
                work_session_id=session.id,
                overall_wellbeing=5,
                mental_fatigue=1,
                workload_manageability=5,
                perceived_focus=5,
                break_recovery=5
            )
            test_db.add(checkin)
            test_db.commit()

    # RTW checkin with wants_manager_support = True, work_contributed_to_absence = False
    rtw1 = models.ReturnToWorkCheckin(
        profile_id=profile.id,
        work_session_id=sessions[0].id,
        absence_reason_category="Personal",
        overall_feeling=4,
        workload_concern=1,
        stress_concern=1,
        work_contributed_to_absence=False,
        wants_manager_support=True,
        additional_comments="Private notes",
        is_manager_visible=True,
        submitted_at=datetime(2026, 11, 2, 18, 0, tzinfo=timezone.utc)
    )
    test_db.add(rtw1)
    test_db.commit()

    detail = service.compute_weekly_risk(profile.id, date(2026, 11, 2))
    assert detail.risk_tier in (RiskTier.LOW, RiskTier.MODERATE)
    # wants_manager_support should generate recommendation but NOT add WELLBEING_DECLINING evidence item
    assert any("manager support" in act.lower() for act in detail.recommended_actions)
    assert not any(item.type == EvidenceType.WELLBEING_DECLINING for item in detail.evidence_items)

    # Now test work_contributed_to_absence = True
    rtw1.work_contributed_to_absence = True
    test_db.commit()

    detail2 = service.compute_weekly_risk(profile.id, date(2026, 11, 2))
    assert detail2.risk_tier in (RiskTier.LOW, RiskTier.MODERATE)
    # work_contributed_to_absence adds supplemental contextual evidence
    assert any(item.type == EvidenceType.WELLBEING_DECLINING for item in detail2.evidence_items)


def test_phase6_rtw_utc_half_open_boundary(test_db):
    """Verify half-open UTC interval filtering [week_start_utc, next_week_start_utc) excludes adjacent weeks."""
    service = WellbeingMonitoringService(test_db)
    user = models.User(
        email=f"phase6_bnd_{uuid.uuid4()}@test.com",
        full_name="Phase6 Boundary User",
        role="EMPLOYEE",
        approval_status="APPROVED",
        is_active=True,
        password_hash=get_password_hash("test")
    )
    test_db.add(user)
    test_db.commit()
    profile = models.Profile(user_id=user.id, target_daily_hours=8)
    test_db.add(profile)
    test_db.commit()

    # Create 3 sessions and 2 check-ins for week starting 2026-11-02
    for i in range(3):
        session = models.WorkSession(
            profile_id=profile.id,
            started_at=datetime(2026, 11, 2 + i, 9, 0, tzinfo=timezone.utc),
            ended_at=datetime(2026, 11, 2 + i, 17, 0, tzinfo=timezone.utc)
        )
        test_db.add(session)
        test_db.commit()
        if i < 2:
            checkin = models.SessionWellbeingCheckin(
                user_id=user.id,
                work_session_id=session.id,
                overall_wellbeing=5,
                mental_fatigue=1,
                workload_manageability=5,
                perceived_focus=5,
                break_recovery=5
            )
            test_db.add(checkin)
            test_db.commit()

    ws_outside = models.WorkSession(
        profile_id=profile.id,
        started_at=datetime(2026, 11, 9, 9, 0, tzinfo=timezone.utc),
        ended_at=datetime(2026, 11, 9, 17, 0, tzinfo=timezone.utc)
    )
    test_db.add(ws_outside)
    test_db.commit()

    # RTW checkin submitted outside the week (e.g. next Monday 2026-11-09)
    rtw_outside = models.ReturnToWorkCheckin(
        profile_id=profile.id,
        work_session_id=ws_outside.id,
        absence_reason_category="Other",
        work_contributed_to_absence=True,
        submitted_at=datetime(2026, 11, 9, 0, 0, tzinfo=timezone.utc) # Next Monday boundary
    )
    test_db.add(rtw_outside)
    test_db.commit()

    # Compute weekly risk for week starting 2026-11-02
    detail = service.compute_weekly_risk(profile.id, date(2026, 11, 2))
    # Should not include rtw_outside submitted at 2026-11-09
    assert not any("work factors contributed" in item.description for item in detail.evidence_items)
