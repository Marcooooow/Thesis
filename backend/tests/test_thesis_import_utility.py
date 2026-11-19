#!/usr/bin/env python3
"""Test suite for thesis demo import utility: user settings, scoped org/teams, provenance, destination errors, conflicts, and dry-run safety."""
import sys, unittest, os
from unittest.mock import patch
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tools.import_thesis_demo import ALLOWLIST, THESIS_ORG_NAME, run_import, inventory_destination

class ImportUtilityTests(unittest.TestCase):
    def test_allowlist_contains_23_account(self):
        self.assertEqual(len(ALLOWLIST), 23)
        self.assertIn("thesis.admin@intellibreak.local", ALLOWLIST)
        self.assertIn("thesis.employee20@intellibreak.local", ALLOWLIST)

    def test_excludes_mltest_employee(self):
        self.assertNotIn("mltest_employee", ALLOWLIST)
        for e in ALLOWLIST:
            self.assertNotIn("mltest", e)

    @patch("tools.import_thesis_demo.inventory_source")
    @patch("tools.import_thesis_demo.inventory_destination", return_value={"connected": False, "status": "MISSING_DESTINATION_URL"})
    def test_missing_destination_url_handling(self, mock_dest_inv, mock_src_inv):
        mock_src_inv.return_value = {
            "demo_users_count": 23,
            "organizations": [{"id": "org-1", "name": THESIS_ORG_NAME}],
            "teams": [{"id": "t1", "name": "Team A"}, {"id": "t2", "name": "Team B"}],
            "organization_memberships": [],
            "team_memberships": [],
            "profiles": [],
            "user_settings_count": 23,
            "work_sessions": [],
            "breaks_count": 0,
            "tasks_count": 0,
            "session_wellbeing_checkins_count": 0,
            "recommendation_feedback_breakdown": {"live": 102, "historical_reconstruction": 49},
            "recommendation_feedback_total": 151
        }
        result = run_import("sqlite:///:memory:", "", dry_run=True)
        self.assertEqual(result.get("status"), "DESTINATION_NOT_CONFIGURED")
        self.assertEqual(result.get("statements_executed"), 0)

    @patch("tools.import_thesis_demo.inventory_source")
    @patch("tools.import_thesis_demo.inventory_destination", return_value={"connected": False, "status": "CONNECTION_FAILED"})
    def test_destination_connection_failure_handling(self, mock_dest_inv, mock_src_inv):
        mock_src_inv.return_value = {
            "demo_users_count": 23,
            "organizations": [{"id": "org-1", "name": THESIS_ORG_NAME}],
            "teams": [{"id": "t1", "name": "Team A"}, {"id": "t2", "name": "Team B"}],
            "organization_memberships": [],
            "team_memberships": [],
            "profiles": [],
            "user_settings_count": 23,
            "work_sessions": [],
            "breaks_count": 0,
            "tasks_count": 0,
            "session_wellbeing_checkins_count": 0,
            "recommendation_feedback_breakdown": {"live": 102, "historical_reconstruction": 49},
            "recommendation_feedback_total": 151
        }
        result = run_import("sqlite:///:memory:", "postgresql://invalid", dry_run=True)
        self.assertEqual(result.get("status"), "DESTINATION_CONNECTION_FAILED")

    @patch("tools.import_thesis_demo.inventory_source")
    @patch("tools.import_thesis_demo.inventory_destination")
    def test_existing_destination_conflict_handling(self, mock_dest_inv, mock_src_inv):
        mock_src_inv.return_value = {
            "demo_users_count": 23,
            "organizations": [{"id": "org-1", "name": THESIS_ORG_NAME}],
            "teams": [{"id": "t1", "name": "Team A"}, {"id": "t2", "name": "Team B"}],
            "organization_memberships": [],
            "team_memberships": [],
            "profiles": [],
            "user_settings_count": 23,
            "work_sessions": [],
            "breaks_count": 0,
            "tasks_count": 0,
            "session_wellbeing_checkins_count": 0,
            "recommendation_feedback_breakdown": {"live": 102, "historical_reconstruction": 49},
            "recommendation_feedback_total": 151
        }
        mock_dest_inv.return_value = {
            "connected": True,
            "status": "CONNECTED",
            "existing_demo_users": [{"id": "123", "email": "thesis.admin@intellibreak.local", "role": "ADMIN", "approval_status": "APPROVED"}],
            "existing_demo_users_count": 1
        }
        result = run_import("sqlite:///:memory:", "sqlite:///:memory:", dry_run=True)
        self.assertEqual(result.get("status"), "BLOCKED_BY_CONFLICTS")
        self.assertTrue(len(result.get("conflicts")) > 0)

    @patch("tools.import_thesis_demo.inventory_source")
    @patch("tools.import_thesis_demo.inventory_destination", return_value={"connected": False, "status": "MISSING_DESTINATION_URL"})
    def test_dry_run_write_protection_and_provenance(self, mock_dest_inv, mock_src_inv):
        mock_src_inv.return_value = {
            "demo_users_count": 23,
            "organizations": [{"id": "org-1", "name": THESIS_ORG_NAME}],
            "teams": [{"id": "t1", "name": "Team A"}, {"id": "t2", "name": "Team B"}],
            "organization_memberships": [],
            "team_memberships": [],
            "profiles": [],
            "user_settings_count": 23,
            "work_sessions": [{"id": "s1"}],
            "breaks_count": 5,
            "tasks_count": 10,
            "session_wellbeing_checkins_count": 8,
            "recommendation_feedback_breakdown": {"live": 102, "historical_reconstruction": 49},
            "recommendation_feedback_total": 151
        }
        result = run_import("sqlite:///:memory:", "", dry_run=True)
        self.assertEqual(result.get("statements_executed"), 0)
        fb = result.get("source_inventory", {}).get("recommendation_feedback", {}).get("breakdown", {})
        self.assertEqual(fb.get("live"), 102)
        self.assertEqual(fb.get("historical_reconstruction"), 49)

    def test_inventory_destination_empty_url(self):
        res = inventory_destination("")
        self.assertFalse(res["connected"])
        self.assertEqual(res["status"], "MISSING_DESTINATION_URL")

if __name__ == "__main__":
    unittest.main(verbosity=2)
