"""Read completed collision G2 ABBA only; no engine, asset hashing or edits."""
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import mean

from analyze_results import hardware_span, read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("collision_v2_analysis.json")
NAMES = ["game_collision_off_a1_v2", "game_collision_on_b1_v2", "game_collision_on_b2_v2", "game_collision_off_a2_v2"]
CONFIG = ["map", "map_sha", "formal_sha", "engine_build", "requested_spawn", "requested_chunk",
          "model_texture_sharing", "background_navigation", "effective_background_navigation", "background_wind",
          "deferred_native_preparation", "deferred_native_budget", "bridge_texture_preparation", "native_entry_prefetch",
          "collision_first", "collision_face_prefetch", "collision_candidate_cache", "collision_query_cache",
          "shared_prefab_textures", "prefab_texture_preparation", "reset_derived_cache", "reset_cache_scope", "cache_scope"]
METRICS = ["geometry_census_calls", "geometry_definition_bytes", "capture_us", "capture_bytes", "captured_meshes",
           "face_us", "face_bytes", "skipped_geometry_nodes", "models", "instances", "specs", "fixed_native_jobs",
           "compiled_hits", "worker_us", "reuse_face_jobs", "reuse_face_fallbacks", "reuse_face_prepare_bytes",
           "reuse_face_worker_us", "reuse_face_prepared_meshes", "geometry_requirement_retries", "peak_reserved_bytes",
           "peak_jobs", "geometry_definition_reserved_bytes", "demand_refresh_us", "dispatch_scan_us", "ready_scan_us",
           "max_publish_us", "frame_bookkeeping_us", "reference_preflight_us", "publication_units", "dispatch_attempts",
           "dispatch_scanned", "native_candidate_lookups", "reuse_reference_jobs"]


def percentiles(values):
    values = sorted(values)
    if not values:
        return {"count": 0}
    return {"count": len(values), "sum": sum(values), "mean": mean(values), "max": values[-1],
            **{str(p): values[min(len(values) - 1, math.ceil(len(values) * p / 100) - 1)] for p in (50, 95, 99)}}


def delta(a, b):
    return {"off_mean": a, "on_mean": b, "difference": b - a, "change_percent": (b / a - 1) * 100 if a else None}


def profile_slice(value):
    return {"metrics": {key: value.get(key, 0) for key in METRICS}, "admission": value["admission"],
            "main_thread_budgets": value["main_thread_budgets"],
            "reuse_face_fallback_reason": value.get("reuse_face_fallback_reason", "")}


receipts = {row["name"]: row for row in read_json(ROOT / "collision_v2_run_receipts.json")}
assert all(name in receipts and receipts[name]["exit_code"] == 0 for name in NAMES), "Wait for all final receipts"
runs = []
for name in NAMES:
    document = read_json(ROOT / (name + ".json"))
    hardware = read_json(ROOT / (name + ".hardware.json"))
    monitor = document["monitor"]
    events = monitor["trace"]["events"]
    start, end = document["entry_epoch_s"], document["entry_end_epoch_s"]
    entry_start_ticks = monitor["start_ticks_us"] + (start - monitor["start_epoch_s"]) * 1e6
    entry_end_ticks = entry_start_ticks + document["entry_ms"] * 1000
    runtime_frames = document["playable_runtime_frames"]
    background_end = monitor["start_epoch_s"] + monitor["span_ms"] / 1000
    background_start = background_end - runtime_frames[-1]["at_ms"] / 1000
    frame_deltas = [right["at_ms"] - left["at_ms"] for left, right in zip(runtime_frames, runtime_frames[1:])]
    main_trace_ids = {event["thread_id"] for event in events if event["label"] == "monitor.render_frame_span"}
    core_tasks = document["map_profile"]["asset_admission_details"]["tasks"]
    core_paths = set(core_tasks)
    native_peak = active_bytes = 0
    intervals = []
    for task in core_tasks.values():
        for stage in task["stages"]:
            intervals += [(stage["dispatched_us"], stage["reserved_bytes"]), (stage["joined_us"], -stage["reserved_bytes"])]
    for _, amount in sorted(intervals, key=lambda item: (item[0], item[1])):
        active_bytes += amount
        native_peak = max(native_peak, active_bytes)
    reuse_initial_paths = []
    geometry_events = []
    trace_totals = defaultdict(float)
    for event in events:
        if event["start_us"] >= entry_end_ticks:
            continue
        if event["label"] == "deferred.prepare" and event.get("details", {}).get("path") in core_paths:
            reuse_initial_paths.append({"path": event["details"]["path"], "wall_ms": event["duration_us"] / 1000,
                                       "fixed_native": event["details"].get("fixed_native")})
        if event["label"] in ("deferred.cpu_capture", "deferred.reused_faces"):
            geometry_events.append({"label": event["label"], "path": event.get("details", {}).get("path"),
                                    "thread_id": event["thread_id"], "main_thread": event["thread_id"] in main_trace_ids,
                                    "wall_ms": event["duration_us"] / 1000})
        if event["label"] != "monitor.render_frame_span":
            trace_totals[event["label"]] += max(0, min(entry_end_ticks, event["end_us"]) - max(entry_start_ticks, event["start_us"])) / 1000
    probe = document["physics_probe"]
    probe_series = [probe["baseline"]] + [candidate[phase] for candidate in probe["candidates"] for phase in ("before", "without", "after")]
    probe_identities = [{key: candidate.get(key) for key in ("uuid", "shape_count", "enabled_shape_count", "shape_types", "bounds", "layer", "layer_restored")}
                        for candidate in probe["candidates"]]
    end_physics, start_physics = document["playable_player_physics_end"], document["playable_player_physics_start"]
    physics_delta = {key: end_physics.get(key, 0) - start_physics.get(key, 0) for key in ("ticks", "total_us", "move_us", "sense_us", "visual_us")}
    physics_delta["mean_tick_us"] = physics_delta["total_us"] / physics_delta["ticks"]
    world_frames = document["playable_world_frames"]
    runtime_components = {}
    for key in ("stream", "camera", "actions", "actors", "navigation"):
        runtime_components["world." + key] = percentiles([row[key] for row in world_frames if key in row])
    for key in ("character", "weather", "hud", "outline"):
        runtime_components[key] = percentiles([row[key]["ms"] for row in runtime_frames if "ms" in row.get(key, {})])
    core = document["map_profile"]["asset_admission"]
    deferred = document["entry_deferred_profile"]
    shadow = document["entry_readiness_shadow"]
    milestones = shadow["milestones"]
    row = {
        "name": name, "variant": "on" if document["collision_geometry"] else "off",
        "report": str(ROOT / (name + ".json")), "hardware_report": str(ROOT / (name + ".hardware.json")),
        "run_receipt": receipts[name], "config_except_collision_geometry": {key: document.get(key) for key in CONFIG},
        "collision_geometry": document["collision_geometry"], "entry_ms": document["entry_ms"],
        "core_ms": document["entry_core_ready_ms"], "post_core_ms": document["entry_ms"] - document["entry_core_ready_ms"],
        "initial_model_wall_ms": document["map_profile"]["asset_parse_wall_us"] / 1000,
        "handoff_to_required_geometry_ms": (milestones["geometry_ready_us"] - shadow["started_us"]) / 1000,
        "entry_deferred": profile_slice(deferred), "final_deferred": profile_slice(document["final_deferred_profile"]),
        "budget": {
            "core": core, "initial_replayed_peak_bytes": native_peak,
            "initial_all_9_fixed_native_exact_bound": len(core_tasks) == 9 and all(task["memory"]["policy"] == "fixed_native_product_then_separately_admitted_raw" and task["compiled"] and len(task["stages"]) == 1 and task["stages"][0]["stage"] == "compiled_read" and task["stages"][0]["reserved_bytes"] == task["memory"]["native_bound_bytes"] == task["retained_charge_bytes"] for task in core_tasks.values()),
            "initial_replay_matches_peak": native_peak == core["peak_inflight_estimate_bytes"],
            "initial_peak_within_cap": core["peak_inflight_estimate_bytes"] <= core["inflight_budget_bytes"],
            "initial_ledger_zero_at_return": core["inflight_jobs_at_return"] == core["inflight_reserved_at_return"] == 0,
            "deferred_fixed_native_count_matches_models": deferred["models"] == deferred["compiled_hits"] == deferred["fixed_native_jobs"],
            "deferred_recorded_peak_within_cap": deferred["admission"]["peak_bytes"] <= deferred["admission"]["byte_limit"],
            "scope": "Initial 4GiB active-preparation and deferred transient reservations exclude separately retained/published results. Census reserve is deducted from deferred cap when enabled. These are not process-RSS/VRAM caps."
        },
        "reloaded_initial_models": reuse_initial_paths,
        "entry_geometry_trace": geometry_events,
        "entry_trace_inclusive_wall_ms": dict(sorted(trace_totals.items())),
        "hardware_entry": hardware_span(hardware, start, end),
        "hardware_background_approximate": hardware_span(hardware, background_start, background_end),
        "background_window": {"start_epoch_s": background_start, "end_epoch_s": background_end,
                              "duration_ms": runtime_frames[-1]["at_ms"], "start_after_entry_ms": (background_start - end) * 1000,
                              "method": "Derived from monitor finish epoch minus final runtime row.at_ms. Includes the small final row/profiler-restoration bookend overhead; not an explicitly persisted exact post_started epoch. All avatar hiding, physics-isolation probe and screenshots happen after monitor.finish, so they are excluded."},
        "background_frames": {
            "monitor_percentiles_ms": monitor["phase_frame_percentiles_ms"].get("playable_background"),
            "monitor_steady_percentiles_ms": monitor["phase_frame_percentiles_ms"].get("playable_steady"),
            "runtime_interrow_ms": percentiles(frame_deltas),
            "interrow_over_50ms": sum(value > 50 for value in frame_deltas),
            "interrow_over_100ms": sum(value > 100 for value in frame_deltas),
            "interrow_over_200ms": sum(value > 200 for value in frame_deltas),
            "scope": "Authoritative p50/p95/p99/max are monitor phase values. Threshold counts use consecutive runtime sample timestamps, omit the first phase-transition interval, and differ from frame callback intervals by sampling jitter (sub-ms)."},
        "runtime_components_ms": runtime_components, "player_physics_cumulative_delta": physics_delta,
        "runtime_sampling_cost": document["playable_runtime_sampling"],
        "physics": {"ok": probe["ok"], "candidate_count": probe["candidate_count"],
                    "entry_collision_body_count": document["collision_bodies"], "probe_resident_body_count": probe["resident_body_count"],
                    "samples_per_series": probe["samples"], "warmup_per_series": probe["warmup"],
                    "camera_sample_calls_excluding_warmup": sum(len(series["camera"]["samples_us"]) for series in probe_series),
                    "character_sample_calls_excluding_warmup": sum(len(series["character"]["samples_us"]) for series in probe_series),
                    "all_series_ok": all(series["ok"] for series in probe_series),
                    "restoration": probe["restoration"], "candidate_identities": probe_identities,
                    "baseline_camera_fractions": probe["baseline"]["camera_fractions"],
                    "baseline_character_collided": probe["baseline"]["character_collided"],
                    "note": "Diagnostic collision-layer isolation after timing; these queries do not replace the separately planned actual loading-transfer validation."},
        "acceptance": {"failures": document["failures"], "trace_dropped": monitor["trace"]["dropped"],
                       "early_entry_enabled": shadow["early_entry_enabled"], "gate_mode": shadow["mode"],
                       "avatar_hidden_after_measurement": document["screenshot_avatar_hidden"],
                       "authored_record_count": document["authored_record_count"],
                       "raw_fallback_count": document["map_profile"]["asset_fallback_count"],
                       "cache_reference_hit": document["map_profile"]["reference_index_hit"],
                       "cache_terrain_hit": document["map_profile"]["terrain_context_cache_hit"],
                       "final_player_position": document["final_player_position"],
                       "remaining_deferred": document["remaining_deferred"]}
    }
    runs.append(row)

groups = {kind: [row for row in runs if row["variant"] == kind] for kind in ("off", "on")}
comparison = {}
for key in ("entry_ms", "core_ms", "post_core_ms", "initial_model_wall_ms", "handoff_to_required_geometry_ms"):
    comparison[key] = delta(*(mean(row[key] for row in groups[kind]) for kind in groups))
for stage in ("entry_deferred", "final_deferred"):
    comparison[stage] = {metric: delta(*(mean(row[stage]["metrics"][metric] for row in groups[kind]) for kind in groups)) for metric in METRICS}
comparison["main_thread_budgets"] = {}
for stage in ("entry_deferred", "final_deferred"):
    comparison["main_thread_budgets"][stage] = {}
    for phase in ("covered_loading", "interactive"):
        comparison["main_thread_budgets"][stage][phase] = {key: delta(*(mean(row[stage]["main_thread_budgets"][phase][key] for row in groups[kind]) for kind in groups)) for key in ("elapsed_us", "acceptance_us", "publication_us", "max_acceptance_unit_us", "max_publication_unit_us", "over_budget_frames")}
for window in ("hardware_entry", "hardware_background_approximate"):
    comparison[window] = {}
    for kind, members in groups.items():
        values = [row[window] for row in members]
        comparison[window][kind] = {
            "cpu_logical_equivalents_weighted": sum(value["cpu_logical_equivalents_mean"] * value["cpu_coverage_s"] for value in values) / sum(value["cpu_coverage_s"] for value in values),
            "cpu_seconds_mean": mean(value["cpu_logical_equivalents_mean"] * value["cpu_coverage_s"] for value in values),
            "main_thread_cpu_equivalents_weighted": sum(value["main_thread_cpu_equivalents_mean"] * value["cpu_coverage_s"] for value in values) / sum(value["cpu_coverage_s"] for value in values),
            "rss_peak_mean_bytes": mean(value["rss_peak_bytes"] for value in values),
            "private_peak_mean_bytes": mean(value["private_peak_bytes"] for value in values),
            "gpu_engine_mean_percent_weighted": {engine: sum(value["gpu_engine_mean_percent"][engine] * value["gpu_valid_coverage_s"][engine] for value in values) / sum(value["gpu_valid_coverage_s"][engine] for value in values) for engine in values[0]["gpu_engine_mean_percent"]}}
comparison["background_monitor_ms"] = {key: delta(*(mean(row["background_frames"]["monitor_percentiles_ms"][key] for row in groups[kind]) for kind in groups)) for key in ("50", "95", "99", "max", "count")}
comparison["background_threshold_counts_per_run"] = {key: delta(*(mean(row["background_frames"][key] for row in groups[kind]) for kind in groups)) for key in ("interrow_over_50ms", "interrow_over_100ms", "interrow_over_200ms")}
comparison["runtime_component_mean_ms"] = {key: delta(*(mean(row["runtime_components_ms"][key]["mean"] for row in groups[kind]) for kind in groups)) for key in runs[0]["runtime_components_ms"]}
result = {
    "scope": "Completed same preferred-resource map, same corrected-native-budget code ABBA; only collision_geometry flag differs. Four final exit0 receipts checked. No model hashing, engine, GPU, import or source changes performed by this analysis.",
    "sample_order": NAMES, "code_identity": read_json(ROOT / "collision_v2_code_identity.json"),
    "same_configuration_except_candidate": all(row["config_except_collision_geometry"] == runs[0]["config_except_collision_geometry"] for row in runs),
    "config_differences": {key: [row["config_except_collision_geometry"][key] for row in runs] for key in CONFIG if any(row["config_except_collision_geometry"][key] != runs[0]["config_except_collision_geometry"][key] for row in runs)},
    "same_physics_probe_identity": all(row["physics"]["candidate_identities"] == runs[0]["physics"]["candidate_identities"] for row in runs),
    "same_baseline_query_results": all(row["physics"]["baseline_camera_fractions"] == runs[0]["physics"]["baseline_camera_fractions"] and row["physics"]["baseline_character_collided"] == runs[0]["physics"]["baseline_character_collided"] for row in runs),
    "runs": runs, "comparison": comparison,
    "recommendation": {"enable_by_default": False, "reason": "Material worker geometry reduction is real, but the candidate adds four full native preparations and main-thread scheduling work, has no background p95/p99 win, and both on-entry samples are slower than both off samples. Keep the candidate available but off pending ownership-aware reuse improvement and repeated complete acceptance."},
    "conclusions": [
        "Four completed same-code/same-preferred-map runs differ only in collision_geometry. Off entry 16.558/16.636s; on 17.512/19.616s. Means 16.597 -> 18.564s (+1.967s, +11.85%); core 9.546 -> 11.005s, post-core 7.051 -> 7.559s. Initial model wall is essentially unchanged (~4.305 -> 4.302s). The B2 spread and uninstrumented waits prevent assigning the full regression to one cause, but the measurements do not support default activation.",
        "Worker reduction is real and repeatable: 28 captured meshes -> 6, capture payload 40,657,932 -> 1,453,380 bytes (-96.43%), prepared face payload 18,129,204 -> 938,268 bytes (-94.82%), 41 geometry nodes skipped. Counted capture time ~0.732 -> 0.034s and face work ~0.128 -> 0.008s are worker wall timings, not additive entry savings. On also executes four reuse-face jobs (six meshes, 4,736,736-byte preparation allowance, 0.018/0.026s worker time); that allowance is not actual extra face bytes.",
        "The same on runs also hit four missing_cpu_capture fallbacks, with deferred full native reads 11 -> 15. Trace proves the additional paths were already initial-core model tasks: wall_pointed_blue_83c1f150_lossless, 5beaac..., c9c641..., bridge_long_pennants_quality. Their full preparation wall totals are ~4.07s in B1, overlapping other work. Deferred _reuse_face_offer rejects a missing ground_cpu_cache at lines 1129/1131; the dispatch fallback at 1968-1972 erases prepared ownership and re-admits the full model safely. This is a concrete added-work route, not a raw import/cache-miss claim.",
        "Geometry census runs 43/44 times by entry and 51/52 by final observation, versus zero off; it is not one scan per frame or per 104/244+ published instance. However the actual dispatch-attempt/acceptance cadence adds CPU-side scheduling work: dispatch_scan mean ~0.179 -> 0.479s, covered-loading acceptance ~0.229 -> 0.304s, and covered main work ~1.233 -> 1.404s. Publication time itself is ~0.878 -> 0.888s. The census has no dedicated timer, so the entire scan delta cannot be attributed solely to it.",
        "No measured migration of the removed bulk capture into a main-thread trace is visible: all deferred.cpu_capture and deferred.reused_faces events run on worker thread IDs, and world_stream._spec:1028-1042 gates collision capture on needs_adopted_collision; ground_batch_record keeps its independent render requirement. Still, these reports lack direct main-thread CpuMesh.capture/get_faces counters. Therefore 'zero main-thread cost return' is not proven; extra acceptance/dispatch work demonstrably returns to the main path.",
        "The timed ~10s background phase has no long-frame benefit: mean monitor p50 64.07 -> 62.70ms, p95 87.65 -> 92.18ms, p99 97.59 -> 100.55ms, per-run max 102.45 -> 109.22ms. Consecutive runtime-frame counts >100ms are off 1/0, on 2/3; none exceed 200ms in any run. All phase frames remain playable_background. Avatar hiding, screenshot capture and the physics-isolation probe occur after monitor.finish, so none accounts for these frame times.",
        "Exact entry CPU is ~2.334 -> 2.322 logical-core equivalents/12, but longer on entry raises CPU seconds 38.74 -> 43.10. Sampled mean RSS peak 3.532 -> 3.430GB improves slightly, while private peak 6.351 -> 6.686GB grows. Approximate timed-background CPU is 0.705 -> 0.672 cores with stream callback mean 1.867 -> 1.976ms. RSS alone is insufficient evidence of a net resource win.",
        "Initial preparation remains 9/9 fixed-native with identical 4,142,350,434-byte peak below 4GiB and zero active ledger at return. Deferred on reserves an extra 4MiB census allowance, reducing cap from 8,510,964,736 to 8,506,770,432 bytes; peaks off ~6.883GB, on 8.033/7.989GB stay within the corresponding cap. Higher on native-job count increases pressure despite much smaller geometry payload; these transient caps exclude published/retained resources and do not cap process private memory.",
        "All four physics probes pass with the same six candidate identities/bounds/shapes, 230 entry bodies, 241 probe-resident bodies, seven samples plus two warmups per series, 133 measured camera and 133 measured character query calls per run (warmups excluded), and every restoration flag true. Baseline camera fractions and character collision booleans are identical. This is local correctness evidence, not a substitute for the separate real unready-destination loading transfer.",
        "Recommendation: keep collision_geometry default off. Before another activation attempt, eliminate the four unnecessary full-native re-preparations with an exact-template/source-bound collision requirement proof and bounded CPU-only reuse preparation; preserve conservative unknown/mixed-consumer upgrades, final source validation, all lease/disposal rules and no main-thread GPU readback. Re-measure complete entry/background/physical-transfer behavior; do not raise the budget or dismiss the slower samples to advertise the geometry byte reduction."
    ],
    "static_evidence": [
        {"path": "scripts/world3d/deferred_asset_loader.gd", "line": 905, "finding": "_geometry_consumers is called at dispatch attempts and joined acceptance; scans directory/hydrated/pending consumers conservatively."},
        {"path": "scripts/world3d/deferred_asset_loader.gd", "line": 1129, "finding": "_reuse_face_offer cannot read shared GPU arrays under a small reuse lease; missing ground_cpu_cache returns a fallback reason."},
        {"path": "scripts/world3d/deferred_asset_loader.gd", "line": 1968, "finding": "Missing capture removes prepared-path state and separately re-admits a complete model, observed on exactly four initial paths."},
        {"path": "scripts/world3d/world_stream.gd", "line": 1028, "finding": "Adoption gates collision capture by effective collision need; independent render batching can retain CPU geometry."},
        {"path": "tools/profile_game_entry.gd", "line": 358, "finding": "Ten-second runtime loop precedes monitor.finish at 413, physics probe at 417 and avatar hiding at 469."}
    ],
    "limits": ["N=2 per arm; B2 variation is large, so do not attribute the entire observed entry regression to one mechanism. This does not justify enabling a slower candidate.",
               "Capture/face bytes are counted worker outputs, not all resource memory. Four reuse-face jobs have a separate 4,736,736-byte conservative preparation allowance; it is not an actual face-output count and must not be added as if it were.",
               "There is no dedicated main-thread CpuMesh.capture/get_faces counter. The traced geometry events all run on workers, and adoption skips effective-none collision capture, but this cannot prove zero main-thread geometry cost in every path.",
               "Background hardware epoch is reconstructed from monitor finish and last runtime row; frame-phase statistics are authoritative. Avatar hiding and physics isolation occur after monitor.finish and cannot explain the recorded background long frames.",
               "Final deferred metrics are taken after the diagnostic physics probe's quiesce/restore, so final-entry deltas are not guaranteed to be exactly the ten-second background window. Background runtime frames and hardware use their own timed scope.",
               "Inclusive worker wall/parent-child timers overlap and are not additive CPU time; main scheduling/publication aggregates cannot identify an individual mutex or GPU wait.",
               "All four runs share one ObjectDB instance-leak warning at exit; do not claim leak-free or zero-warning acceptance."]
}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "same_config": result["same_configuration_except_candidate"], "same_physics": result["same_physics_probe_identity"], "same_query": result["same_baseline_query_results"], "entry": comparison["entry_ms"], "core": comparison["core_ms"], "tail": comparison["post_core_ms"], "hardware_entry": comparison["hardware_entry"], "hardware_background": comparison["hardware_background_approximate"], "longframes": comparison["background_monitor_ms"], "main_budget": comparison["main_thread_budgets"], "components": comparison["runtime_component_mean_ms"]}, ensure_ascii=False, indent=2))
