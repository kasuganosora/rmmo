"""Read only recorded JSON/logs; write this directory's summary.json.

No Godot invocation, resource reads, hashing, external writes or subprocesses.
Completed results retain memory: parked jobs are not active worker threads.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import re
from statistics import mean

REPORTS = Path("D:/code/rmmo_runtime/review_artifacts/deferred_native_20261010")
RUNS = [f"{kind}_{mode}_{sample}" for kind in ("warm", "rebuild")
        for mode, sample in (("old", "a"), ("new", "a"), ("new", "b"), ("old", "b"))]
LAST_MODEL = "ca8df54834f3a7b3f99e866ced32727a97ffc88bab02e026a184cf612df89d8a.glb"
SHA_LABELS = {
    "compiled.source_precheck", "compiled.source_sha", "deferred.source_sha",
    "deferred.final_source_sha", "deferred.reused_source_sha", "game.source_hash",
}
STAGE_LABELS = SHA_LABELS | {
    "compiled.payload_sha", "compiled.native_read", "compiled.read",
    "model.parse", "deferred.job", "deferred.prepare",
    "deferred.compiled_instantiate", "deferred.cpu_capture", "deferred.publication",
    "deferred.gltf_append", "deferred.gltf_generate", "resource.instance_copy",
}


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def event_path(event):
    return event.get("details", {}).get("path", "")


def intervals(events, lower=None, upper=None):
    rows = []
    for event in events:
        start, end = event.get("start_us"), event.get("end_us")
        if not number(start) or not number(end) or end < start:
            continue
        start = max(start, lower) if lower is not None else start
        end = min(end, upper) if upper is not None else end
        if end > start:
            rows.append((start, end))
    return rows


def union_us(rows):
    total = 0
    end = None
    for left, right in sorted(rows):
        if end is None or left > end:
            total += right - left
        elif right > end:
            total += right - end
        end = max(end, right) if end is not None else right
    return total


def timing(events, lower=None, upper=None):
    spans = intervals(events, lower, upper)
    return {
        "count": len(events),
        "unique_paths": len({event_path(e) for e in events if event_path(e)}),
        "worker_or_call_sum_us": sum(b-a for a, b in spans),
        "union_wall_us": union_us(spans),
        "first_start_us": min((a for a, _ in spans), default=None),
        "last_end_us": max((b for _, b in spans), default=None),
        "envelope_wall_us": (max(b for _, b in spans)-min(a for a, _ in spans)) if spans else 0,
        "max_call_us": max((b-a for a, b in spans), default=0),
    }


def active_time(events, lower, upper):
    """Count running task spans, not cores and not completed retained results."""
    points = defaultdict(int)
    for left, right in intervals(events, lower, upper):
        points[left] += 1
        points[right] -= 1
    histogram = defaultdict(float)
    previous, active, peak = lower, 0, 0
    for at, delta in sorted(points.items()):
        histogram[active] += at-previous
        active += delta
        peak = max(peak, active)
        previous = at
    histogram[active] += upper-previous
    return {
        "window_us": upper-lower,
        "peak_running_tasks": peak,
        "mean_running_tasks": sum(n*t for n, t in histogram.items())/(upper-lower) if upper > lower else None,
        "wall_us_by_running_tasks": dict(sorted(histogram.items())),
        "note": "Nested/overlapping task wall spans, not process CPU cores or parked admission entries.",
    }


def interpolate(samples, at, key):
    for sample in samples:
        if sample["epoch_s"] == at and number(sample.get(key)):
            return sample[key]
    for left, right in zip(samples, samples[1:]):
        if left["epoch_s"] <= at <= right["epoch_s"] and right["epoch_s"] > left["epoch_s"]:
            if not number(left.get(key)) or not number(right.get(key)):
                return None
            alpha = (at-left["epoch_s"])/(right["epoch_s"]-left["epoch_s"])
            return left[key] + alpha*(right[key]-left[key])
    return None


def hardware_window(hardware, start, end):
    samples = sorted((s for s in hardware.get("samples", []) if number(s.get("epoch_s"))), key=lambda s: s["epoch_s"])
    inside = [s for s in samples if start <= s["epoch_s"] <= end]
    result = {"start_epoch_s": start, "end_epoch_s": end, "wall_s": end-start,
              "sample_count_inside": len(inside), "enclosed": bool(samples and samples[0]["epoch_s"] <= start <= end <= samples[-1]["epoch_s"])}
    for key in ("cpu_s", "read_bytes", "write_bytes", "read_operations"):
        before, after = interpolate(samples, start, key), interpolate(samples, end, key)
        result[key+"_delta"] = after-before if before is not None and after is not None else None
    result["cpu_core_equivalents"] = result["cpu_s_delta"]/(end-start) if result["cpu_s_delta"] is not None and end > start else None
    for key in ("rss_bytes", "private_bytes", "thread_count", "sampler_ms"):
        result["peak_sampled_"+key] = max((s[key] for s in inside if number(s.get(key))), default=None)
    result["boundary_memory_estimates"] = {
        key: {"start": interpolate(samples, start, key), "end": interpolate(samples, end, key)}
        for key in ("rss_bytes", "private_bytes")
    }
    engines, gpu_memory = defaultdict(list), defaultdict(list)
    for sample in inside:
        gpu = sample.get("gpu", {})
        for name, value in gpu.get("engines", {}).get("items", {}).items():
            if number(value):
                engines[name].append(value)
        for category in ("dedicated", "shared"):
            for name, value in gpu.get(category, {}).get("items", {}).items():
                if number(value):
                    gpu_memory[category+":"+name].append(value)
    result["gpu_engine_sampled_peaks_percent"] = {key: max(values) for key, values in engines.items()}
    result["gpu_memory_sampled_peaks_bytes"] = {key: max(values) for key, values in gpu_memory.items()}
    result["note"] = "CPU is interpolated process CPU seconds / window wall seconds. RSS/private peaks use only actual samples inside the window. GPU engines are separate, never summed. Logical/cache reads are not disk throughput."
    return result


def contains(parent, event):
    return (parent.get("thread_id") == event.get("thread_id")
            and parent["start_us"] <= event["start_us"] <= event["end_us"] <= parent["end_us"]
            and (not event_path(event) or event_path(parent) == event_path(event)))


def trace_summary(data, entry_start_us, entry_end_us, core_us, safety_us):
    trace = data.get("monitor", {}).get("trace", {})
    all_events = trace.get("events", [])
    events = [e for e in all_events if number(e.get("start_us")) and number(e.get("end_us"))
              and e["start_us"] >= entry_start_us and e["end_us"] <= entry_end_us]
    initial_jobs = [e for e in events if e.get("label") == "model.parse"]
    deferred_jobs = [e for e in events if e.get("label") == "deferred.job"]

    def phase(event):
        for job in deferred_jobs:
            if contains(job, event):
                details = job.get("details", {})
                if details.get("native"):
                    return "deferred_native_reference"
                return "deferred_new_model" if details.get("need_model") else "deferred_reuse"
        if any(contains(job, event) for job in initial_jobs):
            return "initial_model"
        if event.get("label", "").startswith("deferred."):
            return "deferred_main_or_unscoped"
        return "other_or_unattributed"

    stages = defaultdict(lambda: defaultdict(list))
    for event in events:
        label = event.get("label", "")
        if label in STAGE_LABELS or label.startswith(("compiled.", "deferred.")):
            stages[phase(event)][label].append(event)
    stage_summary = {scope: {label: timing(values) for label, values in rows.items()} for scope, rows in stages.items()}
    sha = {scope: timing([event for label, rows in labels.items() if label in SHA_LABELS for event in rows])
           for scope, labels in stages.items()}
    models = [e for e in deferred_jobs if e.get("details", {}).get("need_model") and not e.get("details", {}).get("native")]
    dispatches = [e for e in events if e.get("label") == "deferred.dispatch"
                  and e.get("details", {}).get("need_model") and not e.get("details", {}).get("native")]
    per_path = []
    for path in sorted({event_path(e) for e in dispatches+models}):
        dispatch = [e for e in dispatches if event_path(e) == path]
        jobs = [e for e in models if event_path(e) == path]
        success = [e for e in jobs if e.get("details", {}).get("failed") is False]
        path_events = [e for e in events if event_path(e) == path and phase(e) == "deferred_new_model"]
        labels = defaultdict(list)
        for event in path_events:
            if event.get("label") in STAGE_LABELS or event.get("label", "").startswith("compiled."):
                labels[event["label"]].append(event)
        per_path.append({
            "path": path,
            "dispatches": [{"at_us": e["start_us"], "after_core_ms": (e["start_us"]-core_us)/1000,
                            **e.get("details", {})} for e in dispatch],
            "jobs": [{"start_us": e["start_us"], "end_us": e["end_us"],
                      "worker_wall_us": e["end_us"]-e["start_us"], "worker_finished_after_core_ms": (e["end_us"]-core_us)/1000,
                      "thread_id": e.get("thread_id"), **e.get("details", {})} for e in jobs],
            "first_dispatch_before_core": bool(dispatch and min(e["start_us"] for e in dispatch) < core_us),
            "successful_worker_finished_before_core": bool(success and max(e["end_us"] for e in success) <= core_us),
            "first_dispatch_after_core_ms": (min(e["start_us"] for e in dispatch)-core_us)/1000 if dispatch else None,
            "last_successful_worker_finished_after_core_ms": (max(e["end_us"] for e in success)-core_us)/1000 if success else None,
            "stages": {label: timing(values) for label, values in labels.items()},
        })
    last = [row for row in per_path if Path(row["path"]).name == LAST_MODEL]
    publications = [e for e in events if e.get("label") == "deferred.publication" and e["end_us"] <= safety_us]
    last_publication = max(publications, key=lambda e: e["end_us"], default=None)
    return {
        "dropped": trace.get("dropped"), "minimum_event_us": trace.get("minimum_event_us"),
        "event_count_entry_complete_spans": len(events),
        "events_crossing_entry_boundaries": sum(1 for e in all_events if number(e.get("start_us")) and number(e.get("end_us"))
                                               and e["start_us"] < entry_end_us < e["end_us"]),
        "stage_timings": stage_summary, "source_sha": sha,
        "native_read": {scope: timing(labels.get("compiled.native_read", [])) for scope, labels in stages.items()},
        "initial_model_count": len({event_path(e) for e in initial_jobs}),
        "deferred_model_count": len(per_path),
        "deferred_model_dispatches_before_core": sum(row["first_dispatch_before_core"] for row in per_path),
        "deferred_model_workers_finished_before_core": sum(row["successful_worker_finished_before_core"] for row in per_path),
        "deferred_dispatch_routes": dict(Counter(e.get("details", {}).get("stage", "legacy_unlabelled") for e in dispatches)),
        "deferred_models": per_path,
        "ca8_model": last[0] if len(last) == 1 else {"missing_or_duplicate": len(last)},
        "deferred_running_tasks_entry": active_time(deferred_jobs, entry_start_us, entry_end_us),
        "deferred_running_tasks_safety": active_time(deferred_jobs, core_us, safety_us),
        "deferred_model_running_tasks_safety": active_time(models, core_us, safety_us),
        "last_publication_before_safety": last_publication,
        "last_publication_to_safety_ms": (safety_us-last_publication["end_us"])/1000 if last_publication else None,
        "note": "Worker finished does not mean main-thread join/acceptance/publication. Per-model ready-at-core is unavailable without a join event; use entry_prefetch_ready_jobs at handoff as the actual joined count. Stage sums overlap and are not CPU time. Source-SHA excludes payload/rmres/map hashing. Span counts omit calls below the trace threshold and events crossing the entry end; deferred.source_sha also includes the preceding path/manifest checks.",
    }


def read_run(directory, name):
    path = directory/(name+".json")
    paths = {"report": path, "hardware": directory/(name+".hardware.json"), "log": directory/(name+".log")}
    missing = [kind for kind, candidate in paths.items() if not candidate.is_file()]
    if missing:
        return {"name": name, "status": "pending", "missing": missing}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        hardware = json.loads(paths["hardware"].read_text(encoding="utf-8"))
        log = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", paths["log"].read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError) as error:
        return {"name": name, "status": "pending_or_invalid", "reason": str(error)}
    if not data.get("screenshot") or "GAME_ENTRY_FINISHED failures=" not in log:
        return {"name": name, "status": "incomplete", "reason": "Screenshot/final completion log missing; do not measure a running report."}
    try:
        world, profile = data["world_profile"], data["map_profile"]
        core_us, safety_us = world["entry_core_resources_ready_us"], world["entry_safety_ready_us"]
        core_ms, entry_ms = data["entry_core_ready_ms"], data["entry_ms"]
        start_epoch = data["entry_epoch_s"]
        start_us = core_us-core_ms*1000
        end_us, end_epoch = start_us+entry_ms*1000, start_epoch+entry_ms/1000
        safety_ms = (safety_us-core_us)/1000
        if not start_us <= core_us <= safety_us <= end_us:
            raise ValueError("Entry/core/safety timestamps are not ordered")
    except (KeyError, TypeError, ValueError) as error:
        return {"name": name, "status": "invalid_schema", "reason": str(error)}
    deferred = data.get("entry_deferred_profile", {})
    trace = trace_summary(data, start_us, end_us, core_us, safety_us)
    windows = {"entry": (start_epoch, end_epoch), "core": (start_epoch, start_epoch+core_ms/1000),
               "safety": (start_epoch+core_ms/1000, start_epoch+(core_ms+safety_ms)/1000),
               "post_safety": (start_epoch+(core_ms+safety_ms)/1000, end_epoch)}
    hardware_windows = {key: hardware_window(hardware, *bounds) for key, bounds in windows.items()}
    errors = re.findall(r"^\s*(?:SCRIPT )?ERROR:.*$", log, re.M)
    warnings = re.findall(r"^\s*WARNING:.*$", log, re.M)
    failed_checks = re.findall(r"^\s*FAIL(?:\b|:).*$", log, re.M)
    author_check = [line.strip() for line in log.splitlines() if "temporary checkpoint and formal map unchanged" in line]
    return {
        "name": name, "status": "complete", "files": {key: str(value) for key, value in paths.items()},
        "entry_ms": entry_ms, "core_ms": core_ms, "safety_ms": safety_ms,
        "post_core_ms": entry_ms-core_ms, "post_safety_ms": entry_ms-core_ms-safety_ms,
        "clock": {"entry_start_ticks_us": start_us, "core_ticks_us": core_us, "safety_ticks_us": safety_us,
                  "entry_end_ticks_us": end_us, "reported_entry_end_epoch_s": data.get("entry_end_epoch_s"),
                  "derived_entry_end_epoch_s": end_epoch, "monitor_start_ticks_us": data.get("monitor", {}).get("start_ticks_us")},
        "flags": {key: data.get(key) for key in ("deferred_native_preparation", "deferred_native_budget", "deferred_ready_worker_yield", "prepared_collision_faces", "collision_face_prefetch", "cpu_river_overrides", "cpu_river_index", "reset_derived_cache", "reset_cache_scope")},
        "engine_build": data.get("engine_build"),
        "integrity": {"map": data.get("map"), "map_sha": data.get("map_sha"), "formal_sha": data.get("formal_sha"),
                      "authored_records": data.get("authored_record_count"), "final_check_log": author_check,
                      "failures": data.get("failures"), "errors": len(errors), "error_lines": errors,
                      "warnings": len(warnings), "warning_lines": warnings, "failed_check_lines": failed_checks},
        "functional": {key: data.get(key) for key in ("requested_spawn", "requested_chunk", "spawn", "final_player_position", "initial_pending", "remaining_deferred", "resident_record_count", "stream_specs", "collision_bodies", "demand_idle", "screenshot")},
        "initial": {
            "asset_parses": profile.get("asset_parses", []), "admission": profile.get("asset_admission", {}),
            "admission_stage_details": profile.get("asset_admission_details", {}),
            "map_stages": {key: profile.get(key) for key in ("initial_asset_paths", "reference_index_read_us", "reference_index_hit", "reference_selected_count", "parser_total_us", "asset_parse_wall_us", "asset_parse_us", "build_total_us", "mesh_cache_candidate", "cooked_meshes", "cooked_restore_us", "mesh_us", "spec_us", "source_hash_us", "source_scan_us")},
        },
        "deferred": {
            "entry_profile": deferred,
            "prefetch_dispatched_models": deferred.get("entry_prefetch_jobs"),
            "prefetch_joined_results_at_handoff": deferred.get("entry_prefetch_ready_jobs"),
            "prefetch_cumulative_joins": deferred.get("entry_prefetch_joined_jobs"),
            "prefetch_last_join_after_core_ms": (deferred["entry_prefetch_last_ready_us"]-core_us)/1000 if number(deferred.get("entry_prefetch_last_ready_us")) else None,
            "peak_held_jobs": deferred.get("admission", {}).get("peak_jobs", deferred.get("peak_jobs")),
            "peak_active_workers": deferred.get("admission", {}).get("peak_workers"),
            "active_workers_at_entry_snapshot": deferred.get("admission", {}).get("active_workers"),
            "peak_reserved_bytes": deferred.get("peak_reserved_bytes"),
            "note": "entry_profile is the ready-time snapshot, not deferred_profile captured after background walking. peak_jobs includes ready parked outputs; peak_workers counts occupied worker slots."
        },
        "trace": trace,
        "hardware": {"metadata": {key: hardware.get(key) for key in ("pid", "logical_cpus", "physical_cores", "system_ram_bytes", "main_thread_id", "errors", "gpu_errors", "note")}, "windows": hardware_windows},
        "cpu_cores": hardware_windows["entry"]["cpu_core_equivalents"],
        "peak_rss_bytes": hardware_windows["entry"]["peak_sampled_rss_bytes"],
        "peak_private_bytes": hardware_windows["entry"]["peak_sampled_private_bytes"],
    }


def get_path(value, path):
    for part in path.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(part)
    return value


MEAN_FIELDS = [
    "entry_ms", "core_ms", "safety_ms", "post_core_ms", "post_safety_ms", "cpu_cores",
    "peak_rss_bytes", "peak_private_bytes", "deferred.peak_reserved_bytes", "deferred.peak_held_jobs",
    "deferred.peak_active_workers", "deferred.prefetch_dispatched_models", "deferred.prefetch_joined_results_at_handoff",
    "trace.deferred_model_workers_finished_before_core", "trace.deferred_model_dispatches_before_core",
    "trace.last_publication_to_safety_ms", "hardware.windows.safety.cpu_core_equivalents",
    "trace.ca8_model.first_dispatch_after_core_ms", "trace.ca8_model.last_successful_worker_finished_after_core_ms",
    "trace.source_sha.initial_model.count", "trace.source_sha.initial_model.worker_or_call_sum_us",
    "trace.source_sha.deferred_new_model.count", "trace.source_sha.deferred_new_model.worker_or_call_sum_us",
    "trace.source_sha.deferred_new_model.union_wall_us", "trace.source_sha.deferred_new_model.envelope_wall_us",
    "trace.source_sha.deferred_reuse.count", "trace.source_sha.deferred_reuse.worker_or_call_sum_us",
    "trace.native_read.initial_model.worker_or_call_sum_us", "trace.native_read.deferred_new_model.worker_or_call_sum_us",
    "initial.map_stages.reference_index_read_us", "initial.map_stages.asset_parse_wall_us", "initial.map_stages.build_total_us",
]


def aggregate(rows, category):
    groups = {mode: [row for row in rows if row["status"] == "complete" and row["name"].startswith(category+"_"+mode+"_")]
              for mode in ("old", "new")}
    result = {"complete_abba": all(len(group) == 2 for group in groups.values()),
              "counts": {mode: len(group) for mode, group in groups.items()}}
    if not result["complete_abba"]:
        return result
    result["means"] = {mode: {key: mean([get_path(row, key) for row in group])
                              if all(number(get_path(row, key)) for row in group) else None
                              for key in MEAN_FIELDS} for mode, group in groups.items()}
    result["new_minus_old"] = {}
    for key in MEAN_FIELDS:
        old, new = result["means"]["old"][key], result["means"]["new"][key]
        result["new_minus_old"][key] = {"absolute": new-old, "percent": (new-old)/old*100 if old else None} if old is not None and new is not None else None
    failure_counts = [row["integrity"].get("failures") for group in groups.values() for row in group]
    result["functional_failures"] = sum(failure_counts) if all(number(value) for value in failure_counts) else None
    result["log_errors"] = sum(row["integrity"]["errors"] for group in groups.values() for row in group)
    for key in ("map_sha", "formal_sha", "authored_records"):
        values = [row["integrity"].get(key) for group in groups.values() for row in group]
        result[key+"_all_equal"] = all(value is not None and value == values[0] for value in values)
    result["initial_native_hits"] = [row["initial"]["admission"].get("native_cache_hits") for group in groups.values() for row in group]
    result["deferred_model_counts"] = [row["trace"]["deferred_model_count"] for group in groups.values() for row in group]
    result["all_hardware_windows_enclosed"] = all(window["enclosed"] for group in groups.values() for row in group for window in row["hardware"]["windows"].values())
    result["trace_drops"] = [row["trace"]["dropped"] for group in groups.values() for row in group]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, default=REPORTS)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent/"summary.json")
    args = parser.parse_args()
    rows = [read_run(args.reports, name) for name in RUNS]
    summary = {
        "generated_utc": datetime.now(timezone.utc).isoformat(), "report_directory": str(args.reports),
        "order": RUNS, "runs": rows, "warm": aggregate(rows, "warm"), "rebuild": aggregate(rows, "rebuild"),
        "notes": [
            "Incomplete/missing reports remain explicit; no fabricated zeros or partial-run ABBA means.",
            "Full entry is the profile's measured entry_ms. Core readiness and safety readiness are different gates.",
            "Nine initial native models and eleven deferred new models are expected comparison invariants, not hardcoded successful measurements.",
            "Trace stage sums overlap; union/envelope are wall intervals, and none is measured CPU time. Compiler/reader feature flags and exact build are preserved.",
            "No image/asset/source reads or new SHA calculations. Integrity uses the profiler's recorded source hashes and final unchanged check.",
            "Native budget and ready-worker parking are combined in old/new unless recorded flags say otherwise; an ABBA cannot assign their individual contribution.",
        ],
    }
    output = args.output
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    compact = [{"name": row["name"], "status": row["status"],
                **({key: row[key] for key in ("entry_ms", "core_ms", "safety_ms", "cpu_cores", "peak_rss_bytes", "peak_private_bytes")} if row["status"] == "complete" else {})}
               for row in rows]
    print(json.dumps({"runs": compact, "warm": summary["warm"], "rebuild": summary["rebuild"], "output": str(output)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
