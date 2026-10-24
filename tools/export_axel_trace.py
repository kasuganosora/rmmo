"""Export existing Axel diagnostics as a partial Chrome Trace, without inferred edges.

Usage: python tools/export_axel_trace.py --report REPORT --native NATIVE185
       --validation VALIDATION --output OUT.trace.json --coverage OUT.coverage.json
All timestamps remain absolute Godot monotonic microseconds (not Unix time).
Sampled counters and frame intervals are observations, never task/CPU spans.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
from typing import Any

API_NAMES = ["submit_lock", "submit", "present_lock", "present", "acquire", "fence",
             "transfer_pool_wait", "transfer_operations_wait", "transfer_thread_wait", "transfer_lease"]
LOSS_KEYS = ["evicted_ticket_prefix", "contention_drops", "invalid_records"]
TRANSFER_LOSS_KEYS = ["pending_drops", "lease_overflow", "lease_unmatched",
                      "lease_duplicate", "lease_residual", "active_leases"]
MAX_FRAME = (1 << 64) - 1


class InvalidEvidence(ValueError):
    pass


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise InvalidEvidence(reason)


def integer(value: Any, minimum: int = 0) -> bool:
    return type(value) is int and value >= minimum


def number(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def browser_safe(value: Any) -> Any:
    """Keep 64-bit object IDs, pointer identities and frame sentinels exact in JS."""
    if type(value) is int and abs(value) > (1 << 53) - 1:
        return str(value)
    if isinstance(value, dict):
        return {str(k): browser_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [browser_safe(v) for v in value]
    return value


def export_trace(report: dict, native: dict | None = None,
                 validation: dict | None = None) -> tuple[dict, dict]:
    pid, origin = report.get("pid"), report.get("begin_ticks_us")
    require(integer(pid, 1) and integer(origin, 1), "report PID/absolute begin_ticks_us missing or invalid")
    if validation is not None:
        require(validation.get("accepted") is True, "source validation is not accepted")
        require(all(v is True for v in validation.get("checks", {}).values()), "source validation check failed")
    events: list[dict] = []
    lanes: dict[str, int] = {}
    counts: Counter = Counter()
    gaps: list[str] = [
        "Partial timeline only; no dependency/flow edges or complete critical path are inferred.",
        "GPU execution/frame identity is unknown. Engine process frames are not GPU frames.",
        "Route frame wall intervals include all intervening work/waits; they are not function or CPU spans.",
        "Capacity counters are discrete observations; no interpolation, occupancy or CPU utilization inference.",
        "No exact record-to-spec, stream-generation or batch-generation dependency links in this export.",
    ]
    legacy_failed = validation.get("failed_checks", []) if validation is not None else []
    if legacy_failed:
        gaps.append("Upstream accepted=true and current checks all pass, but its retained failed_checks list is nonempty. Preserved as a validation metadata inconsistency; no original report was changed.")

    def lane(name: str) -> int:
        if name not in lanes:
            lanes[name] = len(lanes) + 1
            events.append({"ph": "M", "pid": pid, "tid": lanes[name], "name": "thread_name", "args": {"name": name}})
        return lanes[name]

    def emit(ph: str, name: str, category: str, track: str, at: int | float,
             args: dict | None = None, duration: int | float | None = None) -> None:
        require(number(at) and at >= 0, "invalid absolute event clock: " + name)
        row = {"ph": ph, "name": name, "cat": category, "pid": pid,
               "tid": lane(track), "ts": at, "args": browser_safe(args or {})}
        if ph == "i":
            row["s"] = "t"
        if duration is not None:
            require(number(duration) and duration >= 0, "negative/nonfinite duration: " + name)
            row["dur"] = duration
        events.append(row)
        counts[category] += 1

    emit("i", "report.begin", "anchor", "Reported anchors", origin)
    for key in ["initialize_us", "run_us", "session_begin_us", "sources_begin_us",
                "sources_end_us", "sources_hashed_us", "spawn_parsed_us"]:
        value = report.get("startup", {}).get(key)
        if integer(value, 1):
            emit("i", "startup." + key, "anchor", "Reported anchors", value)
    for key in ["loader_ms", "entry_ms", "stream_settled_ms", "batches_ready_ms"]:
        value = report.get(key)
        if number(value) and value >= 0:
            emit("i", "reported." + key, "anchor", "Reported anchors", origin + value * 1000,
                 {"kind": "reported endpoint, not a measured function span"})
    ready = report.get("origin_first_ready", {})
    if number(ready.get("at_ms")) and ready["at_ms"] >= 0:
        emit("i", "origin_first_ready observation", "anchor", "Reported anchors",
             origin + ready["at_ms"] * 1000, ready)
    anchor = report.get("cpu_time_anchor")
    if anchor:
        require(integer(anchor.get("ticks_us"), 1) and integer(anchor.get("unix_us"), 1), "invalid CPU clock anchor")
        emit("i", "Godot/Unix clock anchor", "anchor", "Reported anchors", anchor["ticks_us"], anchor)

    last_frame_end = -1.0
    frame_holes = 0
    for index, row in enumerate(report.get("frames", [])):
        end, duration = row.get("at_ms"), row.get("ms")
        require(number(end) and number(duration) and end >= 0 and duration >= 0, "invalid route frame clock")
        require(end >= last_frame_end, "route frame observations run backwards")
        if last_frame_end >= 0 and abs((end - duration) - last_frame_end) > .01:
            frame_holes += 1
        last_frame_end = end
        emit("X", "frame wall: " + str(row.get("phase", "unknown")), "observation.frame_wall",
             "Route frame wall observations (not CPU)", origin + (end - duration) * 1000,
             {"observation_index": index, "phase_at_end": row.get("phase"),
              "engine_process_frame": row.get("engine_frame", "unknown"), "gpu_frame": "unknown"}, duration * 1000)
    if frame_holes:
        gaps.append(f"{frame_holes} frame intervals do not meet their preceding observation within 10us; preserved without filling gaps.")

    capacity = report.get("capacity_timeline", {})
    columns, samples = capacity.get("columns", []), capacity.get("samples", [])
    if samples:
        require(columns and columns[0] == "at_us" and len(set(columns)) == len(columns), "invalid capacity columns")
        previous = -1
        for row in samples:
            require(len(row) == len(columns) and integer(row[0]) and row[0] >= previous, "invalid capacity clock/row")
            previous = row[0]
            args = dict(zip(columns[1:], row[1:]))
            require(all(number(v) or type(v) is bool for v in args.values()), "capacity counter is not numeric")
            emit("C", "Capacity observation", "observation.capacity", "Capacity samples (not worker CPU)",
                 origin + row[0], {k: int(v) if type(v) is bool else v for k, v in args.items()})

    model_skips = []
    tasks = report.get("map_profile", {}).get("asset_admission_details", {}).get("tasks", {})
    for path, task in tasks.items():
        for index, stage in enumerate(task.get("stages", [])):
            identity = f"initial-model:{path}:stage-{index}"
            start, end = stage.get("worker_started_us"), stage.get("worker_finished_us")
            if not isinstance(path, str) or not path or not isinstance(stage.get("stage"), str) or not stage["stage"] or not integer(start, 1) or not integer(end, 1):
                model_skips.append({"task": identity, "reason": "missing actual worker start/end or identity; no duration-derived substitute"})
                continue
            require(end >= start, "initial model worker clock runs backwards")
            for key, relation in [("dispatched_us", lambda v: v <= start), ("joined_us", lambda v: v >= end)]:
                if key in stage:
                    require(integer(stage[key], 1) and relation(stage[key]), "initial model " + key + " contradicts worker clock")
            emit("X", stage["stage"] + " worker wall", "initial_model.worker_wall",
                 identity + " (thread unknown)", start,
                 {"task_identity": identity, "path": path, "stage_ordinal": index,
                  "stage": stage["stage"], "thread_identity": "unknown", "error": stage.get("error")}, end - start)
            for key in ["dispatched_us", "joined_us"]:
                if integer(stage.get(key), 1):
                    emit("i", key, "initial_model.marker", identity + " (thread unknown)", stage[key], {"task_identity": identity})
    if model_skips:
        gaps.append(f"{len(model_skips)} initial model stages lack exact endpoint/identity data and were omitted.")

    completed = report.get("publication_audit_v178", {})
    journal = completed.get("trace", {})
    if journal:
        require(journal.get("dropped") == 0, "CompletedTrace lost events")
        require(journal.get("timebase") == "absolute_godot_ticks_us" and journal.get("origin_us") == origin, "CompletedTrace clock identity mismatch")
        for row in journal.get("events", []):
            generation, path, at = row.get("generation"), row.get("path"), row.get("at_us")
            require(type(generation) is int and generation != 0 and isinstance(path, str) and path and integer(at, 1), "CompletedTrace event identity/clock invalid")
            require(isinstance(row.get("event"), str) and row["event"], "CompletedTrace event name missing")
            args = {"path": path, "generation": str(generation), "details": row.get("details", {})}
            track = f"Deferred owner {path} generation {generation} (logical lane)"
            emit("i", row["event"], "completed_job.marker", track, at, args)
            if row["event"] == "worker_finished":
                start = row.get("details", {}).get("started_us")
                if integer(start, 1):
                    require(start <= at, "CompletedTrace worker clock runs backwards")
                    emit("X", "Deferred worker wall", "completed_job.worker_wall", track, start,
                         dict(args, thread_identity="unknown"), at - start)
                else:
                    gaps.append("CompletedTrace worker_finished lacks actual start; marker only.")
        gaps.append("CompletedTrace private_started follows cursor setup; committed precedes synchronous publication callbacks. No service spans are inferred from these markers.")
    else:
        gaps.append("CompletedTrace absent: Deferred task generations and lifecycle unavailable in this run.")

    native_coverage = {"present": native is not None}
    if native is not None:
        require(native.get("schema") == 185 and native.get("api_names") == API_NAMES, "native schema/API identity mismatch")
        require(native.get("pid") == pid, "native/report PID mismatch")
        require(all(native.get(k) is True for k in ["complete", "quiescent", "event_coverage_complete"]), "native recording incomplete")
        require(all(native.get(k) == 0 for k in LOSS_KEYS), "native ring loss or invalid records")
        require(all(native.get("transfer_coverage", {}).get(k) == 0 for k in TRANSFER_LOSS_KEYS), "native transfer coverage loss")
        initialized, threshold = native.get("initialized_ticks_us"), native.get("threshold_us")
        require(integer(initialized, 1) and initialized <= origin and integer(threshold), "native clock origin/threshold invalid")
        rows = native.get("events", [])
        require(native.get("selected_events") == native.get("written_events") == len(rows), "native selected/written loss")
        identities: dict[int, int] = {}
        per_api = Counter()
        for index, row in enumerate(rows):
            start, end, api = row.get("begin_us"), row.get("end_us"), row.get("api")
            gid, tid = row.get("thread_id"), row.get("native_tid")
            require(row.get("seq") == index, "native sequence gap/reorder")
            require(integer(start, initialized) and integer(end, start), "native API clock invalid")
            require(integer(api) and api < len(API_NAMES) and integer(gid, 1) and integer(tid, 1), "native API/thread identity invalid")
            require(gid not in identities or identities[gid] == tid, "Godot thread maps to conflicting native TIDs")
            identities[gid] = tid
            require(end - start >= threshold or row.get("result") != 0, "native row violates selection threshold")
            frame, flags = row.get("frame"), row.get("flags")
            require(integer(frame) and flags in [0, 1] and ((flags == 1 and gid == 1 and frame != MAX_FRAME) or (flags == 0 and frame == MAX_FRAME)), "native engine-frame/thread identity invalid")
            args = dict(row)
            args.update(device_namespace="RenderingDevice" if api >= 6 else "RenderingDeviceDriverVulkan",
                        gpu_frame="unknown", engine_process_frame=frame if flags == 1 else "unknown")
            for key in ["device", "queue", "object", "lease_id"]:
                require(integer(row.get(key)), "native object identity invalid: " + key)
                args[key] = str(row[key])
            emit("X", API_NAMES[api], "native185.api_wall", f"Native Godot {gid} / Win32 {tid}", start, args, end - start)
            per_api[api] += 1
        aggregates = native.get("aggregates", [])
        require(len(aggregates) == len(API_NAMES), "native aggregate coverage missing")
        for api, row in enumerate(aggregates):
            require(row.get("api") == api and integer(row.get("calls")) and row["calls"] >= per_api[api], "native aggregate identity/count invalid")
            require(row.get("over_threshold") == per_api[api], "native selected API count differs from aggregate")
        native_coverage.update(threshold_us=threshold, selected_spans=len(rows),
                               total_api_calls=sum(row["calls"] for row in aggregates),
                               thread_mapping={str(k): v for k, v in identities.items()},
                               aggregates=aggregates)
        gaps.append(f"Native APIs retain only duration >= {threshold}us or nonzero result; unselected calls have aggregate counts but no spans. GPU duration is unavailable.")
    else:
        gaps.append("Native185 recording absent; no driver/API spans exported.")

    coverage = {"accepted": True, "partial_timeline": True, "complete_critical_path": False,
                "dependency_edges": 0, "timestamp_domain": "absolute_godot_monotonic_ticks_us",
                "pid": pid, "report_begin_ticks_us": origin, "source_validation_supplied": validation is not None,
                "upstream_retained_failed_checks": legacy_failed,
                "upstream_current_failed_checks": [],
                "clock_identity_scope": "Same-process PID and declared Godot tick domain; explicit clocks/order checked. No GPU clock synchronization or sampled-frame identity inference.",
                "source_engine": report.get("engine"), "source_map_sha": report.get("map_sha"),
                "completed_trace_reported_complete": completed.get("trace_complete"),
                "events_by_category": dict(counts), "logical_lanes": len(lanes),
                "native": native_coverage, "initial_model_skips": model_skips,
                "frame_interval_discontinuities": frame_holes, "gaps": list(dict.fromkeys(gaps))}
    trace = {"traceEvents": events, "displayTimeUnit": "ms", "otherData": coverage}
    return trace, coverage


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--native", type=Path)
    parser.add_argument("--validation", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--coverage", type=Path, required=True)
    args = parser.parse_args()
    for path in [args.output, args.coverage]:
        if path.exists():
            parser.error("Refuse to overwrite evidence: " + str(path))
    require(args.output.resolve() != args.coverage.resolve(), "trace and coverage paths must differ")
    sources = {}

    def read(path: Path | None):
        if path is None:
            return None
        data = path.read_bytes()
        sources[str(path.resolve())] = hashlib.sha256(data).hexdigest()
        return json.loads(data.decode("utf-8-sig"))

    try:
        trace, coverage = export_trace(read(args.report), read(args.native), read(args.validation))
    except InvalidEvidence as error:
        coverage = {"accepted": False, "reason": str(error), "input_sha256": sources,
                    "trace_written": False, "complete_critical_path": False}
        args.coverage.write_text(json.dumps(coverage, indent=2), encoding="utf-8")
        print(json.dumps(coverage))
        return 2
    coverage["input_sha256"] = sources
    args.output.write_text(json.dumps(trace, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    args.coverage.write_text(json.dumps(coverage, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"trace": str(args.output), "coverage": str(args.coverage),
                      "events": coverage["events_by_category"], "partial_timeline": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
