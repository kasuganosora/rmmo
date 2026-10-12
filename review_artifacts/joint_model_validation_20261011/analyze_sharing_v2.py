"""Read completed editor sharing G3 ABBA; no engine or asset hashing."""
import json
from collections import defaultdict
from pathlib import Path
from statistics import mean

from analyze_results import hardware_span, read_json

ROOT = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")
OUT = Path(__file__).with_name("sharing_v2_analysis.json")
NAMES = ["editor_sharing_off_a1_v2", "editor_sharing_on_b1_v2", "editor_sharing_on_b2_v2", "editor_sharing_off_a2_v2"]
FLAGS = ["checkpoint", "expected_sha256", "formal_sha256", "native_model_footprints", "preparation_lanes", "model_residency", "picking_lod", "prefab_warm_workers"]
UNITS = ["asset_wait", "asset_prepare_main", "asset_parse_worker", "asset_prepare_release", "picking_capture", "picking_faces_prepare", "picking_faces_wait", "picking_shape", "picking_publish", "add_bodies"]


def delta(a, b):
    return {"off_mean": a, "on_mean": b, "difference": b - a, "change_percent": (b / a - 1) * 100 if a else None}


receipts = {row["name"]: row for row in read_json(ROOT / "sharing_v2_run_receipts.json")}
assert all(name in receipts and receipts[name]["exit_code"] == 0 for name in NAMES)
runs = []
for name in NAMES:
    document = read_json(ROOT / (name + ".json"))
    assert document["stage"] == "finished"
    hardware = read_json(ROOT / (name + ".hardware.json"))
    timings = document["load_result"]["timings"]
    trace = document["load_trace"]
    labels = defaultdict(lambda: {"count": 0, "inclusive_worker_wall_ms": 0.0})
    for event in trace["events"]:
        if event["label"].startswith("compiled."):
            labels[event["label"]]["count"] += 1
            labels[event["label"]]["inclusive_worker_wall_ms"] += event["duration_us"] / 1000
    after_samples = [sample for sample in hardware["samples"] if sample.get("epoch_s", 0) >= document["load_end_epoch_s"]]
    first_after = after_samples[0] if after_samples else {}
    observation = document["model_texture_observation"]
    prep = timings["preparation"]
    runs.append({
        "name": name, "variant": "on" if document["model_texture_sharing"] else "off",
        "report": str(ROOT / (name + ".json")), "hardware_report": str(ROOT / (name + ".hardware.json")),
        "run_receipt": receipts[name], "configuration_except_sharing": {key: document.get(key) for key in FLAGS},
        "model_texture_sharing": document["model_texture_sharing"], "load_ms": document["load_ms"],
        "load_start_epoch_s": document["load_start_epoch_s"], "load_end_epoch_s": document["load_end_epoch_s"],
        "texture_observation": observation,
        "derived_texture_counts": {
            "stamped_texture_objects": observation["stamped_pixel_keys"] + observation["duplicate_stamped_objects"],
            "unstamped_or_unrecognized_objects": observation["texture_objects"] - observation["stamped_pixel_keys"] - observation["duplicate_stamped_objects"]},
        "asset_lookahead": timings["asset_lookahead"],
        "preparation": {key: value for key, value in prep.items() if not isinstance(value, (list, dict))},
        "preparation_ledger": prep["ledger"],
        "budget_checks": {"two_worker_limit": prep["ledger"]["worker_limit"] == 2,
                          "peak_workers_within_limit": prep["ledger"]["peak_workers"] <= 2,
                          "peak_inflight_within_four": prep["peak_inflight"] <= 4,
                          "peak_bytes_within_4GiB": prep["ledger"]["peak_bytes"] <= prep["ledger"]["byte_limit"] == 4294967296,
                          "queue_fully_released": prep["ledger"]["jobs"] == prep["ledger"]["reserved_bytes"] == prep["ledger"]["active_workers"] == 0,
                          "all_native_hits": timings["asset_lookahead"]["native_candidates"] == timings["asset_lookahead"]["compiled_hits"] == timings["asset_lookahead"]["consumed"] == 32},
        "build_units": {key: timings["build"]["units"][key] for key in UNITS},
        "validation_ms": timings["validate_ms"], "metadata_ready_ms": timings["metadata_ready_ms"],
        "query_ready_ms": timings["query_ready_ms"], "compiled_trace": dict(labels),
        "hardware_load": hardware_span(hardware, document["load_start_epoch_s"], document["load_end_epoch_s"]),
        "first_hardware_sample_after_load": {"after_load_ms": (first_after.get("epoch_s", document["load_end_epoch_s"]) - document["load_end_epoch_s"]) * 1000,
                                            "rss_bytes": first_after.get("rss_bytes"), "private_bytes": first_after.get("private_bytes"),
                                            "scope": "Nearest later sampler endpoint, not the exact post-settle texture-observation timestamp. Later editing workload is not pooled into load hardware metrics."},
        "acceptance": {"failures": document["failures"], "load_ok": document["load_result"]["ok"],
                       "final_record_count": document["final_record_count"], "final_house_count": document["final_house_count"],
                       "trace_dropped": trace["dropped"], "full_rebuilds": document["full_rebuilds"],
                       "baseline_full_rebuilds": document["baseline_full_rebuilds"]}
    })

groups = {kind: [row for row in runs if row["variant"] == kind] for kind in ("off", "on")}
comparison = {}
for key in ("load_ms", "validation_ms", "metadata_ready_ms", "query_ready_ms"):
    comparison[key] = delta(*(mean(row[key] for row in groups[kind]) for kind in groups))
comparison["texture_observation"] = {key: delta(*(mean(row["texture_observation"][key] for row in groups[kind]) for kind in groups)) for key in ("texture_objects", "stamped_pixel_keys", "pixel_keys_with_multiple_objects", "duplicate_stamped_objects", "renderer_texture_memory_bytes", "live_pool_keys")}
comparison["units_total_ms"] = {key: delta(*(mean(row["build_units"][key]["total_ms"] for row in groups[kind]) for kind in groups)) for key in UNITS}
comparison["hardware_load"] = {}
for kind, members in groups.items():
    values = [row["hardware_load"] for row in members]
    comparison["hardware_load"][kind] = {
        "cpu_logical_equivalents_weighted": sum(value["cpu_logical_equivalents_mean"] * value["cpu_coverage_s"] for value in values) / sum(value["cpu_coverage_s"] for value in values),
        "cpu_seconds_mean": mean(value["cpu_logical_equivalents_mean"] * value["cpu_coverage_s"] for value in values),
        "main_thread_cpu_equivalents_weighted": sum(value["main_thread_cpu_equivalents_mean"] * value["cpu_coverage_s"] for value in values) / sum(value["cpu_coverage_s"] for value in values),
        "rss_peak_mean_bytes": mean(value["rss_peak_bytes"] for value in values),
        "private_peak_mean_bytes": mean(value["private_peak_bytes"] for value in values),
        "gpu_engine_mean_percent_weighted": {engine: sum(value["gpu_engine_mean_percent"][engine] * value["gpu_valid_coverage_s"][engine] for value in values) / sum(value["gpu_valid_coverage_s"][engine] for value in values) for engine in values[0]["gpu_engine_mean_percent"]}}
result = {
    "decision_superseded_by": {"status": "Later user authorization replaces this report's historical default-off release decision; measurements remain unchanged.",
                               "user_instruction": "Default-enable texture sharing after completing the game check.",
                               "game_analysis": str(OUT.with_name("game_sharing_v2_analysis.json")),
                               "current_decision": "Game sharing ABBA is complete with actual 432-448MiB renderer-texture savings and no observed functional blocker. Proceed with the authorized default-on change, rebuild all 32 native products for the new generator, and complete formal-map joint acceptance. No reliable load-time win is claimed."},
    "scope": "Read-only completed sharing v2 editor ABBA. Same preferred resource fixture and fixed budget code; only model_texture_sharing differs. No engine, GPU, import, large hashing or source edits.",
    "sample_order": NAMES, "code_identity": read_json(ROOT / "sharing_v2_code_identity.json"),
    "same_configuration_except_sharing": all(row["configuration_except_sharing"] == runs[0]["configuration_except_sharing"] for row in runs),
    "configuration_differences": {key: [row["configuration_except_sharing"][key] for row in runs] for key in FLAGS if any(row["configuration_except_sharing"][key] != runs[0]["configuration_except_sharing"][key] for row in runs)},
    "runs": runs, "comparison": comparison,
    "conclusions": [
        "Sharing actually occurs in both on runs: the same 67 stamped pixel identities remain, 14 keys previously having multiple live Texture objects become zero, and 53 duplicate objects disappear. Reachable StandardMaterial texture object count is 166 -> 113; stamped objects are 120 -> 67 while 46 unstamped/unrecognized objects remain independent. This is object-identity sharing, not removal of declared images or skipped visual materials.",
        "The post-load/post-derived-settle renderer texture-memory counter is deterministic across both samples: off 3,089,394,128 B, on 2,099,538,384 B; reduction 989,855,744 B (~944 MiB, -32.04%). This is strong evidence of renderer-accounted texture residency savings. It is a process-global renderer counter, not measured dedicated GPU VRAM, and its savings must not be added to process RSS/private as if those were independent allocations.",
        "Exact load-window sampled private-memory peak averages 7,694,305,280 -> 6,905,624,576 B (about -10.25%). RSS peak averages 4,257,241,088 -> 4,211,308,544 B (about -1.08%), much smaller. First hardware samples after load similarly show ~7.694GB -> ~6.896GB private memory, while RSS is around 4.20GB in both groups. Those samples are 47-609ms after load and are not the exact texture-observation timestamp.",
        "Load means 55.108728 -> 54.612043s differ by only -0.496685s (-0.90%). Off A1/A2 vary by 2.152665s, over four times the mean difference, and A2 is faster than either on sample. Therefore no reliable load-time win is established; this experiment validates memory/object reduction, not a speedup claim.",
        "The mechanism is late main-thread publication sharing. ModelTextureCache.apply rebinds matching immutable texture metadata, holds originals through setter submission, synchronizes before dropping retired originals, and uses weak references in a pool bounded at 256 keys (67 live here). It does not avoid earlier native payload/source verification, native deserialization or temporary allocation. The two variants still have 32/32 fixed-native hits and identical planned model reservation total 21,806,698,524 B.",
        "Late sharing adds visible publication overhead: asset_prepare_main totals ~99.392 -> 193.420ms. Model asset_wait is ~4.180 -> 4.571s and aggregate model worker wall ~17.465 -> 18.049s, with overlap/noise; none supports an early-loading-work reduction. No runtime image pixel readback is added by apply; keys are stamped offline from actual image bytes and the tested on path only inspects trusted metadata during rebind.",
        "All four final receipts have exit0, failures0 and no warnings/errors; editor load succeeds with 4,437 records and 61 houses. All use 32 native candidates/hits, no native retry, raw retry, preemption, start failure or ownership rejection, and retain two workers/four in-flight slots. Queue ledger peaks stay below 4GiB and return to zero. G1 picking and residency/lanes remain off, so their benefits are not mixed into this test.",
        "Keep the current default-off policy for this joint release decision as instructed; do not justify enabling it with the 0.9% timing difference. Preserve the strong, repeatable ~944MiB renderer-texture and ~789MB private-peak reduction as a separate memory-benefit result for a focused activation decision with the existing visual/lifetime tests. A future pre-deserialization shared dependency scheme would be a distinct optimization and needs its own budget/source-identity design."
    ],
    "next_workstream": {"subject": "Source-bound immutable model texture sharing activation",
               "already_proven": ["Full editor fixture eliminates 53 duplicate Texture objects across 14 pixel identities", "Renderer-accounted texture memory drops 989,855,744 bytes in both on observations"],
               "not_proven": ["Reliable editor load-time reduction", "Game-entry sharing ABBA and game working-set benefit", "Production activation under a changed compiled generator"],
               "required_before_default_change": ["Run separate same-code game-entry off/on ABBA and complete transfer/visual/lifetime checks", "ModelTextureCache.gd is a Compiled.generator dependency, so editing its default invalidates product generation identity; deliberately rebuild/reverify source-bound derived products and footprints rather than assuming these runtime-flag samples cover that changed generator", "Preserve current preferred-11 publication with G1/G2/G3 defaults off; do not couple this future activation to the current art promotion"]},
    "limits": ["N=2 per arm, warm full-town editor fixture; not a cold-load or statistically established time improvement.",
               "Texture observation traverses reachable StandardMaterial3D texture slots after load timing and derived-batch settling; it does not include arbitrary shader-uniform textures or independently hash GPU pixels.",
               "Renderer texture memory is process-global and distinct from sampled RSS/private; no direct dedicated/shared VRAM measurement is available here.",
               "Hardware uses exact reported load epochs. Later HTTP operations and post-load pixel readbacks in functionality checks are excluded from the load window.",
               "Compiled trace and build unit times are inclusive overlapping worker/parent wall time, not additive CPU time."]
}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"output": str(OUT), "same_configuration": result["same_configuration_except_sharing"], "load": comparison["load_ms"], "texture": comparison["texture_observation"], "hardware": comparison["hardware_load"], "units": comparison["units_total_ms"]}, ensure_ascii=False, indent=2))
