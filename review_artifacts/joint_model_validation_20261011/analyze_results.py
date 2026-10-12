"""Read explicit joint-validation result globs; never launch or warm the game.

Example: python analyze_results.py --output results_summary.json
Default inputs are game_*.json/editor_*.json in the matching runtime directory.
Hardware siblings may be NAME.hardware.json or NAME_hardware.json; ambiguous
siblings are rejected. Each run remains a separate sample, with no inferred win.
"""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re


DEFAULT_ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
FLAGS = ("collision_geometry", "model_texture_sharing", "picking_lod",
         "native_model_footprints", "preparation_lanes", "model_residency",
         "prefab_warm_workers", "bridge_texture_preparation",
         "deferred_native_preparation", "deferred_native_budget",
         "initial_model_workers_override", "background_navigation", "background_wind")
DEFERRED = ("models", "instances", "compiled_hits", "native_retries", "worker_us",
            "capture_us", "captured_meshes", "capture_bytes", "face_us", "face_bytes",
            "native_surface_worker_us", "max_publish_us", "peak_jobs",
            "peak_reserved_bytes", "reserved_bytes", "collision_product_hits",
            "collision_product_misses", "bridge_texture_jobs", "worker_capacity")
UNITS = ("asset_wait", "asset_parse_worker", "asset_prepare_main", "asset_prepare_release",
         "picking_capture", "picking_faces_prepare", "picking_faces_wait", "picking_shape",
         "picking_publish", "add_bodies", "terrain_prepare_wait", "prefab_texture_wait")


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def get(value, *keys):
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def select(value, keys):
    return {key: get(value, key) for key in keys}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def hardware_span(hardware, start, end):
    result = {"start_epoch_s": start, "end_epoch_s": end, "wall_s": None,
              "sampling_coverage_s": None, "cpu_coverage_s": None,
              "cpu_logical_equivalents_mean": None, "cpu_percent_total_logical_mean": None,
              "main_thread_cpu_equivalents_mean": None, "rss_peak_bytes": None,
              "private_peak_bytes": None, "gpu_engine_peak_percent": None,
              "gpu_engine_mean_percent": None, "gpu_valid_coverage_s": None,
              "errors": get(hardware, "errors"), "gpu_errors": get(hardware, "gpu_errors"),
              "limitations": []}
    if not number(start) or not number(end) or end <= start:
        result["limitations"].append("Missing/invalid exact load epoch boundaries; hardware not attributed.")
        return result
    result["wall_s"] = end - start
    samples = get(hardware, "samples")
    if not isinstance(samples, list) or len(samples) < 2:
        result["limitations"].append("No usable owned-process hardware intervals.")
        return result
    origin = next((s for s in samples if number(get(s, "epoch_s")) and number(get(s, "monotonic_s"))), None)
    if origin is None:
        result["limitations"].append("Hardware lacks monotonic-to-epoch anchor.")
        return result
    coverage = cpu_coverage = cpu_seconds = main_seconds = main_coverage = 0.0
    gpu_sum, gpu_coverage, gpu_peak = defaultdict(float), defaultdict(float), {}
    peaks = {"rss_bytes": None, "private_bytes": None}
    for previous, sample in zip(samples, samples[1:]):
        ptime, stime = get(previous, "monotonic_s"), get(sample, "monotonic_s")
        if not number(ptime) or not number(stime) or stime <= ptime:
            continue
        stop = origin["epoch_s"] + stime - origin["monotonic_s"]
        interval = stime - ptime
        overlap = max(0.0, min(end, stop) - max(start, stop - interval))
        if not overlap:
            continue
        coverage += overlap
        p_cpu, s_cpu = get(previous, "cpu_s"), get(sample, "cpu_s")
        if number(p_cpu) and number(s_cpu) and s_cpu >= p_cpu:
            cpu_seconds += (s_cpu - p_cpu) / interval * overlap
            cpu_coverage += overlap
        for thread in get(sample, "threads") or []:
            if get(thread, "id") == get(hardware, "main_thread_id") and number(get(thread, "cpu_equivalents")):
                main_seconds += thread["cpu_equivalents"] * overlap
                main_coverage += overlap
                break
        for key in peaks:
            # Include both endpoints of overlapping intervals; sampled, not an
            # exact instantaneous peak, and may straddle a load boundary by .5s.
            for row in (previous, sample):
                value = get(row, key)
                if number(value):
                    peaks[key] = value if peaks[key] is None else max(peaks[key], value)
        by_type = {}
        for instance, value in (get(sample, "gpu", "engines", "items") or {}).items():
            match = re.search(r"engtype_(.+)$", instance)
            if match and number(value):
                kind = match[1]
                by_type[kind] = max(by_type.get(kind, 0.0), value)
        for kind, value in by_type.items():
            gpu_peak[kind] = max(gpu_peak.get(kind, 0.0), value)
            gpu_sum[kind] += value * overlap
            gpu_coverage[kind] += overlap
    cpus = get(hardware, "logical_cpus")
    mean = cpu_seconds / cpu_coverage if cpu_coverage else None
    result.update(sampling_coverage_s=coverage, cpu_coverage_s=cpu_coverage,
                  cpu_logical_equivalents_mean=mean,
                  cpu_percent_total_logical_mean=mean / cpus * 100 if mean is not None and number(cpus) and cpus > 0 else None,
                  main_thread_cpu_equivalents_mean=main_seconds / main_coverage if main_coverage else None,
                  rss_peak_bytes=peaks["rss_bytes"], private_peak_bytes=peaks["private_bytes"],
                  gpu_engine_peak_percent=gpu_peak or None,
                  gpu_engine_mean_percent={k: gpu_sum[k] / gpu_coverage[k] for k in gpu_sum} or None,
                  gpu_valid_coverage_s=dict(gpu_coverage) or None)
    result["limitations"].append("CPU is interval-weighted process CPU, not worker wall time; boundary intervals are prorated. RSS/private are sampled endpoint maxima. GPU types are separate; each type uses maximum single engine, never their sum. Short-lived thread CPU may be absent; no wait stacks or fence attribution.")
    if coverage < result["wall_s"] * .95:
        result["limitations"].append("Less than 95% of the requested load span has hardware coverage.")
    return result


def summarize_report(report, filename):
    kind = "editor" if isinstance(get(report, "load_result"), dict) or filename.startswith("editor_") else "game"
    result = {"file": filename, "kind": kind, "failures": get(report, "failures"),
              "timeout": get(report, "timeout"), "flags": select(report, FLAGS),
              "map": get(report, "map") if kind == "game" else get(report, "checkpoint"),
              "map_sha": get(report, "map_sha") if kind == "game" else get(report, "expected_sha256"),
              "formal_sha": get(report, "formal_sha") if kind == "game" else get(report, "formal_sha256"),
              "limitations": []}
    if kind == "game":
        result.update(entry_ms=get(report, "entry_ms"),
                      window_start=get(report, "entry_epoch_s"), window_end=get(report, "entry_end_epoch_s"),
                      requested_spawn=get(report, "requested_spawn"), requested_chunk=get(report, "requested_chunk"),
                      screenshot_avatar_hidden=get(report, "screenshot_avatar_hidden"),
                      entry_core_ready_ms=get(report, "entry_core_ready_ms"),
                      entry_deferred=select(get(report, "entry_deferred_profile"), DEFERRED),
                      final_deferred=select(get(report, "final_deferred_profile"), DEFERRED),
                      remaining_deferred=get(report, "remaining_deferred"),
                      frames=select(get(report, "monitor"), ("frame_percentiles_ms", "phase_frame_percentiles_ms")),
                      physics={"collision_bodies": get(report, "collision_bodies"),
                               "entry_readiness_shadow": get(report, "entry_readiness_shadow"),
                               "probe": select(get(report, "physics_probe"), ("ok", "error")),
                               "entry_collision_query": get(report, "entry_collision_query"),
                               "final_collision_query": get(report, "final_collision_query"),
                               "final_collision_profile": get(report, "final_collision_profile"),
                               "player_physics_start": get(report, "playable_player_physics_start"),
                               "player_physics_end": get(report, "playable_player_physics_end")},
                      cache={"admission": get(report, "map_profile", "asset_admission"),
                             **select(get(report, "map_profile"), ("reference_index_hit", "reference_index_reason",
                                      "reference_index_rebuilt_before_models", "mesh_cache_candidate", "mesh_cache_scope",
                                      "terrain_context_cache_hit", "metadata_cache_hit", "asset_fallback_count"))},
                      parse={"wall_us": get(report, "map_profile", "asset_parse_wall_us"),
                             "worker_elapsed_sum_us": get(report, "map_profile", "asset_parse_us"),
                             "assets": get(report, "map_profile", "asset_parses")})
    else:
        timings = get(report, "load_result", "timings")
        result.update(load_ms=get(report, "load_ms"), load_ok=get(report, "load_result", "ok"),
                      window_start=get(report, "load_start_epoch_s"), window_end=get(report, "load_end_epoch_s"),
                      validate_ms=get(timings, "validate_ms"), prefab_warm=get(timings, "validation", "prefab_warm"),
                      units={key: get(timings, "build", "units", key) for key in UNITS},
                      cache=get(timings, "asset_lookahead"), preparation=get(timings, "preparation"),
                      build=select(get(timings, "build"), ("elapsed_ms", "batch_wait_ms", "max_slice_ms")),
                      full_rebuilds=get(report, "full_rebuilds"), baseline_full_rebuilds=get(report, "baseline_full_rebuilds"),
                      final_record_count=get(report, "final_record_count"), final_house_count=get(report, "final_house_count"))
        result["limitations"].append("asset_parse_worker is summed task wall time, not measured CPU and not additive to asset_wait/load_ms. Picking shape/publish and parent add_bodies overlap. HTTP operation timings occur after this load window.")
    result["limitations"].append("One row is one observed run; missing fields are null. Nested/inclusive timings are not summed. Cache candidate/file existence alone does not prove use of a cooked product.")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--glob", action="append", dest="patterns", help="Repeatable, nonrecursive result filename glob")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("results_summary.json"))
    args = parser.parse_args()
    folder = args.input_dir.resolve()
    patterns = args.patterns or ["game_*.json", "editor_*.json"]
    if any("/" in p or "\\" in p or ".." in p for p in patterns):
        parser.error("Use filename-only globs inside --input-dir")
    paths = sorted({p for pattern in patterns for p in folder.glob(pattern)
                    if p.is_file() and p.resolve().parent == folder
                    and not p.name.endswith((".hardware.json", "_hardware.json")) and p.resolve() != args.output.resolve()})
    output = {"input_dir": str(folder), "globs": patterns, "runs": [], "read_errors": [],
              "sample_count": 0, "comparison": None,
              "limitations": ["No automatic before/after causal claim or sample aggregation. Compare identical code/renderer/spawn/flags and prepared cache state separately from art changes. Warmup/rebuild runs must be excluded explicitly using result globs."]}
    for path in paths:
        try:
            report = read_json(path)
            if not isinstance(report, dict):
                raise ValueError("Result must be a JSON object")
            row = summarize_report(report, path.name)
            siblings = [path.with_name(path.stem + suffix) for suffix in (".hardware.json", "_hardware.json")]
            present = [p for p in siblings if p.is_file() and p.resolve().parent == folder]
            hardware = None
            row["hardware_file"] = str(present[0]) if len(present) == 1 else None
            if len(present) == 1:
                try:
                    hardware = read_json(present[0])
                except (OSError, ValueError) as error:
                    row["limitations"].append("Hardware read failed: " + str(error))
            else:
                row["limitations"].append("Hardware sibling missing or ambiguous; no process utilization inferred.")
            row["hardware"] = hardware_span(hardware, row["window_start"], row["window_end"])
            log = path.with_suffix(".log")
            row["log"] = None
            if log.is_file() and log.resolve().parent == folder:
                lines = log.read_text(encoding="utf-8-sig", errors="replace").splitlines()
                row["log"] = {"file": str(log), "passes": sum(x.startswith(("PASS ", "PASS:")) for x in lines),
                              "fail_lines": [x for x in lines if x.startswith(("FAIL ", "FAIL:"))],
                              "errors_warnings": [x for x in lines if re.match(r"^\s*(SCRIPT ERROR:|ERROR:|WARNING:)", x)]}
            output["runs"].append(row)
        except (OSError, ValueError, TypeError, KeyError) as error:
            output["read_errors"].append({"file": str(path), "error": str(error)})
    output["sample_count"] = len(output["runs"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
    print(json.dumps({"output": str(args.output), "sample_count": output["sample_count"],
                      "read_errors": output["read_errors"]}, ensure_ascii=False))
    return 1 if output["read_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
