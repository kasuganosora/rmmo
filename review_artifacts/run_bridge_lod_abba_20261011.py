"""Controlled, non-foreground game-entry ABBA for the two existing LOD maps.

Default invocation only prepares metadata/commands. GPU execution requires --run.
No map, authored resource, production setting, or cache is rewritten here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

ROOT = Path("D:/code/rmmo")
RUNTIME = Path("D:/code/rmmo_runtime")
OUT = RUNTIME / "review_artifacts"
OLD_MAP = RUNTIME / "cache/world3d/reference_pennant_checkpoint_20261009/map.gltf"
OLD_SHA = "5d8137af367d2ce27e15b4155dec78be8a6c47a7c99c1fbc8cce1090d9b1a770"
FORMAL = RUNTIME / "maps/medieval_river_town/map.gltf"
CHECKPOINT = OUT / "bridge_lod_game_checkpoint_20261011.json"
LOD_DIR = OUT / "bridge_lod_update_20261011"
PREFIX = "bridge_lod_abba"
DATE = "20261011"
TARGET_BRIDGE = "stone_e_0be972769041dbc9"
SEQUENCE = [("warm_old", "old"), ("a1", "old"), ("b1", "lod"), ("b2", "lod"), ("a2", "old")]
PROFILE_KEYS = [
    "parser_total_us", "parse_us", "hydrate_us", "validate_us", "prefab_decode_us",
    "asset_parse_us", "asset_parse_wall_us", "texture_decode_us", "build_total_us",
    "mesh_us", "mesh_cache_read_wait_us", "asset_instantiate_us", "hit_us", "miss_us",
    "initial_asset_paths", "initial_models_prefetched", "reference_index_hit",
    "reference_index_reason", "reference_index_rebuilt_before_models", "reference_index_read_us",
    "mesh_cache_candidate", "mesh_cache_scope", "asset_admission", "reference_read",
    "validation_parts", "definition_cache",
]
FIXED_FLAGS = [
    "bridge_texture_preparation", "prefab_texture_preparation", "native_entry_prefetch",
    "shared_prefab_textures", "collision_face_prefetch", "collision_first",
    "deferred_native_preparation", "deferred_native_budget", "background_navigation",
    "background_wind", "building_readiness", "collision_query_cache", "no_collision_proof",
]


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for part in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(part)
    return digest.hexdigest()


def source_fingerprint() -> str:
    # All runtime source remains identical across rounds; unrelated docs/tests may change.
    paths = sorted((ROOT / "scripts").rglob("*.gd"))
    paths += [ROOT / "project.godot", ROOT / "tools/profile_game_entry.gd", ROOT / "tools/run_godot_background.py"]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(str(path.relative_to(ROOT)).encode("utf-8"))
        digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def map_hashes(maps: dict[str, Path]) -> dict[str, str]:
    return {key: sha256(path) for key, path in {**maps, "formal": FORMAL}.items()}


def lod_size_summary() -> dict:
    # Explicit allowlist: plan contains large encoded payloads that must not enter reports.
    plan = read_json(LOD_DIR / "plan.json")
    keys = ["base_triangles", "lod_index_bytes", "outer_bytes_before", "outer_bytes_after",
            "outer_bytes_delta", "raw_before", "raw_after", "raw_delta", "base_exact",
            "collision_exact", "materials_exact", "other_frozen_data_exact", "duplicated_base_surface_bytes"]
    bridges = [{"uuid": item["uuid"], **{key: item["stats"].get(key) for key in keys}}
               for item in plan["bridges"]]
    del plan
    maps = {"old": OLD_MAP, "lod": Path(read_json(CHECKPOINT)["map"])}
    refs = {}
    for variant, path in maps.items():
        root = read_json(path)["nodes"][0]["extras"]
        refs[variant] = {record["uuid"]: record["rmmo_ref"] for record in root["rmmo_records"]}
    actual = []
    for bridge in bridges:
        uuid = bridge["uuid"]
        before = (maps["old"].parent / refs["old"][uuid]["uri"]).stat().st_size
        after = (maps["lod"].parent / refs["lod"][uuid]["uri"]).stat().st_size
        actual.append({"uuid": uuid, "old_bytes": before, "lod_bytes": after, "delta_bytes": after - before})
    review = read_json(LOD_DIR / "review.json")
    return {"bridges": bridges, "plan_outer_bytes_are_estimates": True,
            "totals": {key: sum(item[key] for item in bridges) for key in keys[:8]},
            "actual_rmres_files": actual,
            "actual_rmres_totals": {key: sum(item[key] for item in actual) for key in ["old_bytes", "lod_bytes", "delta_bytes"]},
            "gpu_visual_acceptance_triangles": review.get("triangle_comparisons", []),
            "size_scope": "Five bridge payloads only. Actual rmres file sizes are the storage cost; plan outer byte estimates are retained separately. LOD adds indices, with original base geometry/collision retained."}


def report_paths(label: str) -> tuple[Path, Path]:
    report = OUT / f"{PREFIX}_{label}_{DATE}.json"
    return report, report.with_suffix(".log")


def command_for(label: str, map_path: Path) -> list[str]:
    report, log = report_paths(label)
    return [sys.executable, str(ROOT / "tools/run_godot_background.py"),
            "--timeout", "260", "--log", str(log), "--",
            "D:/tools/godot/Godot_v4.7.2-stable_win64.exe", "--path", str(ROOT),
            "--script", "res://tools/profile_game_entry.gd", "--", f"--map={map_path}",
            f"--output={report}", "--spawn=321.2,0.9,160.3", "--monitor", "--bridge-texture-preparation"]


def extract_row(label: str, variant: str, data: dict, log_text: str) -> dict:
    profile = data.get("map_profile", {})
    deferred = data.get("entry_deferred_profile", {})
    monitor = data.get("monitor", {})
    bridge_events = [event for event in monitor.get("trace", {}).get("events", [])
                     if event.get("label") == "deferred.publication"
                     and event.get("details", {}).get("group_id", "").startswith("bridge:")]
    bridge_rows = []
    for event in bridge_events:
        details = event.get("details", {})
        bridge_rows.append({"uuid": details.get("uuid"), "group_id": details.get("group_id"),
                            "duration_ms": details.get("elapsed_us", event["duration_us"]) / 1000,
                            "trace_duration_ms": event["duration_us"] / 1000,
                            "thread_id": event.get("thread_id"),
                            "prefab_parts_ms": details.get("prefab_parts_ms", {}),
                            "instance_parts_ms": details.get("instance_parts_ms", {})})
    target = [item for item in bridge_rows if TARGET_BRIDGE in str(item.get("group_id", ""))
              or item.get("uuid") == TARGET_BRIDGE]
    lines = log_text.splitlines()
    report, log = report_paths(label)
    return {
        "label": label, "variant": variant, "excluded_warmup": label == "warm_old",
        "report": str(report), "log": str(log),
        **{key: data.get(key) for key in ["entry_ms", "entry_core_ready_ms", "failures", "map", "map_sha",
                                          "formal_sha", "cache_candidate", "cache_existed", "cache_scope",
                                          "reset_derived_cache", "requested_spawn", "requested_chunk",
                                          "engine_build", "screenshot_avatar_hidden"]},
        "configuration": {key: data.get(key) for key in FIXED_FLAGS},
        "pass_count": sum(line.startswith(("PASS ", "PASS:")) for line in lines),
        "fail_lines": [line for line in lines if line.startswith(("FAIL ", "FAIL:"))],
        "errors": [line for line in lines if line.startswith(("ERROR:", "SCRIPT ERROR:"))],
        "warnings": [line for line in lines if line.startswith("WARNING:")],
        "unicode_diagnostics": [line for line in lines if "Unicode parsing error" in line],
        "map_profile": {key: profile.get(key) for key in PROFILE_KEYS},
        "bridge_publications": bridge_rows,
        "target_bridge_publication_ms": sum(item["duration_ms"] for item in target) if target else None,
        "worker_elapsed": {
            "asset_stages": profile.get("asset_admission_details", {}).get("stages", {}),
            "deferred_worker_us": deferred.get("worker_us"),
            "worker_capacity": deferred.get("worker_capacity", {}),
            "reference_worker_us": deferred.get("reference_worker_us"),
            "prefab_pixels_worker_us": deferred.get("prefab_pixels", {}).get("worker_us"),
            "bridge_texture_jobs": deferred.get("bridge_texture_jobs"),
            "bridge_texture_missing_keys": deferred.get("bridge_texture_missing_keys"),
        },
        "admission": deferred.get("admission", {}),
        "frames_by_phase_ms": monitor.get("phase_frame_percentiles_ms", {}),
        "playable_p99_ms": monitor.get("phase_frame_percentiles_ms", {}).get("playable_background", {}).get("99"),
    }


def comparison(rows: list[dict]) -> dict:
    timed = [row for row in rows if not row["excluded_warmup"]]
    if len(timed) != 4:
        return {"complete": False}
    result = {"complete": True, "metrics": {}}
    for metric in ["entry_ms", "entry_core_ready_ms", "target_bridge_publication_ms", "playable_p99_ms"]:
        old = [row[metric] for row in timed if row["variant"] == "old"]
        lod = [row[metric] for row in timed if row["variant"] == "lod"]
        if any(value is None for value in old + lod):
            result["metrics"][metric] = {"available": False}
            continue
        before, after = statistics.mean(old), statistics.mean(lod)
        result["metrics"][metric] = {"old": old, "lod": lod, "old_mean": before, "lod_mean": after,
                                      "lod_minus_old": after - before,
                                      "change_percent": (after / before - 1) * 100 if before else None}
    for key in ["parser_total_us", "hydrate_us", "validate_us", "asset_parse_wall_us", "texture_decode_us", "build_total_us"]:
        old = [row["map_profile"].get(key) for row in timed if row["variant"] == "old"]
        lod = [row["map_profile"].get(key) for row in timed if row["variant"] == "lod"]
        if all(isinstance(value, (int, float)) for value in old + lod):
            result["metrics"][key] = {"old_mean": statistics.mean(old), "lod_mean": statistics.mean(lod)}
    result["comparable_cache_hits"] = all(row["cache_candidate"] and row["cache_existed"]
        and row["map_profile"]["reference_index_hit"] and row["map_profile"]["mesh_cache_candidate"]
        and not row["map_profile"]["reference_index_rebuilt_before_models"] for row in timed)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true", help="Run five private-desktop GPU processes (root approval required in this collaboration).")
    args = parser.parse_args()
    checkpoint = read_json(CHECKPOINT)
    maps = {"old": OLD_MAP, "lod": Path(checkpoint["map"])}
    resource_root = (RUNTIME / "cache/world3d").resolve()
    for path in maps.values():
        if not path.is_file() or not path.resolve().is_relative_to(resource_root):
            raise RuntimeError(f"Invalid existing temporary map: {path}")
    initial_hashes = map_hashes(maps)
    if initial_hashes["old"] != OLD_SHA or initial_hashes["lod"] != checkpoint["sha256"]:
        raise RuntimeError("Temporary map SHA does not match its own expected version")
    cursor = (ROOT / "scripts/world3d/document_open_cursor.gd").read_text(encoding="utf-8")
    if not re.search(r"prefab_warm_workers\s*:?=\s*2\b", cursor):
        raise RuntimeError("Expected unchanged current Cursor prefab warm default 2")
    initial_source = source_fingerprint()
    summary = {
        "scope": "Same source/configuration, fresh process, old-map vs published-LOD-map ABBA; existing temporary maps only.",
        "sequence": [label for label, _ in SEQUENCE],
        "warmup_note": "warm_old excluded to rebuild any stale derived index from prior Cursor changes. No OS or asset cache clearing; both timed variants must hit their own index/selected mesh candidate.",
        "cpu_note": "Worker metrics are cumulative task elapsed times/concurrency, not measured OS CPU utilization; no additional hardware sampler overhead.",
        "prefab_warm_workers_default": 2, "initial_map_sha256": initial_hashes,
        "runtime_source_fingerprint": initial_source, "lod_data": lod_size_summary(), "rows": [],
    }
    if not args.run:
        print(json.dumps({"prepared": True, "gpu_started": False, "sha256": initial_hashes,
                          "lod_totals": summary["lod_data"]["totals"],
                          "commands": [command_for(label, maps[variant]) for label, variant in SEQUENCE]}, indent=2))
        return 0
    summary_path = OUT / f"{PREFIX}_{DATE}.json"
    analysis_path = ROOT / "review_artifacts" / f"bridge_lod_abba_analysis_{DATE}.json"
    outputs = [summary_path, analysis_path] + [path for label, _ in SEQUENCE for path in report_paths(label)]
    if any(path.exists() for path in outputs):
        raise RuntimeError("Refusing to overwrite existing LOD ABBA evidence")
    started = time.time()
    try:
        for label, variant in SEQUENCE:
            if map_hashes(maps) != initial_hashes or source_fingerprint() != initial_source:
                raise RuntimeError("Map/source changed before round")
            print(f"START {label} variant={variant}", flush=True)
            completed = subprocess.run(command_for(label, maps[variant]), cwd=ROOT, timeout=280)
            report, log = report_paths(label)
            logs = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
            if not report.exists():
                raise RuntimeError(f"{label}: report missing; return code {completed.returncode}; log tail {logs[-2000:]}")
            row = extract_row(label, variant, read_json(report), logs)
            row["return_code"] = completed.returncode
            row["map_sha256_after"] = map_hashes(maps)
            row["source_unchanged"] = source_fingerprint() == initial_source
            summary["rows"].append(row)
            summary["comparison"] = comparison(summary["rows"])
            summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({key: row[key] for key in ["label", "entry_ms", "target_bridge_publication_ms", "pass_count", "failures", "playable_p99_ms"]}), flush=True)
            if completed.returncode or row["failures"] or row["fail_lines"] or row["errors"] or row["pass_count"] != 22:
                raise RuntimeError(f"{label}: functional acceptance failed")
            if row["map_sha"] != initial_hashes[variant] or row["formal_sha"] != initial_hashes["formal"] \
                    or row["map_sha256_after"] != initial_hashes or not row["source_unchanged"]:
                raise RuntimeError(f"{label}: map/source identity changed")
            if not row["screenshot_avatar_hidden"] or not row["configuration"]["bridge_texture_preparation"] \
                    or row["reset_derived_cache"] or row["target_bridge_publication_ms"] is None:
                raise RuntimeError(f"{label}: expected profile configuration/evidence missing")
            first = summary["rows"][0]
            if row["configuration"] != first["configuration"] or row["engine_build"] != first["engine_build"] \
                    or row["requested_spawn"] != first["requested_spawn"]:
                raise RuntimeError(f"{label}: configuration differs")
            if label != "warm_old" and not (row["cache_candidate"] and row["cache_existed"]
                    and row["map_profile"]["reference_index_hit"] and row["map_profile"]["mesh_cache_candidate"]
                    and not row["map_profile"]["reference_index_rebuilt_before_models"]):
                raise RuntimeError(f"{label}: timed cache/index miss, cannot claim controlled warm comparison")
        summary["complete"] = True
    except Exception as exc:
        summary["complete"] = False
        summary["error"] = str(exc)
        raise
    finally:
        summary["elapsed_seconds"] = time.time() - started
        summary["final_map_sha256"] = map_hashes(maps)
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        analysis_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
