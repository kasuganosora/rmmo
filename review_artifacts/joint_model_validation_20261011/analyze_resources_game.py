"""Small-file read-only analysis of the completed resource-only game ABBA."""
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean

from analyze_results import hardware_span, read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("resources_game_analysis.json")
NAMES = ["game_baseline_a1", "game_preferred_b1", "game_preferred_b2", "game_baseline_a2"]
CONFIG = ["engine_build", "requested_spawn", "requested_chunk", "collision_geometry", "model_texture_sharing",
          "background_navigation", "effective_background_navigation", "background_wind", "deferred_native_preparation",
          "deferred_native_budget", "bridge_texture_preparation", "native_entry_prefetch", "collision_first",
          "collision_face_prefetch", "collision_candidate_cache", "collision_query_cache", "shared_prefab_textures",
          "prefab_texture_preparation", "cpu_river_index", "reset_derived_cache", "reset_cache_scope", "cache_scope"]
TIMINGS = ["asset_parse_wall_us", "asset_parse_us", "parser_total_us", "parse_us", "reference_index_read_us",
           "validate_us", "texture_decode_us", "build_total_us", "mesh_cache_read_wait_us", "cooked_restore_us",
           "prefab_decode_us", "hydrate_us"]
handoff = read_json(Path("D:/code/rmmo/review_artifacts/town_asset_size_audit_20261011/candidate_handoff.json"))
labels = {}
for item in handoff["preferred"]:
    labels[item["original"].lower()] = item["label"]
    labels[item["candidate"].lower()] = item["label"]


def slim_task(path, task, events):
    result = {"path": path, "label": labels.get(path.lower(), Path(path).stem),
              "queue_ms": task["queue_us"] / 1000, "worker_wall_ms": sum(s["worker_us"] for s in task["stages"]) / 1000,
              "memory_policy": task["memory"]["policy"], "raw_envelope_bytes": task["memory"]["raw_import_reservation_bytes"],
              "reserved_bytes": task["stages"][0]["reserved_bytes"],
              "retained_charge_bytes": task["retained_charge_bytes"], "stages": task["stages"], "compiled_stages_ms": {}}
    for event in events:
        if not event["label"].startswith("compiled.") or event.get("details", {}).get("path", "").lower() != path.lower():
            continue
        if not any(s["worker_started_us"] <= event["start_us"] <= event["end_us"] <= s["joined_us"] for s in task["stages"]):
            continue
        k = event["label"]
        result["compiled_stages_ms"][k] = result["compiled_stages_ms"].get(k, 0) + event["duration_us"] / 1000
    return result


def inspect_budget_header(task):
    # Descriptors are tiny JSON; do not read/hash the model or native product.
    cache = Path("D:/code/rmmo_runtime/cache/world3d/compiled_assets_v1")
    key = hashlib.sha256(task["path"].replace("\\", "/").encode()).hexdigest()
    envelope = read_json(cache / "footprints_v1" / (key + ".json"))
    body = json.loads(envelope["body"])
    index = read_json(cache / (key + ".json"))
    footprint_code = Path("D:/code/rmmo/scripts/world3d/compiled_asset_footprint.gd").read_bytes()
    footprint_generator = hashlib.sha256(("1:" + hashlib.sha256(footprint_code).hexdigest()).encode()).hexdigest()
    expected_native_route = body["estimated_bytes"] < task["raw_envelope_bytes"]
    return {"descriptor": str(cache / "footprints_v1" / (key + ".json")),
            "body_checksum_valid": hashlib.sha256(envelope["body"].encode()).hexdigest() == envelope["sha256"],
            "footprint_generator_matches_current_source": body["footprint_generator"] == footprint_generator,
            "descriptor_matches_manifest": all(body[k] == index[k] for k in ("generator", "source_sha", "payload_sha", "bytes")),
            "descriptor_source_path_matches": body["source_path"] == task["path"],
            "native_estimate_bytes": body["estimated_bytes"], "raw_envelope_bytes": task["raw_envelope_bytes"],
            "native_is_less_than_raw": expected_native_route,
            "production_branch_matches_lower_estimate_rule": expected_native_route == (task["memory_policy"] == "fixed_native_product_then_separately_admitted_raw"),
            "source_and_product_not_rehashed": True}


runs = []
for name in NAMES:
    document = read_json(ROOT / (name + ".json"))
    hardware = read_json(ROOT / (name + ".hardware.json"))
    profile = document["map_profile"]
    detail = profile["asset_admission_details"]
    events = document["monitor"]["trace"]["events"]
    start, end = document["entry_epoch_s"], document["entry_end_epoch_s"]
    core_end = start + document["entry_core_ready_ms"] / 1000
    shadow = document["entry_readiness_shadow"]
    milestones = shadow["milestones"]
    tasks = [slim_task(path, task, events) for path, task in detail["tasks"].items()]
    for task in tasks:
        task["budget_header_review"] = inspect_budget_header(task)
    native_intervals = []
    for task in tasks:
        for stage in task["stages"]:
            native_intervals += [(stage["dispatched_us"], task["budget_header_review"]["native_estimate_bytes"]),
                                 (stage["joined_us"], -task["budget_header_review"]["native_estimate_bytes"])]
    native_active = native_peak = 0
    for _, amount in sorted(native_intervals, key=lambda x: (x[0], x[1])):
        native_active += amount
        native_peak = max(native_peak, native_active)
    trace_totals = defaultdict(float)
    low = document["monitor"]["start_ticks_us"] + (start - document["monitor"]["start_epoch_s"]) * 1e6
    high = low + (end - start) * 1e6
    for event in events:
        if event["label"] == "monitor.render_frame_span":
            continue
        overlap = max(0, min(high, event["end_us"]) - max(low, event["start_us"]))
        if overlap:
            trace_totals[event["label"]] += overlap / 1000
    row = {
        "name": name, "variant": "baseline" if "baseline" in name else "preferred",
        "report": str(ROOT / (name + ".json")), "hardware_report": str(ROOT / (name + ".hardware.json")),
        "entry_ms": document["entry_ms"], "core_ms": document["entry_core_ready_ms"],
        "post_core_ms": document["entry_ms"] - document["entry_core_ready_ms"],
        "map": document["map"], "map_sha": document["map_sha"], "formal_sha": document["formal_sha"],
        "config": {k: document.get(k) for k in CONFIG},
        "acceptance": {"failures": document["failures"], "physics_probe_ok": document["physics_probe"]["ok"],
                       "screenshot_avatar_hidden": document["screenshot_avatar_hidden"],
                       "trace_dropped": document["monitor"]["trace"]["dropped"],
                       "early_entry_enabled": shadow["early_entry_enabled"], "gate_mode": shadow["mode"]},
        "cache": {k: profile.get(k) for k in ["reference_index_hit", "reference_index_reason", "reference_index_rebuilt_before_models",
                  "terrain_context_cache_hit", "mesh_cache_candidate", "mesh_cache_scope", "cooked_meshes", "cooked_specs",
                  "asset_fallback_count", "initial_asset_paths", "reference_selected_count", "reference_deferred_count"]},
        "core_timings_ms": {k: profile[k] / 1000 for k in TIMINGS},
        "core_admission": profile["asset_admission"],
        "core_admission_policy_counts": dict(Counter(t["memory_policy"] for t in tasks)),
        "core_blocked_ms": {k: v / 1000 for k, v in detail["blocked_us_by_reason"].items()},
        "core_ledger_at_return": detail["ledger_at_return"], "core_tasks": tasks,
        "core_known_native_bound_replay": {
            "peak_bytes": native_peak, "budget_bytes": profile["asset_admission"]["inflight_budget_bytes"],
            "exceeds_budget": native_peak > profile["asset_admission"]["inflight_budget_bytes"],
            "all_result_bound_bytes": sum(t["budget_header_review"]["native_estimate_bytes"] for t in tasks),
            "scope": "Re-account recorded dispatch..join intervals with known native descriptor bounds. This is not measured memory and not a prediction of corrected scheduling time."},
        "entry_deferred": {k: document["entry_deferred_profile"][k] for k in ["admission", "models", "compiled_hits", "fixed_native_jobs",
                           "worker_us", "capture_us", "captured_meshes", "capture_bytes", "face_us", "face_bytes", "reference_worker_us",
                           "initial_retained_estimate_bytes", "peak_reserved_bytes", "peak_jobs", "entry_prefetch_jobs",
                           "entry_prefetch_joined_jobs", "bridge_texture_jobs", "bridge_texture_declared_keys",
                           "bridge_texture_missing_keys", "bridge_texture_resident_keys", "prefab_pixels", "main_thread_budgets"]},
        "final_deferred_ledger": document["final_deferred_profile"]["admission"],
        "milestone_intervals_ms": {
            "handoff_to_geometry": (milestones["geometry_ready_us"] - shadow["started_us"]) / 1000,
            "geometry_to_physics_frame": (milestones["physics_ready_us"] - milestones["geometry_ready_us"]) / 1000,
            "physics_to_navigation": (milestones["navigation_ready_us"] - milestones["physics_ready_us"]) / 1000,
            "navigation_to_base_gameplay": (milestones["base_gameplay_ready_us"] - milestones["navigation_ready_us"]) / 1000,
            "base_gameplay_to_render": (milestones["render_ready_us"] - milestones["base_gameplay_ready_us"]) / 1000},
        "hardware_entry": hardware_span(hardware, start, end),
        "hardware_core": hardware_span(hardware, start, core_end),
        "hardware_post_core": hardware_span(hardware, core_end, end),
        "entry_trace_worker_wall_ms_inclusive": dict(sorted(trace_totals.items())),
    }
    runs.append(row)

comparison = {}


def delta(a, b):
    return {"baseline_mean": a, "preferred_mean": b, "difference": b - a, "change_percent": (b / a - 1) * 100 if a else None}


groups = {kind: [r for r in runs if r["variant"] == kind] for kind in ("baseline", "preferred")}
for metric in ["entry_ms", "core_ms", "post_core_ms"]:
    comparison[metric] = delta(*(mean(r[metric] for r in groups[k]) for k in groups))
for parent in ["core_timings_ms", "milestone_intervals_ms"]:
    comparison[parent] = {metric: delta(*(mean(r[parent][metric] for r in groups[k]) for k in groups)) for metric in runs[0][parent]}
for window in ["hardware_entry", "hardware_core", "hardware_post_core"]:
    summary = {}
    for group, members in groups.items():
        hw = [r[window] for r in members]
        summary[group] = {
            "cpu_logical_equivalents_weighted": sum(h["cpu_logical_equivalents_mean"] * h["cpu_coverage_s"] for h in hw) / sum(h["cpu_coverage_s"] for h in hw),
            "cpu_seconds_mean": mean(h["cpu_logical_equivalents_mean"] * h["cpu_coverage_s"] for h in hw),
            "main_thread_cpu_equivalents_weighted": sum(h["main_thread_cpu_equivalents_mean"] * h["cpu_coverage_s"] for h in hw) / sum(h["cpu_coverage_s"] for h in hw),
            "rss_peak_mean_bytes": mean(h["rss_peak_bytes"] for h in hw), "private_peak_mean_bytes": mean(h["private_peak_bytes"] for h in hw),
            "rss_peak_max_bytes": max(h["rss_peak_bytes"] for h in hw), "private_peak_max_bytes": max(h["private_peak_bytes"] for h in hw),
            "gpu_engine_mean_percent_weighted": {engine: sum(h["gpu_engine_mean_percent"][engine] * h["gpu_valid_coverage_s"][engine] for h in hw) / sum(h["gpu_valid_coverage_s"][engine] for h in hw)
                                                  for engine in hw[0]["gpu_engine_mean_percent"]},
            "gpu_engine_peak_percent_max": {engine: max(h["gpu_engine_peak_percent"][engine] for h in hw) for engine in hw[0]["gpu_engine_peak_percent"]}}
    comparison[window] = summary
comparison["core_tasks_by_asset"] = {}
for label in sorted({r["label"] for r in runs[0]["core_tasks"]}):
    entry = {}
    for group, members in groups.items():
        tasks = [t for r in members for t in r["core_tasks"] if t["label"] == label]
        entry[group] = {"worker_wall_ms_mean": mean(t["worker_wall_ms"] for t in tasks),
                        "queue_ms_mean": mean(t["queue_ms"] for t in tasks),
                        "stage_worker_wall_ms_mean": {stage: mean(t["compiled_stages_ms"].get(stage, 0) for t in tasks) for stage in sorted({s for t in tasks for s in t["compiled_stages_ms"]})}}
    comparison["core_tasks_by_asset"][label] = entry

result = {
    "scope": "Completed game resources-only ABBA; small JSON/log input only, no source hashing, Godot, imports or cache rebuild.",
    "hardware_method": "Existing analyze_results.hardware_span over exact entry_epoch_s..entry_end_epoch_s. Interval-weighted process CPU; sampled RSS/private endpoints; per-engine GPU max-single-engine aggregation, not sum across engine types.",
    "sample_order": NAMES,
    "same_reported_configuration": all(r["config"] == runs[0]["config"] for r in runs),
    "configuration_differences": {key: [r["config"][key] for r in runs] for key in CONFIG if any(r["config"][key] != runs[0]["config"][key] for r in runs)},
    "runs": runs, "comparison": comparison,
    "conclusions": [
        "Both preferred samples are faster than both baseline samples; mean entry improves 19.970s to 17.643s (-11.65%). N=2 per variant and A1/A2 drift 2.140s; magnitude is observed in this warm debug Forward+ fixture, not a general cold/release guarantee.",
        "Core model preparation wall span improves ~5.54s to ~4.47s; model worker wall sum is overlapping and must not be added to entry time. Three losslessly cleaned core assets show lower source SHA work, while reduced pennant textures also lower native read work. Core parser/terrain/texture work overlaps this, limiting total gain.",
        "Core readiness improves ~1.07s and post-core legacy readiness ~1.25s. Preferred still spends ~10.65s before core ready and ~6.99s after; handoff-to-required geometry ~4.20s remains the biggest post-core interval. Background navigation and background wind switches are both off in these runs, and shadow early-entry is disabled; no gate weakening is part of this result.",
        "Process CPU equivalents fall while CPU seconds and memory peaks fall: lower utilization here is compatible with less work, not evidence that concurrency stopped. GPU 3D/Copy remain low; the data has no wait stacks and cannot assign the remaining idle time to disk, driver fences or a specific lock.",
        "All four runs have 9/9 initial compiled hits, 11 deferred compiled hits, reference index and terrain context hits, 221 cooked meshes/30 specs and no raw fallback. Metadata bypass for integrity is deliberate; candidate existence alone is not used as a cache-hit claim.",
        "Budget branch difference is a correctness gap, not missing footprints: model_parse_preparation.gd:72 selects a fixed native candidate only when native estimated_bytes < raw estimated_bytes; deferred_asset_loader.gd:1987 repeats it. All nine descriptor headers exist and match their current manifest/path/checksum/source generator. A uses native for 7/9 and B for 4/9; the others bypass higher known native bounds and still load native. No existing proof shows the lower raw formula covers native deserialization/capture lifetime. Same reported flags therefore do not establish a correct source-bound budget contract.",
        "The recorded initial ledger has 4 workers/4GiB in-flight and settles to zero. Its reported peaks are within 4GiB only under the lower-charge policy. Replaying those exact dispatch..join intervals with known native descriptors gives 5,464,130,518B in A and 4,567,552,794B in B, both above 4,294,967,296B. This is under-accounting against the declared bound, not proof actual RSS exceeded the cap. Retained estimates are separate published ownership, not a process-RSS cap.",
        "Deferred reports an ~7.93GiB ledger budget, peak A~7.77GiB/B~4.13GiB, loading 6 workers then interactive 2. The same candidate<raw selection exists there, so these reported peaks alone cannot prove source-bound native accounting. Historical worker peaks cannot be compared against the current interactive worker_limit=2.",
        "Entry/final deferred ledgers legitimately retain background reference jobs/ready packets. This report does not claim cancellation cleanup or zero process-exit ownership from those live snapshots. Same code/asset conservation after all runs remains subject to the separately prepared source_conservation compare.",
    ],
    "limits": ["Only warm resource replacement is measured; G1 picking/G2 collision/G3 sharing remain off and their benefits are not included.",
               "Nested trace timings are inclusive wall spans, not CPU and not additive. Derived core/post-core subwindows use the reported core readiness boundary.",
               "Core task source hashes prove actual final validation occurred; footprints and reservation estimates are conservative accounting, not measured allocation or VRAM.",
               "Reports have no per-run source code fingerprint. Engine/config equality is explicit, code freeze and end-of-run source conservation need the separate harness."],
    "budget_correctness_review": {
        "status": "fix_required_after_current_freeze_then_repeat_game_acceptance",
        "locations": ["scripts/world3d/model_parse_preparation.gd:72", "scripts/world3d/deferred_asset_loader.gd:1987"],
        "raw_formula": "asset_memory_estimate.gd:113-115: 2*encoded_source + 3*RGBA_full_mip_bound + 3*decoded_mesh + collision + overhead",
        "native_formula": "compiled_asset_footprint.gd:116-121: 64MiB + 2*native_uncompressed + 3*CPU_image_mip + 3*GPU_RGBA_mip + 4*mesh_storage + 4*mesh_capture + 3*collision_faces + containers/resources",
        "why_not_equivalent": "Lossless source cleanup can remove encoded unused images while the native active pixel/mesh statistics stay identical. Raw formula does not separately model native serialized streams and all capture/upload workspace in the native formula; min(raw,native) has no proved lifetime upper-bound equivalence.",
        "minimal_fix": "Choose any valid source-bound candidate for fixed-native reading and reserve its full native bound regardless of whether it saves bytes. If a baseline/legacy path may still deserialize native with a known descriptor, charge max(raw,native), as editor load_job.gd:442-446 already does. Native miss/source retry must retain existing disposal and separate fresh raw admission; do not alter footprint formulas, cap, worker count or release ownership early.",
        "test_gap": "test_native_model_budget.gd:25-29 always native20<raw60. test_native_model_budget_gpu.gd:238 pads raw_floor to native+128MiB. They verify smaller-native fallback ownership but do not exercise native>=raw. Footprint test validates formula integrity, not scheduler adoption of a larger bound.",
        "required_cases": ["native>raw: exact native reservation and peak concurrency obey cap", "native==raw: retain fixed product identity", "raw<cap<native: exclusive task waits for every live lease", "source change/native miss after larger native allocation: join, main disposal/retained quarantine as designed, fresh raw reservation", "same native statistics with smaller encoded source cannot lower native task credit", "baseline control that can read native preserves max envelope"],
        "expected_impact": "Corrected scheduling may reduce overlap or increase measured entry time. Preserve this resource ABBA as historical observation; do not use it as final safe-budget acceptance until corrected re-run."}}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "same_configuration": result["same_reported_configuration"], "entry": comparison["entry_ms"], "core": comparison["core_ms"], "tail": comparison["post_core_ms"], "hardware": comparison["hardware_entry"], "models": comparison["core_tasks_by_asset"]}, ensure_ascii=False, indent=2))
