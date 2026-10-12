"""Summarize existing acceptance receipts; never hash assets or run engines."""
import json
from datetime import datetime, timezone
from pathlib import Path

from analyze_results import hardware_span, read_json

HERE = Path(__file__).resolve().parent
RUNTIME = Path("D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011")


def source(name):
    return str(HERE / name)


def write(name, value):
    (HERE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


transfer = read_json(RUNTIME / "transfer_final.json")
transfer_log = (RUNTIME / "transfer_final.log").read_text(encoding="utf-8", errors="replace").splitlines()
passes = [line for line in transfer_log if line.startswith("PASS ")]
warnings = [line for line in transfer_log if "WARNING:" in line]
readiness = transfer["target_readiness"]
surface = transfer["destination_surface"]
queue = transfer["queue"]
stages = transfer["stages"]
stage_spans = [{"stage": stage["stage"], "start_ms": stage["at_ms"],
                "until_next_stage_ms": (stages[index + 1]["at_ms"] if index + 1 < len(stages) else transfer["transfer_ms"]) - stage["at_ms"]}
               for index, stage in enumerate(stages)]
transfer_analysis = {
    "source_report": str(RUNTIME / "transfer_final.json"), "source_log": str(RUNTIME / "transfer_final.log"),
    "pass_count": len(passes), "failures": transfer["failures"], "checks": passes,
    "warnings": warnings, "variant": {"collision_geometry": transfer["collision_geometry"], "model_texture_sharing": transfer["model_texture_sharing"]},
    "map": transfer["map"], "map_sha": transfer["map_sha"], "formal_sha_at_test": transfer["formal_sha"],
    "origin": transfer["origin"], "destination": transfer["destination"],
    "entry_ms": transfer["entry_ms"], "transfer_ms": transfer["transfer_ms"],
    "height_query_ms_outside_entry_and_transfer": transfer["height_query_ms"], "height_query_phase": transfer["height_query_phase"],
    "cover_capture_ms_included_in_transfer": transfer["cover_capture_ms"], "stage_intervals": stage_spans,
    "target_not_prepared_before_transfer": {
        "bridge_pending": transfer["destination_bridge_pending"], "bridge_published": transfer["destination_bridge_published"],
        "query_did_not_change_runtime_cache": transfer["destination_query_cache_unchanged"],
        "verified_height_source": surface["source"], "uuid": surface["uuid"], "resource": surface["resource"],
        "collision_surface_id": surface["surface_id"], "base_collision_faces": surface["base_collision_faces"],
        "surface_y": surface["y"], "record_pose": surface["record_pose"]},
    "handoff": transfer["loading_profile"],
    "target_readiness": {key: value for key, value in readiness.items() if key != "pending_diagnostic"},
    "background_diagnostic_pending_count": len(readiness["pending_diagnostic"]),
    "readiness_scope": "Existing local-transfer EntryPlan safety clip. Zero required/unsupported dependencies; distant ordinary pending instances are not a full-map readiness requirement. Inspection preserved the demand set.",
    "worker_capacity": {key: transfer[key] for key in ("deferred_workers", "deferred_workers_observed", "deferred_workers_mode", "deferred_workers_override", "deferred_workers_interactive_before", "deferred_workers_interactive_after")},
    "post_transfer_queue": {key: value for key, value in queue.items() if key != "profile"},
    "ledger": queue["profile"]["admission"],
    "ledger_checks": {"peak_within_cap": queue["profile"]["admission"]["peak_bytes"] <= queue["profile"]["admission"]["byte_limit"],
                      "zero_current_credit": queue["profile"]["admission"]["reserved_bytes"] == queue["profile"]["admission"]["jobs"] == queue["profile"]["admission"]["active_workers"] == 0},
    "hardware_transfer": hardware_span(read_json(RUNTIME / "transfer_final.hardware.json"), transfer["transfer_epoch_s"], transfer["transfer_end_epoch_s"]),
    "screenshots": {"cover": transfer["cover_image"], "destination": transfer["final_image"], "avatar_hidden": transfer["screenshot_avatar_hidden"]},
    "conclusions": [
        "23 PASS / 0 FAIL. Destination was pending and unpublished; a CPU-only verified authored rmres collision query resolved bridge stone_e_0be972769041dbc9 height without warming its runtime geometry. This corrects the old terrain-under-bridge oracle error.",
        "Real same-map transfer committed, cover preceded heavy work and remained with input/gravity frozen, no premature target placement, target rendering/radar ready before cover retirement, and input restored at the authored height. Target bridge has 78 shapes and the installed synchronized body is hit by the landing ray at y~0.897166m.",
        "Exact safety scope has pending_required=[] and unsupported_required=[], ready collision receipt and matching bridge rendering/spec/group. 729 ordinary background instances remain pending in the diagnostic scope without widening the safety contract; no test-triggered ensure_geometry demand was injected.",
        "Transfer takes 10.820356s including 42.165ms cover-image capture. CPU author-height query 547.686ms occurs before game entry and is not counted in transfer. Initial entry is 13.048826s from a different origin (-35,0.925,1.4), so it must not be compared to the problem-point resource ABBA.",
        "Covered worker capacity reaches six and restores two interactively. Ledger peak 8,477,331,024 B is within its 8,510,964,736 B cap and current credit is zero in the recorded queue; no path/instance errors. The profile's historical worker_limit=6 differs from the restored live queue worker_limit=2 and is not an un-restored capacity failure.",
        "Exit emits a ten-ObjectDB-instance leak warning. Successful transfer/zero queue credit does not establish leak-free process exit. Map SHA preservation is an assertion from the test report; this read-only summary does not repeat its large hashes."
    ]
}
write("transfer_final_analysis.json", transfer_analysis)

game = read_json(HERE / "resources_game_v2_analysis.json")
editor = read_json(HERE / "editor_resources_analysis.json")
picking = read_json(HERE / "picking_v2_analysis.json")
collision = read_json(HERE / "collision_v2_analysis.json")
sharing = read_json(HERE / "sharing_v2_analysis.json")
game_sharing = read_json(HERE / "game_sharing_v2_analysis.json")
conservation = read_json(HERE / "source_compare_20261011_225458.json")
save = read_json(RUNTIME / "joint_candidate_save.json")
publication_candidates = [RUNTIME / "publish_preferred_v2_receipt.json", RUNTIME / "publish_preferred_receipt.json"]
publication_path = next((path for path in publication_candidates if path.exists()), publication_candidates[0])
publication = read_json(publication_path) if publication_path.exists() else {}
publication_history = []
for path in reversed(publication_candidates):
    if path.exists():
        receipt = read_json(path)
        publication_history.append({"report": str(path), "ok": receipt.get("ok", False),
                                    "map_published": receipt.get("map_published", False),
                                    "failures": receipt.get("failures", []), "import_count": len(receipt.get("imports", []))})
compiled = read_json(RUNTIME / "compile_published_shared.json")
index = read_json(RUNTIME / "published_dependency_index.json")
published_game = read_json(RUNTIME / "published_game_default.json")
published_transfer = read_json(RUNTIME / "published_transfer_default.json")
published_catalog = read_json(RUNTIME / "joint_published_catalog.json")
postverify = read_json(RUNTIME / "postpublish_verify_final.json")
model_review_path = HERE / "model_reviews_1791732780325528700/index.json"
model_review = read_json(model_review_path)
memory_pages = read_json(HERE / "published_memory_pages_analysis.json")
def logged_checks(name):
    lines = (RUNTIME / (name+".log")).read_text(encoding="utf-8", errors="replace").splitlines()
    return {"pass_count": sum(line.startswith("PASS ") for line in lines),
            "warnings": [line for line in lines if "WARNING:" in line]}
assert publication["ok"] and publication["map_published"] and not publication["failures"]
assert len(compiled["models"]) == 32 and all(row["ok"] and row["footprint"]["ok"] for row in compiled["models"])
assert compiled["source_unchanged"] and not compiled["failures"] and not compiled["footprints_failed"]
assert index["ok"] and postverify["passed"] and not postverify["failures"]
assert published_game["failures"] == published_transfer["failures"] == published_catalog["failures"] == 0
assert all(row["ok"] for row in published_catalog["checks"])
assert all(d["model_texture_sharing"] for d in (published_game, published_transfer, published_catalog))
assert len(model_review["models"]) == 11 and all(all(value == "通过" for value in row["statuses"].values()) for row in model_review["models"])
assert memory_pages["recommendation"]["retain_default_model_texture_sharing"]
summary = {
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "scope": "Read-only rollup of completed joint acceptance, formal publication and postpublication evidence; no new model/map/source hashes. Historical benchmark arms and timestamps remain separate from the rebuilt published generation and final memory pair.",
    "selected_release": {"asset_choice": "preferred", "model_types": 11, "affected_instances": 59,
                         "formal_map": "D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf",
                         "validation_map": transfer["map"], "validation_map_sha": transfer["map_sha"],
                         "excluded": "Seven metadata overlays/combined 14-type variant remain experimental; G1/G2 stay default off.",
                         "default_flags_at_completed_benchmarks": {"picking_lod": False, "collision_geometry": False, "model_texture_sharing": False},
                         "authorized_next_configuration": {"picking_lod": False, "collision_geometry": False,
                                                           "model_texture_sharing": True, "status": "enabled_rebuilt_native_and_postpublication_acceptance_complete"}},
    "resources_game_final_v2": {"analysis": source("resources_game_v2_analysis.json"), "receipt": str(RUNTIME / "game_resources_v2_run_receipts.json"),
                                "entry_ms": game["comparison"]["entry_ms"], "model_wall_ms": game["comparison"]["core_timings_ms"]["asset_parse_wall_us"],
                                "all_9_native_bound_each_run": all(row["budget_acceptance"]["fixed_native_source_bound_tasks"] == 9 for row in game["runs"]),
                                "all_initial_replayed_peaks_match": all(row["budget_acceptance"]["replayed_peak_equals_actual_ledger_peak"] for row in game["runs"]),
                                "note": "Use this corrected-budget 5.46% observation, not the historical v1 11.65% experiment."},
    "resources_editor": {"analysis": source("editor_resources_analysis.json"), "receipt": str(RUNTIME / "resources_run_receipts.json"),
                         "load_ms": editor["comparison"]["metrics"]["load_ms"],
                         "asset_wait_ms": editor["comparison"]["metrics"]["asset_wait_total_ms"],
                         "note": "Editor already used correct native-bound admission. Art-only warm-load mean improves 13.71% with 5.56s baseline drift; no claim that all observed time is causal."},
    "G1_picking": {"analysis": source("picking_v2_analysis.json"), "load_ms": picking["comparison"]["metrics"]["load_ms"],
                   "geometry_counts": picking["comparison"]["geometry_counts"], "enable_default": False,
                   "reason": "1284 pick bodies skipped, but full load +3.31%; investigate record/policy lookup and unaccounted add_bodies time separately."},
    "G2_collision": {"analysis": source("collision_v2_analysis.json"), "entry_ms": collision["comparison"]["entry_ms"],
                     "enable_default": False, "reason": collision["recommendation"]["reason"]},
    "G3_sharing": {"analysis": source("sharing_v2_analysis.json"), "load_ms": sharing["comparison"]["load_ms"],
                   "renderer_texture_bytes": sharing["comparison"]["texture_observation"]["renderer_texture_memory_bytes"],
                   "duplicate_texture_objects": sharing["comparison"]["texture_observation"]["duplicate_stamped_objects"],
                   "enable_default_authorized": True, "activation_status": "enabled_and_postpublication_validated",
                   "reason": "User authorized significant gains without established adverse impact. Editor renderer-accounted reduction is944MiB; the published-generation game pair retains431.609MiB less final renderer texture memory and251.410MiB less private commit, with6.137MiB higher working set. The old sustained256MiB RSS increase is not reproduced but is not causally diagnosed/fixed. All32 current-generator native products and postpublication functional checks pass. No reliable load-time win is claimed.",
                   "game_analysis": source("game_sharing_v2_analysis.json"), "game_entry_ms": game_sharing["comparison"]["entry_ms"],
                   "game_final_texture_bytes": game_sharing["comparison"]["texture_observation"]["renderer_texture_memory_bytes"],
                   "game_activation_recommendation": game_sharing["activation_recommendation"],
                   "current_activation_evidence": source("published_memory_pages_analysis.json"),
                   "current_activation_recommendation": memory_pages["recommendation"],
                   "next_workstream": sharing.get("next_workstream")},
    "actual_loading_transfer": {"analysis": source("transfer_final_analysis.json"), "report": str(RUNTIME / "transfer_final.json"),
                                "pass_count": len(passes), "failures": transfer["failures"], "transfer_ms": transfer["transfer_ms"],
                                "cover_capture_ms_included": transfer["cover_capture_ms"], "pending_destination_tested": transfer["destination_bridge_pending"],
                                "committed": transfer["loading_profile"]["committed"], "real_bridge_collision_ray": readiness["bridge_ray_hits_body"],
                                "required_pending_count": len(readiness["pending_required"]), "unsupported_required_count": len(readiness["unsupported_required"]),
                                "note": "Production experimental flags off; entry13.049s is a different spawn, not comparable to problem-point entry."},
    "combined_save_reopen_functionality": {"report": str(RUNTIME / "joint_candidate_save.json"), "stage": save["stage"],
                                          "check_count": len(save["checks"]), "failures": save["failures"],
                                          "operations": len(save["operations"]), "saves": len(save["saves"]), "loads": len(save["loads"]),
                                          "final_records": save["final_records"], "final_houses": save["final_houses"],
                                          "picking_lod": save["picking_lod"], "model_texture_sharing": save["model_texture_sharing"],
                                          "note": "Combined candidate real HTTP/Save As/reopen correctness fixture; not formal preferred-only publication or an extra performance sample."},
    "prepublication_conservation": {"report": source("source_compare_20261011_225458.json"), "created_utc": conservation["created_utc"],
                                    "passed": conservation["passed"], "file_count": conservation["file_count"],
                                    "changed_files": len(conservation["changed_files"]), "invalid_files": len(conservation["invalid_current_files"]),
                                    "inventory_changes": conservation["inventory_changes"],
                                    "compiled_dependency_fingerprint_unchanged": conservation["compiled_source_fingerprint"] == conservation["previous_compiled_source_fingerprint"],
                                    "note": "7126-file full conservation is evidence from the existing completed harness, before authorized promotion; not rerun here."},
    "formal_publication_receipt_snapshot": {"report": str(publication_path), "ok": publication.get("ok", False),
                                            "map_published": publication.get("map_published", False), "failures": publication.get("failures", []),
                                            "import_count": len(publication.get("imports", [])),
                                            "status": "published_and_postpublication_validated" if publication.get("ok") and publication.get("map_published") else "not_confirmed_by_current_receipt",
                                            "published_sha256": publication["published_sha256"],
                                            "original_postpublish_requirements": publication.get("postpublish_required", []),
                                            "requirements_completed_by": [str(RUNTIME / name) for name in ("published_dependency_index.json", "published_game_default.json", "published_transfer_default.json", "joint_published_catalog.json", "postpublish_verify_final.json")],
                                            "api_limit": publication["ui_mcp_batch_relink"]},
    "formal_publication_receipt_history": publication_history,
    "postpublication_acceptance": {
        "compiled_products": {"report": str(RUNTIME / "compile_published_shared.json"), "model_count": len(compiled["models"]),
                              "all_native_and_footprints_valid": True, "built": compiled["built"], "reused": compiled["reused"],
                              "footprints_built": compiled["footprints_built"], "footprints_reused": compiled["footprints_reused"],
                              "failures": compiled["failures"], "footprints_failed": compiled["footprints_failed"],
                              "source_unchanged": compiled["source_unchanged"], "source_sha": compiled["source_sha"],
                              "note": "All32 use the current generator;21 rebuilt here and11 already built during the same-generation preferred publication were validated/reused. Do not call this32 newly rewritten products."},
        "formal_dependency_index": {"report": str(RUNTIME / "published_dependency_index.json"), "ok": index["ok"]},
        "game": {"report": str(RUNTIME / "published_game_default.json"), "failures": published_game["failures"],
                 "map": published_game["map"], "map_sha": published_game["map_sha"], "entry_ms": published_game["entry_ms"],
                 "model_texture_sharing": published_game["model_texture_sharing"], "collision_geometry": published_game["collision_geometry"],
                 "cache_candidate": published_game["cache_candidate"], "cache_existed": published_game["cache_existed"],
                 "reference_index_hit": published_game["map_profile"]["reference_index_hit"],
                 "reference_index_rebuilt_before_models": published_game["map_profile"]["reference_index_rebuilt_before_models"],
                 "terrain_context_cache_hit": published_game["map_profile"]["terrain_context_cache_hit"],
                 **logged_checks("published_game_default"),
                 "note": "37.066s is the first new temporary published-checkpoint path: selected cooked cache absent, reference index missing/rebuilt, terrain context cold. This is a correctness smoke, not a warm-ABBA regression or warm-load performance result."},
        "transfer": {"report": str(RUNTIME / "published_transfer_default.json"), **logged_checks("published_transfer_default"),
                     "failures": published_transfer["failures"], "entry_ms": published_transfer["entry_ms"], "transfer_ms": published_transfer["transfer_ms"],
                     "cover_capture_ms_included": published_transfer["cover_capture_ms"], "committed": published_transfer["loading_profile"]["committed"],
                     "destination_was_pending": published_transfer["destination_bridge_pending"],
                     "destination_was_published": published_transfer["destination_bridge_published"],
                     "height_query_did_not_warm_geometry": published_transfer["destination_query_cache_unchanged"],
                     "target_readiness": {k:v for k,v in published_transfer["target_readiness"].items() if k not in ("pending_diagnostic", "collision_states")},
                     "model_texture_sharing": published_transfer["model_texture_sharing"], "collision_geometry": published_transfer["collision_geometry"],
                     "note": "Real pending-destination loading transfer with current defaults. Origin differs from problem-point resource benchmarks;13.625s entry must not be compared to them."},
        "editor_catalog": {"report": str(RUNTIME / "joint_published_catalog.json"), "stage": published_catalog["stage"],
                           "failures": published_catalog["failures"], "check_count": len(published_catalog["checks"]), "all_checks_passed": True,
                           "native_hits": published_catalog["load_result"]["timings"]["asset_lookahead"]["compiled_hits"],
                           "native_candidates": published_catalog["load_result"]["timings"]["asset_lookahead"]["native_candidates"],
                           "catalog_model_count": len(published_catalog["catalog_audit"]),
                           "thumbnail_requested": published_catalog["thumbnail_preparation"]["requested"],
                           "new_instance_save": published_catalog["catalog_small_save"]["result"]["ok"],
                           "final_record_count": published_catalog["final_record_count"], "final_house_count": published_catalog["final_house_count"],
                           "model_texture_sharing": published_catalog["model_texture_sharing"], "picking_lod": published_catalog["picking_lod"]},
        "source_conservation": {"report": str(RUNTIME / "postpublish_verify_final.json"), "passed": postverify["passed"],
                                "file_count": postverify["file_count"], "failures": postverify["failures"],
                                "changed_paths": [row if isinstance(row, str) else row["path"] for row in postverify["changed_files"]],
                                "allowed_change_count": len(postverify["allowed_changes"]), "new_target_count": len(postverify["new_targets"]),
                                "definition_count": len(postverify["new_definitions"]),
                                "note": "7126 existing rows checked; exactly the authorized map/catalog/default-source changes. Original GLBs and1762 definitions preserved. This summary reuses the completed receipt, not fresh hashes."},
        "per_model_reviews": {"report": str(model_review_path), "model_count": len(model_review["models"]),
                              "status_counts": model_review["status_counts"], "all_four_categories_passed": True,
                              "note": "Source-bound11-model resource/visual/runtime/game-editor review receipts; visualization comparisons are existing verified evidence, not new screenshots by this summary."},
        "memory_pair": {"analysis": source("published_memory_pages_analysis.json"), "recommendation": memory_pages["recommendation"],
                        "comparison": memory_pages["comparison"]}},
    "open_limits": ["Offline exact-reference promotion is complete; a generic UI/3D-MCP batch relink API is not implemented and is not implied by the offline tool or HTTP catalog/save acceptance.",
                    "Game entry/collision runs each emit one ObjectDB leak warning and transfer emits ten; performance and functional passes are not zero-leak acceptance.",
                    "Only warm debug/editor-binary measurements; low CPU/GPU utilization remains. Preserve measured resource benefits without adding inclusive timers or mixing old/new budget arms.",
                    "G1/G2 remain default off pending diagnosis. Texture sharing is enabled and accepted on the rebuilt published generation; historical default-off results remain labeled as such.",
                    "Current memory evidence is one bounded OFF/ON pair: old sustained+256MiB RSS was not reproduced, not diagnosed as fixed or harmless. The new~6MiB RSS difference and unresolved historical behavior remain monitored; renderer counters are not entry VRAM."]
}
write("joint_acceptance_summary.json", summary)
print(json.dumps({"transfer_analysis": source("transfer_final_analysis.json"), "summary": source("joint_acceptance_summary.json"),
                  "transfer_pass": len(passes), "transfer_failures": transfer["failures"],
                  "publication_snapshot": summary["formal_publication_receipt_snapshot"]}, ensure_ascii=False, indent=2))
