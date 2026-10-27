import unittest
from run_axel_texture_phase import requeue_controls_match


class RequeueSampleControls(unittest.TestCase):
    def test_reports_must_match_both_requested_controls(self):
        for legacy in (True, False):
            for suppressed in (True, False):
                report = {"controls": {"dirty_requeue_index": not legacy,
                                       "selective_requeue_membership": not legacy},
                          "sync_slow_logs_suppressed": suppressed}
                self.assertTrue(requeue_controls_match(report, legacy, suppressed))
                self.assertFalse(requeue_controls_match(report, not legacy, suppressed))
                self.assertFalse(requeue_controls_match(report, legacy, not suppressed))

    def test_missing_partial_or_non_boolean_state_is_not_evidence(self):
        for report in ({}, {"controls": []},
                       {"controls": {"dirty_requeue_index": True}},
                       {"controls": {"dirty_requeue_index": 1, "selective_requeue_membership": True},
                        "sync_slow_logs_suppressed": False}):
            self.assertFalse(requeue_controls_match(report, False, False))


if __name__ == "__main__":
    unittest.main()
