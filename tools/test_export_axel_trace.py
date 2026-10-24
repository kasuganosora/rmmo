"""Pure offline contracts; no engine, map or external dependency."""
import copy
import unittest

from export_axel_trace import API_NAMES, MAX_FRAME, InvalidEvidence, export_trace


def evidence():
    report = {"pid": 123, "begin_ticks_us": 1000,
              "frames": [{"at_ms": 2, "ms": 2, "engine_frame": 7, "phase": "return"}],
              "capacity_timeline": {"columns": ["at_us", "jobs", "live_workers"], "samples": [[2000, 6, 0]]},
              "map_profile": {"asset_admission_details": {"tasks": {"native.scn": {"stages": [
                  {"stage": "compiled_read", "dispatched_us": 1100, "worker_started_us": 1200,
                   "worker_finished_us": 1800, "joined_us": 1900, "worker_us": 600, "error": 0}
              ]}}}}}
    native = {"schema": 185, "pid": 123, "complete": True, "quiescent": True,
              "event_coverage_complete": True, "initialized_ticks_us": 100, "threshold_us": 10,
              "api_names": API_NAMES.copy(), "selected_events": 1, "written_events": 1,
              "evicted_ticket_prefix": 0, "contention_drops": 0, "invalid_records": 0,
              "transfer_coverage": dict.fromkeys(["pending_drops", "lease_overflow", "lease_unmatched",
                                                  "lease_duplicate", "lease_residual", "active_leases"], 0),
              "events": [{"seq": 0, "begin_us": 1500, "end_us": 1520, "api": 9,
                          "thread_id": 33, "native_tid": 777, "frame": MAX_FRAME, "flags": 0,
                          "device": 10000, "queue": 2, "object": 9007199254740999,
                          "lease_id": 9007199254740997, "result": 0}],
              "aggregates": [{"api": i, "calls": int(i == 9), "over_threshold": int(i == 9)} for i in range(10)]}
    return report, native


class ExportTests(unittest.TestCase):
    def test_exact_spans_separate_observations_no_edges(self):
        report, native = evidence()
        trace, coverage = export_trace(report, native)
        rows = trace["traceEvents"]
        self.assertTrue(coverage["accepted"])
        self.assertFalse(coverage["complete_critical_path"])
        self.assertEqual(coverage["dependency_edges"], 0)
        self.assertTrue(all(row["ph"] in ["X", "i", "C", "M"] for row in rows))
        api = next(row for row in rows if row.get("cat") == "native185.api_wall")
        self.assertEqual((api["ts"], api["dur"]), (1500, 20))
        self.assertEqual(api["args"]["device_namespace"], "RenderingDevice")
        self.assertEqual(api["args"]["engine_process_frame"], "unknown")
        self.assertEqual(api["args"]["gpu_frame"], "unknown")
        self.assertEqual(api["args"]["object"], "9007199254740999")
        frame = next(row for row in rows if row.get("cat") == "observation.frame_wall")
        self.assertNotEqual(frame["tid"], api["tid"])
        self.assertEqual((frame["ts"], frame["dur"]), (1000, 2000))
        counter = next(row for row in rows if row["ph"] == "C")
        self.assertEqual(counter["args"], {"jobs": 6, "live_workers": 0})

    def test_missing_model_end_never_derived_from_elapsed(self):
        report, _ = evidence()
        stage = report["map_profile"]["asset_admission_details"]["tasks"]["native.scn"]["stages"][0]
        stage.pop("worker_finished_us")
        trace, coverage = export_trace(report)
        self.assertEqual(len(coverage["initial_model_skips"]), 1)
        self.assertFalse(any(row.get("cat") == "initial_model.worker_wall" for row in trace["traceEvents"]))

    def test_native_loss_rejected(self):
        for key in ["evicted_ticket_prefix", "contention_drops", "invalid_records"]:
            report, native = evidence()
            native[key] = 1
            with self.subTest(key=key), self.assertRaises(InvalidEvidence):
                export_trace(report, native)
        report, native = evidence()
        native["transfer_coverage"]["lease_unmatched"] = 1
        with self.assertRaises(InvalidEvidence):
            export_trace(report, native)

    def test_sequence_or_aggregate_loss_rejected(self):
        for mutate in [lambda n: n["events"][0].update(seq=1),
                       lambda n: n.update(selected_events=2),
                       lambda n: n["aggregates"][9].update(over_threshold=0)]:
            report, native = evidence()
            mutate(native)
            with self.assertRaises(InvalidEvidence):
                export_trace(report, native)

    def test_clock_and_identity_failures_rejected(self):
        for mutate in [lambda n: n.update(pid=999),
                       lambda n: n.update(initialized_ticks_us=2000),
                       lambda n: n["events"][0].update(end_us=1000),
                       lambda n: n["events"][0].update(native_tid=0),
                       lambda n: n["events"][0].update(flags=1, frame=7)]:
            report, native = evidence()
            mutate(native)
            with self.assertRaises(InvalidEvidence):
                export_trace(report, native)

    def test_model_clock_contradiction_rejected(self):
        report, _ = evidence()
        stage = report["map_profile"]["asset_admission_details"]["tasks"]["native.scn"]["stages"][0]
        stage["joined_us"] = 1300
        with self.assertRaises(InvalidEvidence):
            export_trace(report)

    def test_completed_markers_preserve_identity_without_fabricated_service(self):
        report, _ = evidence()
        report["publication_audit_v178"] = {"trace": {"dropped": 0, "timebase": "absolute_godot_ticks_us",
            "origin_us": 1000, "events": [
                {"path": "native.scn", "generation": -9223371785213310981,
                 "at_us": 2000, "event": "accepted", "details": {}},
                {"path": "native.scn", "generation": -9223371785213310981,
                 "at_us": 3000, "event": "committed", "details": {"uuid": "house"}}
            ]}}
        trace, _ = export_trace(report)
        rows = [r for r in trace["traceEvents"] if r.get("cat", "").startswith("completed_job")]
        self.assertEqual([r["ph"] for r in rows], ["i", "i"])
        self.assertEqual(rows[0]["args"]["generation"], "-9223371785213310981")
        damaged = copy.deepcopy(report)
        damaged["publication_audit_v178"]["trace"]["dropped"] = 1
        with self.assertRaises(InvalidEvidence):
            export_trace(damaged)
        damaged["publication_audit_v178"]["trace"]["dropped"] = 0
        damaged["publication_audit_v178"]["trace"]["origin_us"] = 1001
        with self.assertRaises(InvalidEvidence):
            export_trace(damaged)

    def test_failed_source_validation_rejected(self):
        report, native = evidence()
        with self.assertRaises(InvalidEvidence):
            export_trace(report, native, {"accepted": False})
        with self.assertRaises(InvalidEvidence):
            export_trace(report, native, {"accepted": True, "checks": {"native_clock": False}})

    def test_retained_legacy_failure_list_is_preserved_not_hidden(self):
        report, native = evidence()
        validation = {"accepted": True, "checks": {"native_clock": True},
                      "failed_checks": ["selected_work_counts_complete_match"]}
        _, coverage = export_trace(report, native, validation)
        self.assertEqual(coverage["upstream_retained_failed_checks"], validation["failed_checks"])
        self.assertEqual(coverage["upstream_current_failed_checks"], [])
        self.assertTrue(any("metadata inconsistency" in gap for gap in coverage["gaps"]))


if __name__ == "__main__":
    unittest.main()
