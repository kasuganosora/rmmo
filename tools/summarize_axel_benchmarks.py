"""Export existing Axel reports under benchmark v2. No engine launch or cache edits.

Usage: python tools/summarize_axel_benchmarks.py --output-prefix OUT/benchmark_v2
       OUT/wait180_A1.json OUT/wait180_B1.json ...
Writes .json, .csv (runs/work), and .frames.csv; refuses existing outputs.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

CONTRACT_PATH = Path(__file__).with_name("axel_benchmark_contract_v2.json")
METRICS = ("pipeline_to_loader_ms", "pipeline_to_entry_ms", "pipeline_to_full_ready_ms",
           "entry_to_full_ready_ms", "process_to_pipeline_ms", "process_to_entry_ms",
           "process_to_full_ready_ms")
SWITCHES = ("append_dependency_delta", "completed_owner_drain", "entry_defer_upload",
            "independent_instance_preparation", "native_prefab_direct_specs", "ordered_retirement_tail",
            "ready_collision_bypass", "resumable_bin_ledger", "native_products_required")


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False).encode("utf-8")).hexdigest()


def number(value):
    return value if type(value) in (int, float) and math.isfinite(value) and value >= 0 else None


def summarize(values, minimum=10):
    values = sorted(v for v in values if number(v) is not None)
    return {"n": len(values), "sufficient_n": len(values) >= minimum,
            "p50": statistics.median(values) if values else None,
            "p95": values[math.ceil(.95 * len(values)) - 1] if values else None,
            "max": max(values) if values else None}


def source_manifest(value):
    if not isinstance(value, dict) or not value:
        return None
    if not all(isinstance(k, str) and isinstance(v, str) and len(v) == 64
               and all(c in "0123456789abcdefABCDEF" for c in v) for k, v in value.items()):
        return None
    return {k: v.lower() for k, v in value.items()}


def anchors_and_metrics(report, owned):
    begin = number(report.get("begin_ticks_us"))
    entry = number(report.get("entry_ms"))
    full = number(report.get("origin_first_ready", {}).get("at_ms"))
    bridge = report.get("cpu_time_anchor", {})
    ticks, unix = number(bridge.get("ticks_us")), number(bridge.get("unix_us"))
    pipeline_unix = unix + begin - ticks if None not in (begin, ticks, unix) else None
    created = number(owned.get("engine_created"))
    spawn_unix = round(created * 1_000_000) if created is not None and report.get("pid") is not None and owned.get("engine_pid") == report["pid"] else None
    startup = (pipeline_unix - spawn_unix) / 1000 if pipeline_unix is not None and spawn_unix is not None and pipeline_unix >= spawn_unix else None
    def point(offset):
        return {"ticks_us": begin + offset * 1000 if begin is not None and offset is not None else None,
                "unix_us": pipeline_unix + offset * 1000 if pipeline_unix is not None and offset is not None else None}
    anchors = {"process_spawn": {"unix_us": spawn_unix, "source": "owned.engine_created with matching PID" if spawn_unix is not None else None},
               "pipeline_begin": {"ticks_us": begin, "unix_us": pipeline_unix},
               "entry": point(entry), "full_ready": point(full)}
    metrics = dict(zip(METRICS, [number(report.get("loader_ms")), entry, full,
        full - entry if full is not None and entry is not None and full >= entry else None,
        startup, startup + entry if startup is not None and entry is not None else None,
        startup + full if startup is not None and full is not None else None]))
    return anchors, metrics


def game_arguments(command):
    if not isinstance(command, list) or not all(isinstance(x, str) for x in command):
        return None
    separators = [i for i, x in enumerate(command) if x == "--"]
    if not separators:
        return None
    return ["--frame-heartbeat-port=<ephemeral>" if x.startswith("--frame-heartbeat-port=") else x
            for x in command[separators[-1] + 1:] if not x.startswith("--output=")]


def presentmon_observer(sidecar):
    if sidecar is None:
        return {"enabled": False}
    if not isinstance(sidecar, dict):
        raise ValueError("PresentMon sidecar must be an object")
    def identity(key):
        valid = source_manifest({key: sidecar.get(key)})
        return valid[key] if valid else None
    command = sidecar.get("command")
    arguments = None
    if isinstance(command, list) and command and all(isinstance(x, str) for x in command):
        arguments = []
        ephemeral = {"--process_id", "--session_name", "--output_file"}
        i = 1  # Executable bytes are identified by SHA, not its machine-specific path.
        while i < len(command):
            item = command[i]
            if item in ephemeral:
                if i + 1 == len(command):
                    arguments = None
                    break
                arguments.append(item + "=<run-specific>")
                i += 2
                continue
            arguments.append(item.split("=", 1)[0] + "=<run-specific>"
                             if item.split("=", 1)[0] in ephemeral else item)
            i += 1
    return {"enabled": True, "exe_sha256": identity("pm_sha256"),
            "wrapper_sha256": identity("wrapper_sha256"), "arguments": arguments}


def extract_run(name, report, validation, launch, owned, contract, presentmon=None):
    checks = validation.get("checks", {})
    command = launch.get("command", [])
    args = game_arguments(command)
    sources = source_manifest(report.get("sources"))
    after = source_manifest(report.get("sources_after"))
    auxiliary = source_manifest(launch.get("external_sources", launch.get("sources")))
    engine_sha = launch.get("engine_sha", launch.get("engine_sha256"))
    diagnostic = validation.get("diagnostic", launch.get("diagnostic"))
    pm_observer = presentmon_observer(presentmon)
    if pm_observer["enabled"]:
        diagnostic = True
    module = validation.get("module_observation") or {}
    cache = {"os": "retained_uncontrolled", "strict_os_cold": False,
             "native_required": report.get("native_products_required"),
             "native_product_manifest_sha256": None, "driver_shader_cache": "unmeasured",
             "observed_checks": {k: checks.get(k) for k in contract["cache_checks"]},
             "disabled_flags": [x for x in (args or []) if "cache" in x or x == "--cold-index"],
             "resource_bundles": report.get("controls", {}).get("resource_bundles")}
    probe = command[command.index("--script") + 1] if "--script" in command and command.index("--script") + 1 < len(command) else None
    observers = {"diagnostic": diagnostic, "presentmon": pm_observer, "native_schema": validation.get("native_schema"),
                 "native_threshold_us": launch.get("native_threshold_us"), "trace_off": launch.get("trace_off"),
                 "official_profiler": "--remote-debug" in command or (probe is not None and "official" in probe),
                 "heartbeat": bool(report.get("frame_heartbeat")) or any(x.startswith("--frame-heartbeat-port=") for x in (args or [])),
                 "frame_split": bool(report.get("frame_split")) or "--frame-split-probe" in (args or []),
                 "method_monitor": bool(report.get("monitor")) or "--monitor" in (args or []),
                 "quiet_cpu_validated": checks.get("quiet_cpu_sampler_valid"),
                 "one_module_observation": bool(module), "weobs_present": module.get("we_hook_present"),
                 "graphics_environment": launch.get("graphics_environment")}
    config = {"engine_sha256": engine_sha, "map_sha256": report.get("map_sha"),
              "working_tree_sources_sha256": fingerprint(sources) if sources else None,
              "auxiliary_sources_sha256": fingerprint(auxiliary) if auxiliary else None,
              "probe": probe, "game_arguments": args, "controls": report.get("controls"),
              "switches": {k: report.get(k) for k in SWITCHES}, "cache": cache, "observers": observers,
              "capacity": validation.get("observed_capacity"), "admission_bytes": validation.get("admission_byte_limits"),
              "viewport": report.get("viewport_size"), "spawn": report.get("requested_spawn"),
              "loading_frame_policy": report.get("loading_frame_policy"), "runtime_frame_policy": report.get("runtime_frame_policy"),
              "readiness_contract": report.get("origin_first_ready", {}).get("contract")}
    missing = [k for k in ("engine_sha256", "map_sha256", "working_tree_sources_sha256", "auxiliary_sources_sha256", "probe", "game_arguments", "controls", "capacity", "admission_bytes", "readiness_contract") if config[k] is None]
    if diagnostic is None: missing.append("observers.diagnostic")
    if pm_observer["enabled"]:
        missing.extend("observers.presentmon." + k for k in ("exe_sha256", "wrapper_sha256", "arguments") if pm_observer[k] is None)
    if any(x is None for x in cache["observed_checks"].values()): missing.append("cache.observed_checks")
    if missing: config["incomplete_identity_run"] = name
    anchors, metrics = anchors_and_metrics(report, owned)
    work = validation.get("work", {})
    selected = work.get("selected_actual", {})
    final = {f"{kind}.{field}": number(work.get("final", {}).get(kind, {}).get(field))
             for kind, fields in contract["final_work_fields"].items() for field in fields}
    invalid = [k for k, ok in checks.items() if ok is not True]
    if validation.get("accepted") is not True: invalid.append("original_validation_not_accepted")
    if not sources or sources != after: invalid.append("working_tree_sources_missing_or_changed")
    if report.get("map_sha") is None or report.get("map_sha") != report.get("map_sha_after"): invalid.append("map_identity_missing_or_changed")
    if report.get("failures") != []: invalid.append("route_failures_or_missing_failure_list")
    if metrics["pipeline_to_full_ready_ms"] is None: invalid.append("full_ready_missing")
    if pm_observer["enabled"]:
        if presentmon.get("target_pid") is None or presentmon.get("target_pid") != report.get("pid"):
            invalid.append("presentmon_target_pid_missing_or_mismatched")
        if presentmon.get("capture_accepted") is not True:
            invalid.append("presentmon_capture_not_accepted")
    phase_values = {}
    for frame in report.get("frames", []):
        if isinstance(frame.get("phase"), str) and number(frame.get("ms")) is not None:
            phase_values.setdefault(frame["phase"], []).append(frame["ms"])
    frames = {}
    for phase, values in phase_values.items():
        frame_stats = summarize(values)
        frame_stats.pop("sufficient_n")  # Frame count is not independent benchmark-run N.
        frame_stats["frame_count"] = frame_stats.pop("n")
        frames[phase] = {**frame_stats, **{f"over_{limit}ms": sum(v > limit for v in values) for limit in (33, 50, 100, 200)}}
    return {"name": name, "group_id": fingerprint(config), "configuration": config,
            "configuration_missing": missing, "valid": not invalid, "invalid_reasons": invalid,
            "original_accepted": validation.get("accepted"), "original_failed_checks": validation.get("failed_checks"),
            "presentmon_capture": None if presentmon is None else {
                "target_pid": presentmon.get("target_pid"), "capture_accepted": presentmon.get("capture_accepted"),
                "base_diagnostic": validation.get("diagnostic", launch.get("diagnostic"))},
            "legacy_work_mismatches": work.get("mismatches"), "validation_checks": checks,
            "source_manifest": sources, "auxiliary_source_manifest": auxiliary,
            "anchors": anchors, "metrics_ms": metrics, "process_clock_mapping": "single Unix/ticks anchor estimate; error unmeasured",
            "initial_work": selected, "final_work": final, "frames": frames}


def group_runs(runs, contract):
    grouped = {}
    for run in runs:
        grouped.setdefault(run["group_id"], []).append(run)
    output = []
    for key, members in grouped.items():
        valid = [r for r in members if r["valid"]]
        minimum = contract["statistics"]["minimum_valid_runs_per_configuration"]
        output.append({"group_id": key, "configuration": members[0]["configuration"],
            "runs": [r["name"] for r in members], "attempts": len(members), "valid_runs": len(valid),
            "sufficient_n": len(valid) >= minimum, "diagnostic": members[0]["configuration"]["observers"]["diagnostic"],
            "target_conclusion": "not evaluated; report historical and process boundaries separately",
            "metrics_ms": {m: summarize([r["metrics_ms"][m] for r in valid], minimum) for m in METRICS}})
    return output


def read_json(path, inputs, required=False):
    if not path.exists():
        if required: raise FileNotFoundError(path)
        inputs[str(path)] = None
        return {}
    data = path.read_bytes()
    inputs[str(path)] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    return json.loads(data.decode("utf-8-sig"))


def write_csv(path, rows):
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("x", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-prefix", type=Path, required=True)
    parser.add_argument("reports", nargs="+", type=Path)
    args = parser.parse_args(argv)
    reports = [p.resolve() for p in args.reports]
    if len(set(reports)) != len(reports): parser.error("Duplicate report inputs would inflate N")
    outputs = [Path(str(args.output_prefix) + suffix) for suffix in (".json", ".csv", ".frames.csv")]
    for path in outputs:
        if path.exists(): raise FileExistsError("Refuse overwriting " + str(path))
        if not path.parent.is_dir(): raise FileNotFoundError(path.parent)
    inputs = {}
    contract = read_json(CONTRACT_PATH, inputs, True)
    runs, seen_report_hashes = [], set()
    for path in reports:
        report = read_json(path, inputs, True)
        report_sha = inputs[str(path)]["sha256"]
        if report_sha in seen_report_hashes:
            raise ValueError("Copied report bytes would inflate N: " + str(path))
        seen_report_hashes.add(report_sha)
        companion = lambda suffix: read_json(path.with_name(path.stem + suffix), inputs)
        pm_path = path.with_name(path.stem + ".presentmon_validation.json")
        pm_sidecar = read_json(pm_path, inputs)
        if inputs[str(pm_path)] is None:
            pm_sidecar = None  # A present-but-empty sidecar is an unknown observer, never absent.
        runs.append(extract_run(str(path), report, companion(".validation.json"), companion(".launch.json"), companion(".owned.json"), contract, pm_sidecar))
    artifact = {"contract": contract, "contract_sha256": inputs[str(CONTRACT_PATH)]["sha256"],
                "exporter_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "inputs": inputs, "groups": group_runs(runs, contract), "runs": runs,
                "limitations": ["Historical evidence only; no new GPU runs.", "OS/driver cache and complete native-product byte inventories are not measured.",
                                "Source byte manifests include dirty working-tree changes; Git revision alone is not used.",
                                "Missing fields stay null (empty CSV cell); groups below N=10 are insufficient."]}
    with outputs[0].open("x", encoding="utf-8") as stream:
        json.dump(artifact, stream, ensure_ascii=False, indent=2, allow_nan=False)
    csv_rows, frame_rows = [], []
    for run in runs:
        c = run["configuration"]
        row = {"run": run["name"], "group_id": run["group_id"], "valid": run["valid"],
               "diagnostic": c["observers"]["diagnostic"], "engine_sha256": c["engine_sha256"],
               "map_sha256": c["map_sha256"], "working_tree_sources_sha256": c["working_tree_sources_sha256"],
               "strict_os_cold": False, "cache_configuration_sha256": fingerprint(c["cache"]),
               "observer_configuration_sha256": fingerprint(c["observers"]),
               "invalid_reasons": json.dumps(run["invalid_reasons"]), **run["metrics_ms"]}
        for anchor, value in run["anchors"].items(): row[anchor + "_unix_us"] = value.get("unix_us")
        row.update({"initial." + k: v for k, v in run["initial_work"].items()})
        row.update({"final." + k: v for k, v in run["final_work"].items()})
        csv_rows.append(row)
        for phase, values in run["frames"].items():
            frame_rows.append({"run": run["name"], "group_id": run["group_id"], "phase": phase, **values})
    write_csv(outputs[1], csv_rows)
    write_csv(outputs[2], frame_rows)
    print(json.dumps({"outputs": [str(p) for p in outputs], "runs": len(runs),
                      "groups": [{"id": g["group_id"][:12], "n": g["valid_runs"], "diagnostic": g["diagnostic"], "sufficient_n": g["sufficient_n"]} for g in artifact["groups"]]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
