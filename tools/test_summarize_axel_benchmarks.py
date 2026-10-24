"""Small pure-Python contracts: statistics, missing anchors, and group isolation."""
import copy
import csv
import io
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout

import summarize_axel_benchmarks as bench


CONTRACT = json.loads(bench.CONTRACT_PATH.read_text(encoding="utf-8"))


def inputs():
    report = {"pid": 10, "begin_ticks_us": 2_000_000,
              "cpu_time_anchor": {"ticks_us": 2_000_100, "unix_us": 10_000_100},
              "entry_ms": 3000, "loader_ms": 2000, "origin_first_ready": {"at_ms": 9000, "contract": "three empty frames"},
              "sources": {"res://a.gd": "a" * 64}, "sources_after": {"res://a.gd": "a" * 64},
              "map_sha": "b" * 64, "map_sha_after": "b" * 64, "failures": [],
              "controls": {"white_material": True, "map_textures": False, "resource_bundles": False},
              "native_products_required": True, "frames": [{"phase": "return", "ms": 60}, {"phase": "return", "ms": 10}]}
    validation = {"accepted": True, "checks": {k: True for k in CONTRACT["cache_checks"]},
                  "diagnostic": False, "observed_capacity": {"job_limit": [6], "worker_limit": [6]},
                  "admission_byte_limits": [7705667456], "work": {"selected_actual": {"deferred.models": 23}},
                  "module_observation": {"we_hook_present": False}}
    launch = {"engine_sha": "c" * 64, "external_sources": {"runner.py": "d" * 64},
              "command": ["python", "--", "engine", "--script", "res://probe.gd", "--", "--mesh-only", "--cold-index", "--output=x.json"]}
    owned = {"engine_pid": 10, "engine_created": 8.0}
    return report, validation, launch, owned


def presentmon():
    return {"target_pid": 10, "capture_accepted": True, "pm_sha256": "e" * 64,
            "wrapper_sha256": "f" * 64, "command": ["presentmon.exe", "--process_id", "10",
            "--session_name", "session-one", "--timed", "500", "--qpc_time", "--output_file", "one.csv"]}


def run(name="one", values=None, pm=None):
    return bench.extract_run(name, *(values or inputs()), CONTRACT, pm)


class BenchmarkContracts(unittest.TestCase):
    def test_nearest_rank_p95_n10_is_max(self):
        self.assertEqual(bench.summarize(list(range(1, 11))), {"n": 10, "sufficient_n": True, "p50": 5.5, "p95": 10, "max": 10})

    def test_missing_not_zero_and_small_n_insufficient(self):
        self.assertEqual(bench.summarize([None, float("nan"), True, -1]), {"n": 0, "sufficient_n": False, "p50": None, "p95": None, "max": None})
        self.assertFalse(bench.summarize([7, 8])["sufficient_n"])

    def test_four_anchors_and_historical_boundary(self):
        r = run()
        self.assertEqual(r["anchors"]["pipeline_begin"]["unix_us"], 10_000_000)
        self.assertEqual(r["metrics_ms"]["pipeline_to_full_ready_ms"], 9000)
        self.assertEqual(r["metrics_ms"]["process_to_full_ready_ms"], 11000)
        self.assertEqual(r["metrics_ms"]["entry_to_full_ready_ms"], 6000)

    def test_missing_owned_never_uses_wrapper_start(self):
        report, validation, launch, owned = inputs()
        launch["start_unix"] = 8
        r = run(values=(report, validation, launch, {}))
        self.assertIsNone(r["anchors"]["process_spawn"]["unix_us"])
        self.assertIsNone(r["metrics_ms"]["process_to_full_ready_ms"])
        self.assertEqual(r["metrics_ms"]["pipeline_to_full_ready_ms"], 9000)

    def test_wrong_pid_and_missing_clock_are_not_startup(self):
        values = inputs(); values[3]["engine_pid"] = 99
        self.assertIsNone(run(values=values)["metrics_ms"]["process_to_pipeline_ms"])
        values = inputs(); values[0].pop("cpu_time_anchor")
        self.assertIsNone(run(values=values)["metrics_ms"]["process_to_full_ready_ms"])

    def test_missing_readiness_is_invalid_not_zero(self):
        values = inputs(); values[0].pop("origin_first_ready")
        r = run(values=values)
        self.assertFalse(r["valid"])
        self.assertIsNone(r["metrics_ms"]["pipeline_to_full_ready_ms"])

    def test_run_name_and_output_do_not_split_equal_configs(self):
        values = inputs(); values[2]["command"][-1] = "--output=another.json"
        self.assertEqual(run()["group_id"], run("two", values)["group_id"])

    def test_dirty_working_tree_splits_even_with_same_git_revision(self):
        values = inputs(); values[0]["git_sha"] = "same"
        values[0]["sources"]["res://a.gd"] = "e" * 64
        values[0]["sources_after"] = copy.deepcopy(values[0]["sources"])
        self.assertNotEqual(run()["group_id"], run(values=values)["group_id"])

    def test_engine_observer_cache_and_hook_each_split(self):
        variants = []
        v = inputs(); v[2]["engine_sha"] = "e" * 64; variants.append(v)
        v = inputs(); v[1]["diagnostic"] = True; v[1]["native_schema"] = 185; variants.append(v)
        v = inputs(); v[2]["command"].append("--without-derived-geometry-cache"); variants.append(v)
        v = inputs(); v[1]["module_observation"]["we_hook_present"] = True; variants.append(v)
        for values in variants:
            self.assertNotEqual(run()["group_id"], run(values=values)["group_id"])

    def test_incomplete_identity_isolates_and_source_change_invalidates(self):
        values = inputs(); values[2].pop("engine_sha")
        self.assertNotEqual(run("one", values)["group_id"], run("two", values)["group_id"])
        values = inputs(); values[0]["sources_after"]["res://a.gd"] = "e" * 64
        self.assertFalse(run(values=values)["valid"])

    def test_failed_attempt_retained_but_not_in_statistics(self):
        a = run(); b = run("two"); b["valid"] = False
        group = bench.group_runs([a, b], CONTRACT)[0]
        self.assertEqual(group["attempts"], 2)
        self.assertEqual(group["valid_runs"], 1)
        self.assertFalse(group["sufficient_n"])
        self.assertEqual(group["metrics_ms"]["pipeline_to_full_ready_ms"]["n"], 1)

    def test_frames_do_not_claim_independent_run_n(self):
        frames = run()["frames"]["return"]
        self.assertEqual(frames["frame_count"], 2)
        self.assertEqual(frames["over_50ms"], 1)
        self.assertNotIn("sufficient_n", frames)

    def test_presentmon_sidecar_forces_diagnostic_separate_from_native_only(self):
        values = inputs(); values[1]["native_schema"] = 185
        a, b = run(values=values), run(values=values, pm=presentmon())
        self.assertNotEqual(a["group_id"], b["group_id"])
        self.assertTrue(b["configuration"]["observers"]["diagnostic"])
        self.assertTrue(b["valid"])
        self.assertFalse(b["presentmon_capture"]["base_diagnostic"])

    def test_presentmon_tool_wrapper_and_capture_options_each_split(self):
        a = run(pm=presentmon())
        for key in ("pm_sha256", "wrapper_sha256"):
            pm = presentmon(); pm[key] = "a" * 64
            self.assertNotEqual(a["group_id"], run(pm=pm)["group_id"])
        pm = presentmon(); pm["command"].append("--no_track_input")
        self.assertNotEqual(a["group_id"], run(pm=pm)["group_id"])

    def test_presentmon_pid_session_output_do_not_split_configuration(self):
        pm = presentmon(); values = inputs()
        values[0]["pid"] = 20; values[3]["engine_pid"] = 20
        pm["target_pid"] = 20
        pm["command"][0] = "different/path/presentmon.exe"
        pm["command"][2] = "20"; pm["command"][4] = "session-two"; pm["command"][-1] = "two.csv"
        self.assertEqual(run(pm=presentmon())["group_id"], run("two", values, pm)["group_id"])

    def test_presentmon_missing_identity_remains_unknown_and_isolated(self):
        pm = presentmon(); pm.pop("wrapper_sha256")
        a, b = run("one", pm=pm), run("two", pm=pm)
        observer = a["configuration"]["observers"]["presentmon"]
        self.assertTrue(observer["enabled"])
        self.assertIsNone(observer["wrapper_sha256"])
        self.assertEqual(observer["exe_sha256"], "e" * 64)
        self.assertIn("observers.presentmon.wrapper_sha256", a["configuration_missing"])
        self.assertNotEqual(a["group_id"], b["group_id"])
        self.assertTrue(run(pm={})["configuration"]["observers"]["presentmon"]["enabled"])
        pm["pm_sha256"] = "invalid"
        self.assertIsNone(run(pm=pm)["configuration"]["observers"]["presentmon"]["exe_sha256"])

    def test_presentmon_wrong_target_or_failed_capture_is_invalid(self):
        pm = presentmon(); pm["target_pid"] = 99
        self.assertIn("presentmon_target_pid_missing_or_mismatched", run(pm=pm)["invalid_reasons"])
        pm = presentmon(); pm["capture_accepted"] = False
        self.assertIn("presentmon_capture_not_accepted", run(pm=pm)["invalid_reasons"])

    def test_cli_loads_presentmon_companion_and_preserves_its_sha(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); values = inputs(); report = directory / "sample.json"
            sidecar = directory / "sample.presentmon_validation.json"
            for path, value in [(report, values[0]), (directory / "sample.validation.json", values[1]),
                                (directory / "sample.launch.json", values[2]), (sidecar, presentmon())]:
                path.write_text(json.dumps(value), encoding="utf-8")
            prefix = directory / "result"
            with redirect_stdout(io.StringIO()): bench.main(["--output-prefix", str(prefix), str(report)])
            data = json.loads(prefix.with_suffix(".json").read_text(encoding="utf-8"))
            self.assertEqual(data["runs"][0]["configuration"]["observers"]["presentmon"]["wrapper_sha256"], "f" * 64)
            self.assertEqual(data["inputs"][str(sidecar)]["sha256"], bench.hashlib.sha256(sidecar.read_bytes()).hexdigest())

    def test_export_null_csv_and_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory); values = inputs(); report = directory / "sample.json"
            for path, value in [(report, values[0]), (directory / "sample.validation.json", values[1]), (directory / "sample.launch.json", values[2])]:
                path.write_text(json.dumps(value), encoding="utf-8")
            prefix = directory / "result"
            with redirect_stdout(io.StringIO()): bench.main(["--output-prefix", str(prefix), str(report)])
            data = json.loads(prefix.with_suffix(".json").read_text(encoding="utf-8"))
            self.assertIsNone(data["runs"][0]["metrics_ms"]["process_to_full_ready_ms"])
            with prefix.with_suffix(".csv").open(newline="", encoding="utf-8") as stream:
                row = next(csv.DictReader(stream))
            self.assertEqual(row["process_to_full_ready_ms"], "")
            self.assertEqual(row["initial.deferred.models"], "23")
            with self.assertRaises(FileExistsError): bench.main(["--output-prefix", str(prefix), str(report)])

    def test_copied_input_cannot_inflate_n(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            for name in ("one", "two"):
                (directory / (name + ".json")).write_text(json.dumps(inputs()[0]))
            with self.assertRaisesRegex(ValueError, "inflate N"):
                bench.main(["--output-prefix", str(directory / "result"), str(directory / "one.json"), str(directory / "two.json")])


if __name__ == "__main__":
    unittest.main()
