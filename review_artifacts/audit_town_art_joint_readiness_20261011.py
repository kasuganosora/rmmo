"""Read-only source/reference integrity audit; never imports assets or rebuilds caches."""
from __future__ import annotations

import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

REPO = Path("D:/code/rmmo")
RUNTIME = Path("D:/code/rmmo_runtime")
EVIDENCE = REPO / "review_artifacts/town_asset_size_audit_20261011"
ART = RUNTIME / "art_sources/town_asset_size_optimization_20261011"
OUTPUT = REPO / "review_artifacts/town_art_joint_readiness_audit_20261011.json"
MAP = RUNTIME / "maps/medieval_river_town/map.gltf"
CHECKPOINT = RUNTIME / "cache/world3d/bridge_lod_checkpoint_20261011_1791699698203797000/map.gltf"


def norm(value):
    return str(Path(str(value).replace("\\", "/"))).replace("\\", "/")


def key(value):
    return norm(value).casefold()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


hashes = {}


def digest(path):
    p = Path(norm(path))
    if key(p) not in hashes:
        if not p.is_file():
            hashes[key(p)] = {"path": norm(p), "exists": False}
        else:
            h = hashlib.sha256()
            size = 0
            with p.open("rb") as f:
                while chunk := f.read(1024 * 1024):
                    h.update(chunk)
                    size += len(chunk)
            hashes[key(p)] = {"path": norm(p), "exists": True, "bytes": size, "sha256": h.hexdigest()}
    return hashes[key(p)].copy()


def verify(path, expected_sha, expected_bytes=None):
    row = digest(path)
    row["expected_sha256"] = expected_sha
    row["sha_matches"] = row.get("sha256") == expected_sha
    if expected_bytes is not None:
        row["expected_bytes"] = expected_bytes
        row["length_matches"] = row.get("bytes") == expected_bytes
    return row


handoff = read(EVIDENCE / "candidate_handoff.json")
old = read(REPO / "review_artifacts/town_large_asset_art_handoff_20261011.json")
inventory = read(EVIDENCE / "inventory_report.json")
decoded = read(EVIDENCE / "inventory_map_definitions.json")
picking = read(EVIDENCE / "editor_picking_manifest.json")
map_check = verify(MAP, old["map_sha256"])
data = read(MAP)
extras = data["nodes"][0]["extras"]
formal = extras["rmmo_records"]
prior_records = {r["uuid"]: r for r in decoded["records"]}
definition_map = {r["uri"]: r for r in decoded["definitions"]}
refs = {}
record_mismatches = []
for r in formal:
    ref = r["rmmo_ref"]
    previous = prior_records.get(r["uuid"], {})
    if previous.get("uri") != ref["uri"] or previous.get("state") != r.get("rmmo_state", {}):
        record_mismatches.append(r["uuid"])
    refs[ref["uri"]] = ref
definition_checks = []
for uri, ref in refs.items():
    p = MAP.parent / uri
    result = verify(p, ref["sha256"], ref["length"])
    result.update(uri=uri, decoded_definition_present=uri in definition_map,
                  dependency_sha_matches=extras["rmmo_resource_dependencies"].get(uri) == ref["sha256"])
    definition_checks.append(result)

instances = defaultdict(set)
original_path_spelling = {}
for r in decoded["records"]:
    for p in r["paths"]:
        if p["path"].lower().endswith(".glb"):
            instances[key(p["path"])].add(r["uuid"])
            original_path_spelling[key(p["path"])] = norm(p["path"])

originals = []
inventory_rows = {key(r["path"]): r for r in inventory["rows"]}
for r in old["rows"]:
    actual = verify(r["path"], r["source_sha256"], r["source_bytes"])
    actual["instance_uuids"] = sorted(instances[key(r["path"])])
    actual["instance_count"] = len(actual["instance_uuids"])
    actual["inventory_instance_count_matches"] = actual["instance_count"] == inventory_rows[key(r["path"])]["instance_count"]
    cache = RUNTIME / "cache/world3d/compiled_assets_v1" / (hashlib.sha256(norm(r["path"]).encode()).hexdigest() + ".json")
    actual["native_index"] = norm(cache)
    if cache.exists():
        header = read(cache)
        actual["native_index_header_only"] = header
        actual["native_index_source_matches"] = header.get("source_sha") == actual.get("sha256")
    actual["native_payload_and_current_generator_validated"] = False
    originals.append(actual)

original_keys = {key(r["path"]) for r in old["rows"]}
additional = [dict(digest(original_path_spelling[k]), instance_uuids=sorted(v), instance_count=len(v))
              for k, v in instances.items() if k not in original_keys]


def candidate_row(r):
    row = {name: r.get(name) for name in ("label", "kind", "original", "original_sha256", "candidate", "candidate_sha256", "art_status", "integration_status", "published", "review", "shadows")}
    row["original_check"] = verify(r["original"], r["original_sha256"])
    row["candidate_check"] = verify(r["candidate"], r["candidate_sha256"])
    row["formal_original_instances"] = len(instances[key(r["original"])])
    row["formal_candidate_instances"] = len(instances.get(key(r["candidate"]), set()))
    row["source_bytes_saved"] = row["original_check"].get("bytes", 0) - row["candidate_check"].get("bytes", 0)
    row["reported_baseline_generator"] = r["baseline"]["compiled_generator"]
    row["reported_candidate_generator"] = r["optimized"]["compiled_generator"]
    return row


preferred = [candidate_row(r) for r in handoff["preferred"]]
fallbacks = [candidate_row(r) for r in handoff["exact_fallbacks"]]
preferred_by_candidate = {key(r["candidate"]): r for r in preferred}
all_candidates = {key(r["candidate"]): r for r in preferred + fallbacks}
preferred_by_original = {key(r["original"]): r for r in preferred}
picking_rows = []
for r in picking["rows"]:
    row = {name: r.get(name) for name in ("label", "path", "sha256", "candidate", "candidate_sha256", "status", "gpu_run", "published")}
    row["source_check"] = verify(r["path"], r["sha256"])
    if r.get("candidate"):
        row["candidate_check"] = verify(r["candidate"], r["candidate_sha256"])
        lineage = all_candidates.get(key(r["path"]))
        original = lineage["original"] if lineage else r["path"]
        row["formal_original"] = norm(original)
        row["formal_original_instances"] = len(instances[key(original)])
        row["formal_candidate_instances"] = len(instances.get(key(r["candidate"]), set()))
        selected = preferred_by_original.get(key(original))
        row["based_on_preferred_source"] = selected is not None and key(selected["candidate"]) == key(r["path"])
        row["preferred_combination_requires_rederive"] = selected is not None and not row["based_on_preferred_source"]
        row["preferred_candidate"] = selected["candidate"] if selected else None
    picking_rows.append(row)

copies = []
for filename, target in [("candidate_handoff.json", ART / "candidate_handoff.json"),
                         ("editor_picking_manifest.json", ART / "editor_picking/editor_picking_manifest.json")]:
    copies.append({"repo": digest(EVIDENCE / filename), "runtime": digest(target),
                   "parsed_equal": read(EVIDENCE / filename) == read(target)})

# Re-read the map, independent of memoized hashes, to detect a concurrent save.
with MAP.open("rb") as f:
    map_after = hashlib.file_digest(f, "sha256").hexdigest()
failed_files = [r for r in originals + definition_checks if not r.get("sha_matches") or r.get("length_matches") is False]
failed_candidates = [r["label"] for r in preferred + fallbacks
                     if not r["original_check"]["sha_matches"] or not r["candidate_check"]["sha_matches"]]
failed_picking = [r["label"] for r in picking_rows if not r["source_check"]["sha_matches"]
                  or (r.get("candidate") and not r["candidate_check"]["sha_matches"])]
result = {
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "scope": "Read-only fresh SHA and reference audit; no engine, imports, GPU, HTTP, native rebuild, formal writes or new visual approval.",
    "map": map_check, "map_sha_after": map_after, "map_unchanged_during_audit": map_check.get("sha256") == map_after,
    "baseline_checkpoint": verify(CHECKPOINT, old["map_sha256"]),
    "reference_binding": {
        "method": "Formal map SHA matches prior decoded inventory; all referenced rmres full file SHA+length rechecked; record UUID/uri/state aligned. External paths are from that prior decoder evidence, not a new Godot decode.",
        "record_count": len(formal), "previous_record_count": len(decoded["records"]),
        "record_mismatches": record_mismatches, "definition_count": len(definition_checks),
        "all_definition_sha_length_valid": not failed_files,
        "all_dependencies_match": all(r["dependency_sha_matches"] for r in definition_checks),
        "all_decoded_definitions_present": all(r["decoded_definition_present"] for r in definition_checks),
        "definition_total_bytes": sum(r.get("bytes", 0) for r in definition_checks),
    },
    "original_32": originals, "additional_formal_models": additional,
    "preferred": preferred, "exact_fallbacks": fallbacks, "editor_picking": picking_rows,
    "handoff_copies": copies,
    "summary": {
        "original_native_model_count": len(originals), "original_instances": sum(r["instance_count"] for r in originals),
        "formal_glb_paths": len(instances), "formal_glb_instances": sum(len(v) for v in instances.values()),
        "original_sources_changed_vs_handoff": sum(not r["sha_matches"] for r in originals),
        "native_index_headers_matching_source": sum(r.get("native_index_source_matches", False) for r in originals),
        "preferred_count": len(preferred), "preferred_original_instances": sum(r["formal_original_instances"] for r in preferred),
        "preferred_formal_instances": sum(r["formal_candidate_instances"] for r in preferred),
        "preferred_source_bytes_saved": sum(r["source_bytes_saved"] for r in preferred),
        "distinct_resource_candidates": len(all_candidates),
        "picking_candidates": sum(bool(r.get("candidate")) for r in picking_rows),
        "picking_texture_combinations_requiring_new_candidate": [r["label"] for r in picking_rows if r.get("preferred_combination_requires_rederive")],
        "failed_file_count": len(failed_files), "failed_candidate_labels": failed_candidates, "failed_picking_labels": failed_picking,
    },
    "evidence": {
        "candidate_handoff": norm(EVIDENCE / "candidate_handoff.json"),
        "visual_review": norm(EVIDENCE / "selected_visual_review.json"),
        "source_invalidation": norm(handoff["source_cache_invalidation"]),
        "inventory": norm(EVIDENCE / "inventory_report.json"),
        "decoded_inventory": norm(EVIDENCE / "inventory_map_definitions.json"),
        "review_generator_versions": sorted({r[x]["compiled_generator"] for r in handoff["preferred"] + handoff["exact_fallbacks"] for x in ("baseline", "optimized")}),
        "historical_single_model_reviews": "15 unique resource candidates: real GLTF import, production processing, SCN save/reopen, Compiled/Footprint/Preparation and twelve GPU views passed according to reports; ten lossless pixel-exact, five lossy with six shadow views and human approval. No new rendering performed by this audit.",
    },
    "acceptance_gaps": [
        "Historical native review generators differ, including some baseline/candidate pairs. Rebuild isolated derived artifacts under frozen current code; do not retag old cache or claim its current validity.",
        "All new optimized references remain candidates. Whole-map game/editor loading, current G1/G2/G3 toggles, transfer and HTTP editing/save/reopen have not yet been jointly accepted.",
        "Seven metadata candidates explicitly lack GPU/HTTP acceptance. Three shrubs derive from lossless texture versions rather than preferred PBR2k versions; combining requires a new bound candidate and checks.",
        "Wind evidence samples still/t1/t4, not continuous shimmer; dedicated bright/dark alpha-edge coverage is not demonstrated in the inspected reports. Existing distant pennant moire remains documented.",
    ],
    "failed_files": failed_files,
}
OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"output": norm(OUTPUT), "summary": result["summary"], "reference_binding": result["reference_binding"], "checkpoint": result["baseline_checkpoint"]}, ensure_ascii=False, indent=2))
