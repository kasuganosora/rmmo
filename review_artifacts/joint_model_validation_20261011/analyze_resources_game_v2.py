"""Small-file read-only analysis of the completed resource-only game ABBA."""
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean

from analyze_results import hardware_span, read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("resources_game_v2_analysis.json")
NAMES = ["game_baseline_a1_v2", "game_preferred_b1_v2", "game_preferred_b2_v2", "game_baseline_a2_v2"]
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
              "retained_charge_bytes": task["retained_charge_bytes"], "native_bound_bytes": task["memory"].get("native_bound_bytes"), "compiled_read_reservation_bytes": task["memory"].get("compiled_read_reservation_bytes"), "native_payload_sha": task["memory"].get("native_payload_sha"), "state": task["state"], "compiled": task["compiled"], "blocked_us_by_reason": task["blocked_us_by_reason"], "stages": task["stages"], "compiled_stages_ms": {}}
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
    native_is_less_than_raw = body["estimated_bytes"] < task["raw_envelope_bytes"]
    return {"descriptor": str(cache / "footprints_v1" / (key + ".json")),
            "body_checksum_valid": hashlib.sha256(envelope["body"].encode()).hexdigest() == envelope["sha256"],
            "footprint_generator_matches_current_source": body["footprint_generator"] == footprint_generator,
            "descriptor_matches_manifest": all(body[k] == index[k] for k in ("generator", "source_sha", "payload_sha", "bytes")),
            "descriptor_source_path_matches": body["source_path"] == task["path"],
            "native_estimate_bytes": body["estimated_bytes"], "raw_envelope_bytes": task["raw_envelope_bytes"],
            "native_is_less_than_raw": native_is_less_than_raw,
            "fixed_native_identity_and_credit_match": task["memory_policy"] == "fixed_native_product_then_separately_admitted_raw" and task["native_payload_sha"] == body["payload_sha"] and task["native_bound_bytes"] == task["compiled_read_reservation_bytes"] == task["reserved_bytes"] == task["retained_charge_bytes"] == body["estimated_bytes"] and len(task["stages"]) == 1 and task["stages"][0]["stage"] == "compiled_read" and task["stages"][0]["error"] == 0 and task["state"] == "retained" and task["compiled"],
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
        "core_blocked_ms": {k: v / 1000 for k, v in detail["blocked_us_by_reason"].items()}, "core_scheduler_wall_ms": detail["elapsed_us"] / 1000, "core_total_blocked_wall_ms": detail["blocked_us"] / 1000, "core_task_queue_sum_ms": detail["task_queue_us"] / 1000, "core_task_queue_max_ms": detail["max_task_queue_us"] / 1000, "core_stages": detail["stages"], "core_worker_wall_equivalents": sum(s["worker_us"] for t in tasks for s in t["stages"]) / detail["elapsed_us"],
        "core_ledger_at_return": detail["ledger_at_return"], "core_tasks": tasks,
        "core_known_native_bound_replay": {
            "peak_bytes": native_peak, "budget_bytes": profile["asset_admission"]["inflight_budget_bytes"],
            "exceeds_budget": native_peak > profile["asset_admission"]["inflight_budget_bytes"],
            "all_result_bound_bytes": sum(t["budget_header_review"]["native_estimate_bytes"] for t in tasks), "equals_recorded_ledger_peak": native_peak == detail["ledger_at_return"]["peak_bytes"],
            "scope": "Re-account recorded dispatch..join intervals with known native descriptor bounds. Recorded source-bound ledger credit, not measured memory; joined outputs transfer to separately tracked retained ownership."},
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
        "critical_stage_intervals_ms_from_entry": {
            event["label"]: {"start_ms": (event["start_us"] - low) / 1000,
                             "end_ms": (event["end_us"] - low) / 1000,
                             "wall_ms": event["duration_us"] / 1000,
                             "details": event.get("details", {})}
            for event in events if event["label"] in (
                "game.source_read", "game.hydrate", "game.validate", "game.texture_decode",
                "game.texture_join_wait", "game.asset_preparation", "game.parse", "game.build",
                "game.mesh_cache_wait")
        },
        "initial_model_scheduler_interval_ms_from_entry": {
            "start_ms": (detail["started_us"] - low) / 1000,
            "end_ms": (detail["finished_us"] - low) / 1000,
            "wall_ms": detail["elapsed_us"] / 1000},
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

receipts = read_json(ROOT / "game_resources_v2_run_receipts.json")
receipt_by_name = {r["name"]: r for r in receipts}
code_identity = read_json(ROOT / "game_resources_v2_code_identity.json")
for row in runs:
    row["run_receipt"] = receipt_by_name[row["name"]]
    row["budget_acceptance"] = {
        "initial_tasks": len(row["core_tasks"]),
        "fixed_native_source_bound_tasks": sum(t["budget_header_review"]["fixed_native_identity_and_credit_match"] for t in row["core_tasks"]),
        "all_tiny_descriptor_identity_checks_pass": all(all(t["budget_header_review"][k] for k in ("body_checksum_valid", "footprint_generator_matches_current_source", "descriptor_matches_manifest", "descriptor_source_path_matches", "fixed_native_identity_and_credit_match")) for t in row["core_tasks"]),
        "native_larger_or_equal_raw_tasks": [t["path"] for t in row["core_tasks"] if not t["budget_header_review"]["native_is_less_than_raw"]],
        "initial_ledger_peak_within_cap": row["core_ledger_at_return"]["peak_bytes"] <= row["core_ledger_at_return"]["byte_limit"],
        "initial_worker_peak_within_limit": row["core_ledger_at_return"]["peak_workers"] <= row["core_admission"]["worker_limit"],
        "initial_reservations_released_at_return": row["core_ledger_at_return"]["reserved_bytes"] == row["core_ledger_at_return"]["jobs"] == row["core_ledger_at_return"]["active_workers"] == 0,
        "replayed_peak_equals_actual_ledger_peak": row["core_known_native_bound_replay"]["equals_recorded_ledger_peak"],
        "retained_sum_equals_all_known_native_bounds": row["core_admission"]["result_resident_estimate_bytes"] == row["core_admission"]["initial_required_resident_estimate_bytes"] == row["core_known_native_bound_replay"]["all_result_bound_bytes"],
        "deferred_models_all_fixed_native": row["entry_deferred"]["models"] == row["entry_deferred"]["compiled_hits"] == row["entry_deferred"]["fixed_native_jobs"] == 11,
        "deferred_recorded_ledger_peak_within_cap": row["entry_deferred"]["admission"]["peak_bytes"] <= row["entry_deferred"]["admission"]["byte_limit"],
        "deferred_retained_matches_core_transfer": row["entry_deferred"]["initial_retained_estimate_bytes"] == row["core_admission"]["result_resident_estimate_bytes"],
        "scope": "Initial task identities/credit independently matched to tiny descriptor/index headers and reconstructed from dispatch..join intervals. Deferred has aggregate fixed-native count/ledger, not per-task lease events, so its all-path lease bounds cannot be independently reconstructed from this report. Both ledgers exclude separately held initial/published results from the transient cap; neither cap claims process-RSS bound."
    }
for metric in ["core_scheduler_wall_ms", "core_total_blocked_wall_ms", "core_task_queue_sum_ms", "core_task_queue_max_ms", "core_worker_wall_equivalents"]:
    comparison[metric] = delta(*(mean(r[metric] for r in groups[k]) for k in groups))
comparison["core_blocked_ms"] = {reason: delta(*(mean(r["core_blocked_ms"].get(reason, 0) for r in groups[k]) for k in groups)) for reason in sorted({key for r in runs for key in r["core_blocked_ms"]})}
comparison["core_ledger_peak_bytes"] = delta(*(mean(r["core_ledger_at_return"]["peak_bytes"] for r in groups[k]) for k in groups))
comparison["initial_retained_bound_bytes"] = delta(*(mean(r["core_admission"]["initial_required_resident_estimate_bytes"] for r in groups[k]) for k in groups))
comparison["deferred_ledger_peak_bytes"] = delta(*(mean(r["entry_deferred"]["admission"]["peak_bytes"] for r in groups[k]) for k in groups))
result = {
    "scope": "Resource-only warm game ABBA v2, under the same corrected fixed-native budget code. Original v1 analysis preserved as historical pre-fix evidence; samples are not pooled.",
    "input_completion": "All four final game JSON, hardware siblings and run receipts exist; each receipt has exit_code 0 and failures 0. Game report has no top-level stage field, so completion uses final runner receipts rather than inferring stage from file existence.",
    "hardware_method": "Existing analyze_results.hardware_span over exact entry_epoch_s..entry_end_epoch_s; interval-weighted owned-process CPU, sampled RSS/private endpoints, GPU engine types reported separately. Core/post-core split uses reported entry_core_ready_ms.",
    "sample_order": NAMES,
    "same_reported_configuration": all(r["config"] == runs[0]["config"] for r in runs),
    "configuration_differences": {key: [r["config"][key] for r in runs] for key in CONFIG if any(r["config"][key] != runs[0]["config"][key] for r in runs)},
    "code_identity_receipt": code_identity,
    "budget_code_matches_completed_cpu_fix": code_identity.get("D:/code/rmmo/scripts/world3d/model_parse_preparation.gd") == "f2fc0c49c49ae254e41259a9c8a4c9865c63678d2d25261971fe5e3f443a7750" and code_identity.get("D:/code/rmmo/scripts/world3d/deferred_asset_loader.gd") == "195873793b8e34ec55beda2bc934094bd64bd97f0badd4bf85a514197db67702",
    "runs": runs, "comparison": comparison,
    "conclusions": [
        "The resource-only contrast now uses the same corrected budget source and matches its completed CPU fix hashes. Every initial task in every run has a fixed compiled_read stage, matching payload SHA and descriptor/index identity, and exact native reservation/retained charge: 9/9, including A's two and B's five native>=raw assets. This is no longer the old 7/9 versus 4/9 mixed-budget experiment.",
        "Initial dispatch..join native-bound replay exactly equals the recorded ledger peak in all four runs: A 4,227,630,538 B; B 4,142,350,434 B; each below the 4,294,967,296 B cap with peak four workers. Initial ledger returns to zero; full output charges 8,145,609,458 B / 7,249,031,734 B transfer to explicitly separate retained ownership. These are conservative accounting bounds, not allocation measurements or a total-RSS cap.",
        "Deferred reports 11/11 models as fixed native, no raw fallback, initial-retained transfer identical to core, and peak ledger A 8,362,719,810 B / B 6,882,624,864 B below its 8,510,964,736 B cap. This phase permits six loading workers and switches to two interactive workers; historical peak six must not be compared to the final worker_limit=2. Per-task deferred lease intervals are not present, so only initial-model peak is independently reconstructed.",
        "Entry A1=17.703416s, B1=16.609263s, B2=16.929399s, A2=17.773232s: mean 17.738324s -> 16.769331s, -0.968993s (-5.46%). Both B samples beat both A samples; N=2 per arm remains limited. A drift is 0.070s and B spread 0.320s. This is a modest measured warm-entry win, not the old v1 -11.65% result and not a demonstrated cold/release guarantee.",
        "Initial model preparation wall improves 5.035s -> 4.083s (-18.91%). Poll-based byte-limit blocked wall falls 3.270s -> 1.660s while B adds 1.167s worker-limit blocking; total blocked wall falls 3.270s -> 2.826s. Mean overlapping worker-wall equivalents rise 2.546 -> 3.054; this is task occupancy, not CPU usage. The smaller valid native bounds enable different overlap without enlarging cap or worker count.",
        "Model improvements no longer directly reduce the whole core: core readiness is 10.221s -> 10.150s (-0.071s). B models finish at entry 6.913/7.170s, but the same 55-request map texture stage ends at 7.469/8.009s, with explicit texture_join_wait 0.556/0.838s. Texture work starts at 4.791/5.359s; it becomes the late parse prerequisite, while hydrate/validation and build also vary. This is measured critical-path handoff, not evidence that the model saving disappeared or an additive 0.95s entry saving.",
        "Most measured entry gain is post-core: 7.517s -> 6.619s (-0.898s), including handoff-to-required geometry 4.905s -> 4.024s (-0.881s). Navigation readiness remains about 1.19s and final render milestone about 0.844s in B. All 408 selected + 4029 deferred references, 221 cooked meshes/30 specs, bridge 11 declared texture keys with seven resident/four prepared, physics probes and the full legacy gate are preserved.",
        "Exact entry-window CPU falls from 2.535 to 2.183 logical-core equivalents out of 12, and per-run CPU seconds 44.971 -> 36.614 (-18.58%). Mean sampled RSS peak falls 3.743GB -> 3.459GB (-7.58%); private peak 6.880GB -> 6.205GB (-9.80%). Main-thread equivalents remain ~0.537 -> 0.533. GPU averages remain low and separate: 3D 0.871% -> 0.789%, Copy 2.149% -> 2.028%; this lower-work result is not a hardware-saturation result.",
        "Losslessly cleaned pier/wall/blue-pennant source SHA spans fall ~1.005/0.752/1.035s -> 0.147/0.124/0.161s. Other individual native_read worker spans sometimes grow under changed concurrency, including the large pennant, so neither their inclusive sums nor one isolated per-model wall time establishes an additional entrance saving or a raw decoding regression.",
        "All four runs have failures=0, successful physics probe, no dropped trace events, complete hardware coverage and no hardware sampling errors. All also report one identical ObjectDB instance leak warning at exit; acceptance must not be described as zero-warning/leak-free. No early-entry gate or G1/G2/G3 candidate benefit is included; candidate switches remain off in this resource-only comparison."
    ],
    "limits": ["Two samples per variant, warm Godot debug Forward+ fixture, not a cold/release or general model-count guarantee.", "No heavy source/product hashing, import, engine or cache rebuild was performed by this analysis. Descriptor/index headers are small and checked against recorded task credit/identity; final SHA validation evidence is the measured compiled reader, not independently repeated here.", "Nested worker trace wall spans overlap, are not CPU time, and are not additive to entry time. Poll-based scheduler blocked wall does not say all workers were idle.", "Initial 4GiB cap covers active preparation; after join, native output is explicitly retained outside this in-flight cap and handed to deferred/published ownership. Deferred cap similarly is not a total process/RSS/VRAM cap.", "Entry/final deferred snapshots can legitimately retain background reference jobs. These performance reports do not independently prove cancellation/exit ownership cleanup.", "All four runs have one identical ObjectDB instance-leak warning at exit. It does not invalidate entry/physics checks, but this report does not claim zero-warning or leak-free exit acceptance.", "Same-code evidence is the runner identity receipt plus complete per-task corrected native budget binding. Final formal/temp/source conservation is a separate harness and is not rerun during timed experiments."]
}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "same_configuration": result["same_reported_configuration"], "budget_code_matches": result["budget_code_matches_completed_cpu_fix"], "entry": comparison["entry_ms"], "core": comparison["core_ms"], "tail": comparison["post_core_ms"], "model_wall": comparison["core_timings_ms"]["asset_parse_wall_us"], "hardware": comparison["hardware_entry"], "blocked":comparison["core_blocked_ms"], "worker_wall_equivalents":comparison["core_worker_wall_equivalents"], "budget": [r["budget_acceptance"] for r in runs], "models": comparison["core_tasks_by_asset"]}, ensure_ascii=False, indent=2))
