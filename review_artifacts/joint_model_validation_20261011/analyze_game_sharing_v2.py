"""Read completed game texture-sharing ABBA; no engines or source hashes."""
import json
from pathlib import Path
from statistics import mean

from analyze_results import hardware_span, read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("game_sharing_v2_analysis.json")
NAMES = ["game_sharing_off_a1_v2", "game_sharing_on_b1_v2", "game_sharing_on_b2_v2", "game_sharing_off_a2_v2"]
CONFIG = ["map", "map_sha", "formal_sha", "engine_build", "requested_spawn", "requested_chunk",
          "collision_geometry", "background_navigation", "effective_background_navigation", "background_wind",
          "deferred_native_preparation", "deferred_native_budget", "bridge_texture_preparation", "native_entry_prefetch",
          "collision_first", "collision_face_prefetch", "collision_candidate_cache", "collision_query_cache",
          "shared_prefab_textures", "prefab_texture_preparation", "reset_derived_cache", "reset_cache_scope", "cache_scope"]


def delta(a, b):
    return {"off_mean": a, "on_mean": b, "difference": b-a, "change_percent": (b/a-1)*100 if a else None}


def hardware_group(rows, field):
    values = [row[field] for row in rows]
    coverage = sum(value["cpu_coverage_s"] for value in values)
    engines = values[0]["gpu_engine_mean_percent"]
    return {
        "cpu_logical_equivalents_weighted": sum(value["cpu_logical_equivalents_mean"]*value["cpu_coverage_s"] for value in values)/coverage,
        "cpu_seconds_mean": mean(value["cpu_logical_equivalents_mean"]*value["cpu_coverage_s"] for value in values),
        "main_thread_cpu_equivalents_weighted": sum(value["main_thread_cpu_equivalents_mean"]*value["cpu_coverage_s"] for value in values)/coverage,
        "rss_peak_mean_bytes": mean(value["rss_peak_bytes"] for value in values),
        "private_peak_mean_bytes": mean(value["private_peak_bytes"] for value in values),
        "gpu_engine_mean_percent_weighted": {engine: sum(value["gpu_engine_mean_percent"][engine]*value["gpu_valid_coverage_s"][engine] for value in values)/sum(value["gpu_valid_coverage_s"][engine] for value in values) for engine in engines}}


receipts = {row["name"]: row for row in read_json(ROOT / "game_sharing_v2_run_receipts.json")}
assert all(name in receipts and receipts[name]["exit_code"] == 0 and receipts[name]["failures"] == 0 for name in NAMES)
runs = []
for name in NAMES:
    document = read_json(ROOT / (name+".json"))
    hardware = read_json(ROOT / (name+".hardware.json"))
    log = (ROOT / (name+".log")).read_text(encoding="utf-8", errors="replace")
    assert "GAME_ENTRY_FINISHED failures=0" in log
    monitor = document["monitor"]
    frames = document["playable_runtime_frames"]
    frame_deltas = [b["at_ms"]-a["at_ms"] for a, b in zip(frames, frames[1:])]
    background_end = monitor["start_epoch_s"]+monitor["span_ms"]/1000
    background_start = background_end-frames[-1]["at_ms"]/1000
    observe_epoch = document["model_texture_observation_epoch_s"]
    nearest = min(hardware["samples"], key=lambda sample: abs(sample["epoch_s"]-observe_epoch))
    tasks = document["map_profile"]["asset_admission_details"]["tasks"]
    core = document["map_profile"]["asset_admission"]
    deferred = document["entry_deferred_profile"]
    intervals = [(stage[stamp], stage["reserved_bytes"]*sign) for task in tasks.values() for stage in task["stages"] for stamp, sign in (("dispatched_us", 1), ("joined_us", -1))]
    peak = active = 0
    for _, amount in sorted(intervals, key=lambda item: (item[0], item[1])):
        active += amount
        peak = max(peak, active)
    probe = document["physics_probe"]
    series = [probe["baseline"]]+[candidate[phase] for candidate in probe["candidates"] for phase in ("before", "without", "after")]
    query_results = [{"camera_fractions": value["camera_fractions"], "character_collided": value["character_collided"]} for value in series]
    identities = [{key: candidate.get(key) for key in ("uuid", "shape_count", "enabled_shape_count", "shape_types", "bounds", "layer", "layer_restored")} for candidate in probe["candidates"]]
    observation = document["model_texture_observation"]
    runs.append({
        "name": name, "variant": "on" if document["model_texture_sharing"] else "off",
        "report": str(ROOT / (name+".json")), "receipt": receipts[name],
        "configuration_except_sharing": {key: document.get(key) for key in CONFIG},
        "entry_ms": document["entry_ms"], "core_ms": document["entry_core_ready_ms"],
        "post_core_ms": document["entry_ms"]-document["entry_core_ready_ms"],
        "initial_model_wall_ms": document["map_profile"]["asset_parse_wall_us"]/1000,
        "entry_hardware": hardware_span(hardware, document["entry_epoch_s"], document["entry_end_epoch_s"]),
        "background_hardware_approximate": hardware_span(hardware, background_start, background_end),
        "background_window": {"start_epoch_s": background_start, "end_epoch_s": background_end,
                              "duration_ms": frames[-1]["at_ms"],
                              "method": "Monitor finish epoch minus final runtime row.at_ms; small profiler-restoration bookend overhead is not separately persisted. Physics/texture observation/avatar hiding/screenshot follow monitor.finish and are excluded."},
        "background_monitor_ms": monitor["phase_frame_percentiles_ms"]["playable_background"],
        "background_interrow_threshold_counts": {str(threshold): sum(value > threshold for value in frame_deltas) for threshold in (50, 100, 200)},
        "texture_observation": observation, "texture_observation_epoch_s": observe_epoch,
        "texture_observation_after_entry_s": observe_epoch-document["entry_end_epoch_s"],
        "texture_observation_after_monitor_s": observe_epoch-background_end,
        "texture_observation_scope": "Map-root StandardMaterial3D objects after entry, ten-second monitor, physical isolation, author checks, and any configured route; this is not entry VRAM or an all-map resident count. RS memory includes the whole process. No pixel readback occurs in this observation.",
        "texture_unstamped_or_unrecognized_objects": observation["texture_objects"]-observation["stamped_pixel_keys"]-observation["duplicate_stamped_objects"],
        "nearest_hardware_sample_to_texture_observation": {"offset_ms": (nearest["epoch_s"]-observe_epoch)*1000,
                                                            "rss_bytes": nearest["rss_bytes"], "private_bytes": nearest["private_bytes"],
                                                            "scope": "One nearest owned-process sample, not an instantaneous peak nor exact RS observation."},
        "physics": {"ok": probe["ok"], "all_series_ok": all(value["ok"] for value in series),
                    "candidate_count": probe["candidate_count"], "candidate_identities": identities,
                    "samples": probe["samples"], "warmup": probe["warmup"],
                    "measured_camera_calls": sum(len(value["camera"]["samples_us"]) for value in series),
                    "measured_character_calls": sum(len(value["character"]["samples_us"]) for value in series),
                    "restoration": probe["restoration"], "all_series_query_results": query_results,
                    "entry_body_count": document["collision_bodies"], "probe_resident_body_count": probe["resident_body_count"]},
        "budget": {"core": core, "entry_deferred": deferred["admission"], "initial_replayed_peak_bytes": peak,
                   "all_9_fixed_native_exact_bound": len(tasks)==9 and all(task["memory"]["policy"]=="fixed_native_product_then_separately_admitted_raw" and task["compiled"] and len(task["stages"])==1 and task["stages"][0]["stage"]=="compiled_read" and task["stages"][0]["reserved_bytes"]==task["memory"]["native_bound_bytes"]==task["retained_charge_bytes"] for task in tasks.values()),
                   "replayed_peak_matches": peak==core["peak_inflight_estimate_bytes"],
                   "core_peak_within_cap": peak<=core["inflight_budget_bytes"],
                   "core_ledger_returned_zero": core["inflight_jobs_at_return"]==core["inflight_reserved_at_return"]==0,
                   "deferred_all_fixed_native": deferred["models"]==deferred["compiled_hits"]==deferred["fixed_native_jobs"],
                   "deferred_peak_within_cap": deferred["admission"]["peak_bytes"]<=deferred["admission"]["byte_limit"]},
        "acceptance": {"failures": document["failures"], "trace_dropped": monitor["trace"]["dropped"],
                       "reference_index_hit": document["map_profile"]["reference_index_hit"],
                       "terrain_cache_hit": document["map_profile"]["terrain_context_cache_hit"],
                       "raw_fallbacks": document["map_profile"]["asset_fallback_count"],
                       "authored_records": document["authored_record_count"],
                       "avatar_hidden_after_measurement": document["screenshot_avatar_hidden"],
                       "early_entry_enabled": document["entry_readiness_shadow"]["early_entry_enabled"],
                       "gate_mode": document["entry_readiness_shadow"]["mode"]}})

groups = {kind: [row for row in runs if row["variant"]==kind] for kind in ("off", "on")}
comparison = {key: delta(*(mean(row[key] for row in groups[kind]) for kind in groups)) for key in ("entry_ms", "core_ms", "post_core_ms", "initial_model_wall_ms")}
comparison["texture_observation"] = {key: delta(*(mean(row["texture_observation"][key] for row in groups[kind]) for kind in groups)) for key in ("texture_objects", "stamped_pixel_keys", "duplicate_stamped_objects", "pixel_keys_with_multiple_objects", "live_pool_keys", "renderer_texture_memory_bytes")}
comparison["background_monitor_ms"] = {key: delta(*(mean(row["background_monitor_ms"][key] for row in groups[kind]) for kind in groups)) for key in ("50", "95", "99", "max", "count")}
comparison["background_interrow_threshold_counts"] = {key: delta(*(mean(row["background_interrow_threshold_counts"][key] for row in groups[kind]) for kind in groups)) for key in ("50", "100", "200")}
for field in ("entry_hardware", "background_hardware_approximate"):
    comparison[field] = {kind: hardware_group(rows, field) for kind, rows in groups.items()}
comparison["nearest_hardware_sample_to_texture_observation"] = {key: delta(*(mean(row["nearest_hardware_sample_to_texture_observation"][key] for row in groups[kind]) for kind in groups)) for key in ("rss_bytes", "private_bytes")}
result = {
    "scope": "Four completed game sharing v2 runs, same preferred resources/source/native generation and corrected admission code, sharing flag only. Read-only JSON/log analysis; no engine or source hashes.",
    "code_identity": read_json(ROOT / "game_sharing_v2_code_identity.json"), "sample_order": NAMES,
    "same_configuration_except_sharing": all(row["configuration_except_sharing"]==runs[0]["configuration_except_sharing"] for row in runs),
    "configuration_differences": {key: [row["configuration_except_sharing"][key] for row in runs] for key in CONFIG if any(row["configuration_except_sharing"][key]!=runs[0]["configuration_except_sharing"][key] for row in runs)},
    "same_physics_identities": all(row["physics"]["candidate_identities"]==runs[0]["physics"]["candidate_identities"] for row in runs),
    "same_all_physics_query_results": all(row["physics"]["all_series_query_results"]==runs[0]["physics"]["all_series_query_results"] for row in runs),
    "all_physics_restored": all(all(row["physics"]["restoration"].values()) for row in runs),
    "runs": runs, "comparison": comparison,
    "activation_recommendation": {"blocking_issue_observed": False, "enable_requested_by_user": True,
        "recommendation": "Proceed with controlled default-on source change, regenerate all 32 fixed native products and footprints, then complete formal-map game/editor/transfer/visual acceptance. This ABBA supports actual texture memory reduction and local collision correctness; it does not establish a load-speed win or cover the changed compiled-generator identity.",
        "G1_G2_defaults_remain_off": True},
    "conclusions": [
        "Entry off 17.648/16.601s versus on 17.972/16.906s: means 17.124784 -> 17.439169s (+0.314385s, +1.84%). Each arm varies by about 1.05s; no reliable speed benefit or precise small regression is established. Preserve both slower on samples and baseline drift in reporting.",
        "Actual game sharing is repeatable: the same 60 stamped identities remain, 13 duplicated keys/24 duplicate objects fall to zero, and reachable texture objects drop 127 -> 103 with 43 unstamped/unrecognized objects unchanged. The weak sharing pool has 60 live keys on, zero off.",
        "Renderer texture-memory off is 2,786,324,736 B in both runs; on is 2,316,562,688/2,333,339,904 B, saving 448/432 MiB (mean 440 MiB, ~16.56%). Observation is 24.0-24.8s after entry, after monitor and physics diagnostics and before avatar hiding/screenshot. This is a whole-process renderer allocation counter at the later scene state, not entry GPU VRAM, and should not be added to RSS/private savings.",
        "Entry RSS mean sampled peak rises 3,386,836,992 -> 3,717,189,632 B (~330MB/+9.75%), while private peak stays nearly flat 6,222,721,024 -> 6,213,457,920 B. Late sharing does not prevent initial allocations. Do not claim that all entry memory metrics improve; the repeatable gain is texture residency at the recorded observation and the already measured full-editor residency.",
        "Ten-second background phase has no established frame-time improvement: both arms have 0 intervals >200ms; off >100ms counts 4/4 versus on 3/8. B2 is noisier. Use authoritative monitor phase percentiles in the table; threshold counts are runtime interrow intervals and exclude the first transition frame. Physics, descriptor observation, avatar hiding and screenshot are outside these timed frames.",
        "All four runs finish exit0/failures0 with the same six physical candidate identities and exact before/without/after camera fractions and character collision results; 133 camera and 133 character measured calls per run, seven samples/two warmups, all restoration flags true. This is a local collision probe, not a replacement for a real pending-destination transfer with sharing default on.",
        "Initial preparation keeps nine source-bound fixed-native tasks each, reconstructed initial ledger peaks matching recorded values below 4GiB, with zero active credit at core return. Deferred native preparation stays within its recorded byte limit. These preparation caps exclude separately retained/published allocations and are not process memory caps.",
        "No new blocking functional issue is visible, and user authorization favors the proven texture memory benefit. Controlled default activation is reasonable after rebuilding and verifying changed-generation native products and formal-map transfer/editor/game paths. Keep G1/G2 off. All four game processes retain the known one-ObjectDB-instance exit warning; this evidence does not prove leak-free exit."
    ],
    "limits": ["N=2 per arm, warm fixture/debug binary; no cold-load or statistical time claim.",
               "Texture descriptors cover reachable map-root StandardMaterial3D slots, including mesh originals/overrides/next_pass; arbitrary shader uniforms and unloaded models are outside scope.",
               "No image readback in the observation; visual/material fidelity remains covered by separate GPU review and pending production-generation acceptance.",
               "CPU uses exact entry epochs and interval-weighted samples. RSS/private use endpoint maxima and can straddle a boundary by a sampling interval; GPU engine types are separate, not summed.",
               "Current generator used a false default with runtime flag overrides. Flipping the source default changes generator identity and requires explicit rebuild/revalidation."]}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "same_configuration": result["same_configuration_except_sharing"],
                  "same_physics": result["same_all_physics_query_results"], "comparison": comparison,
                  "blocking": result["activation_recommendation"]["blocking_issue_observed"]}, ensure_ascii=False, indent=2))
