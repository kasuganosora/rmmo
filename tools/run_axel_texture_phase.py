"""Run one owned, private-desktop map texture sample; preserve every outcome."""
import argparse
import configparser
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess
import time

from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]
MAP = Path("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf")
REVIEW_ROOT = Path("D:/code/rmmo_runtime/review_artifacts")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    files = list((ROOT / "scripts").rglob("*.gd"))
    # Custom material behavior is part of the measured source, too.
    files += list((ROOT / "scripts").rglob("*.gdshader"))
    files += list((ROOT / "scripts").rglob("*.gdshaderinc"))
    files += [ROOT / "tools" / name for name in (
        "profile_axel_game_pipeline.gd", "profile_axel_white_streaming.gd",
        "profile_axel_predictive_streaming.gd",
        "profile_axel_worker_capacity.gd", "profile_axel_fault_capture.gd", "run_godot_background.py",
        "run_axel_texture_phase.py", "full_native_fixture_audit.py")]
    return {str(p.relative_to(ROOT)).replace("\\", "/"): digest(p) for p in files}


def save(path, value):
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)


def requeue_controls_match(report, legacy, suppressed):
    controls = report.get("controls", {})
    return (isinstance(controls, dict) and
            controls.get("dirty_requeue_index") is (not legacy) and
            controls.get("selective_requeue_membership") is (not legacy) and
            report.get("sync_slow_logs_suppressed") is suppressed)


def test_fixture_paths(map_path, content_root, stage="map"):
    if map_path is None and content_root is None:
        return None
    if map_path is None or content_root is None:
        raise ValueError("--map-path and --content-root must be supplied together")
    review = REVIEW_ROOT.resolve(strict=True)
    root = content_root.resolve(strict=True)
    map_file = map_path.resolve(strict=True)
    if (root == review or not root.is_relative_to(review) or not root.is_dir() or
            not map_file.is_relative_to(root) or not map_file.is_file() or
            not (root / ("full_fixture_manifest.json" if stage == "full" else "fixture_manifest.json")).is_file()):
        raise ValueError("test map and content root must be an owned review-artifact fixture")
    return map_file, root


def stage_arguments(stage):
    if stage == "white": return ["--white-material", "--without-map-textures"]
    if stage == "map": return ["--map-texture-stage"]
    if stage == "full": return ["--full-material-stage"]
    raise ValueError("unsupported stage")


def full_stage_controls_match(report):
    if not isinstance(report, dict) or not isinstance(report.get("controls"), dict): return False
    controls = report["controls"]
    audit = report.get("full_model_material_audit", {})
    if not isinstance(audit, dict): return False
    meshes, surfaces = audit.get("visible_model_meshes"), audit.get("base_textured_surfaces")
    if type(meshes) is not int or type(surfaces) is not int: return False
    return (controls.get("full_material_stage") is True and controls.get("map_texture_stage") is False
            and controls.get("map_textures") is True and controls.get("white_material") is False
            and controls.get("white_native") is False and controls.get("native_geometry_only") is False
            and controls.get("compiled") is True
            and audit.get("after_real_draw") is True and meshes > 0 and surfaces > 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--map-path", type=Path, help="Explicit isolated test map; requires --content-root")
    parser.add_argument("--content-root", type=Path, help="Owned isolated fixture root; requires --map-path")
    parser.add_argument("--stage", choices=("white", "map", "full"), default="map")
    parser.add_argument("--full-fixture-manifest-sha256")
    parser.add_argument("--expected-full-models", type=int, default=49)
    parser.add_argument("--cold-index", action="store_true")
    parser.add_argument("--legacy-publication", action="store_true")
    parser.add_argument("--separate-material-publication", action="store_true")
    parser.add_argument("--without-native-prefab-direct-specs", action="store_true")
    parser.add_argument("--legacy-source-reads", action="store_true")
    parser.add_argument("--legacy-vsync-submission", action="store_true")
    parser.add_argument("--traverse", action="store_true")
    parser.add_argument("--texture-profile", action="store_true")
    parser.add_argument("--batch-timeline", action="store_true")
    parser.add_argument("--profile-procedural-uploads", action="store_true")
    closed_building = parser.add_mutually_exclusive_group()
    closed_building.add_argument("--closed-building-preparation", action="store_true")
    closed_building.add_argument("--without-closed-building-preparation", action="store_true")
    building_arrivals = parser.add_mutually_exclusive_group()
    building_arrivals.add_argument("--closed-building-arrivals", action="store_true")
    building_arrivals.add_argument("--without-closed-building-arrivals", action="store_true")
    parser.add_argument("--without-covered-source-coalescing", action="store_true")
    parser.add_argument("--without-prepared-road-paint", action="store_true")
    parser.add_argument("--without-covered-batch-borrow", action="store_true")
    parser.add_argument("--without-uv-projection-elision", action="store_true")
    parser.add_argument("--serial-chunk-textures", action="store_true")
    texture_upload = parser.add_mutually_exclusive_group()
    texture_upload.add_argument("--background-texture-upload", action="store_true")
    texture_upload.add_argument("--without-background-texture-upload", action="store_true")
    parser.add_argument("--without-background-pixel-retirement", action="store_true")
    parser.add_argument("--without-batched-texture-handoff", action="store_true")
    parser.add_argument("--without-incremental-source-retirement", action="store_true")
    parser.add_argument("--without-raw-face-reuse", action="store_true")
    parser.add_argument("--without-texture-plan-reuse", action="store_true")
    parser.add_argument("--sync-texture-headers", action="store_true")
    parser.add_argument("--full-cache-trims", action="store_true")
    parser.add_argument("--without-capacity-eviction-accounting", action="store_true")
    parser.add_argument("--scripted-cache-sort", action="store_true")
    parser.add_argument("--without-lazy-terrain-height", action="store_true")
    parser.add_argument("--full-stream-adoption", action="store_true")
    parser.add_argument("--unaccounted-stream-removals", action="store_true")
    parser.add_argument("--rebuild-demand-catalogues", action="store_true")
    parser.add_argument("--legacy-requeue", action="store_true")
    parser.add_argument("--suppress-sync-slow-logs", action="store_true")
    parser.add_argument("--screenshot", action="store_true")
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--fault-capture-extension", type=Path,
                        help="Opt-in native first-chance capture; marks this as a diagnostic sample")
    args = parser.parse_args()
    fixture = test_fixture_paths(args.map_path, args.content_root, args.stage)
    map_path = fixture[0] if fixture else MAP
    full_before = None
    if args.stage == "full":
        if not fixture or not args.full_fixture_manifest_sha256:
            parser.error("full stage requires an isolated full fixture and its manifest SHA")
        from full_native_fixture_audit import verify_full_fixture
        full_before = verify_full_fixture(fixture[1], map_path, args.full_fixture_manifest_sha256.lower(), args.expected_full_models)
    elif args.full_fixture_manifest_sha256:
        parser.error("full fixture manifest is only valid for full stage")
    output = args.output.resolve()
    paths = {suffix: output.with_suffix("." + suffix) for suffix in
             ("json", "log", "launch.json", "result.json")}
    if any(p.exists() for p in paths.values()):
        raise FileExistsError("Use a new output stem; failed samples are retained")
    fault_capture = None
    if args.fault_capture_extension:
        paths["fault.raw"] = output.with_suffix(".fault.raw")
        if paths["fault.raw"].exists():
            raise FileExistsError(paths["fault.raw"])
        extension = args.fault_capture_extension.resolve()
        config = configparser.ConfigParser(interpolation=None)
        config.read(extension, encoding="utf-8")
        library = Path(config["libraries"]["windows.x86_64"].strip('"'))
        if not library.is_absolute():
            library = extension.parent / library
        fault_capture = {"extension": str(extension), "extension_sha256": digest(extension),
                         "library": str(library), "library_sha256": digest(library),
                         "raw": str(paths["fault.raw"]),
                         "contract": "First-chance context only; original exception continues. No debugger, polling, or priority change."}
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(args.engine.resolve()), "--path", str(ROOT), "--script",
           "res://tools/profile_axel_fault_capture.gd" if fault_capture else "res://tools/profile_axel_worker_capacity.gd", "--",
           "--output=" + str(paths["json"]), "--mesh-only", "--without-mock-server",
           "--without-hud", "--uncapped-runtime", "--uncapped-loading",
           "--runtime-seconds=0", "--origin-seconds=8", "--steady-seconds=0",
           "--texture-lighting", "--post-ready-seconds=10",
           "--native-only", "--efficient-membership-probe", "--settle-demands",
           "--without-derived-geometry-cache", "--without-prefab-bounds-cache",
           "--without-model-metadata-cache"]
    cmd += stage_arguments(args.stage)
    if fixture:
        cmd += ["--test-map=" + str(map_path), "--test-content-root=" + str(fixture[1])]
    cmd += ["--native-departure", "--frame-split-probe"] if args.traverse else ["--origin-only"]
    if args.cold_index:
        cmd.append("--cold-index")
    if args.legacy_publication:
        cmd.append("--legacy-prepared-material-publication")
    if args.separate_material_publication:
        cmd.append("--separate-material-publication")
    if args.without_native_prefab_direct_specs:
        cmd.append("--without-native-prefab-direct-specs")
    if args.legacy_source_reads:
        cmd.append("--without-mounted-texture-source-reuse")
    if args.legacy_vsync_submission:
        cmd.append("--legacy-vsync-submission")
    if args.texture_profile:
        cmd.append("--texture-stage-profile")
    if args.batch_timeline:
        cmd.append("--batch-timeline")
    if args.profile_procedural_uploads:
        cmd.append("--profile-procedural-uploads")
    if args.closed_building_preparation:
        cmd.append("--closed-building-preparation")
    if args.without_closed_building_preparation:
        cmd.append("--without-closed-building-preparation")
    if args.closed_building_arrivals:
        cmd.append("--closed-building-arrivals")
    if args.without_closed_building_arrivals:
        cmd.append("--without-closed-building-arrivals")
    if args.without_covered_source_coalescing:
        cmd.append("--without-covered-source-coalescing")
    if args.without_prepared_road_paint:
        cmd.append("--without-prepared-road-paint")
    if args.without_covered_batch_borrow:
        cmd.append("--without-covered-batch-borrow")
    if args.without_uv_projection_elision:
        cmd.append("--without-uv-projection-elision")
    if args.serial_chunk_textures:
        cmd.append("--serial-chunk-textures")
    if args.background_texture_upload:
        cmd.append("--background-texture-upload")
    if args.without_background_texture_upload:
        cmd.append("--without-background-texture-upload")
    if args.without_background_pixel_retirement:
        cmd.append("--without-background-pixel-retirement")
    if args.without_batched_texture_handoff:
        cmd.append("--without-batched-texture-handoff")
    if args.without_incremental_source_retirement:
        cmd.append("--without-incremental-source-retirement")
    if args.without_raw_face_reuse:
        cmd.append("--without-raw-face-reuse")
    if args.without_texture_plan_reuse:
        cmd.append("--without-texture-plan-reuse")
    if args.sync_texture_headers:
        cmd.append("--sync-texture-headers")
    if args.full_cache_trims:
        cmd.append("--full-cache-trims")
    if args.without_capacity_eviction_accounting:
        cmd.append("--without-capacity-eviction-accounting")
    if args.scripted_cache_sort:
        cmd.append("--scripted-cache-sort")
    if args.without_lazy_terrain_height:
        cmd.append("--without-lazy-terrain-height")
    if args.full_stream_adoption:
        cmd.append("--full-stream-adoption")
    if args.unaccounted_stream_removals:
        cmd.append("--unaccounted-stream-removals")
    if args.rebuild_demand_catalogues:
        cmd.append("--rebuild-demand-catalogues")
    if args.legacy_requeue:
        cmd.append("--legacy-requeue")
    if args.suppress_sync_slow_logs:
        cmd.append("--suppress-sync-slow-logs")
    if args.screenshot:
        cmd.append("--stage-screenshot")
    if fault_capture:
        cmd += ["--fault-capture-extension=" + fault_capture["extension"],
                "--fault-capture-file=" + fault_capture["raw"]]
    before = sources()
    launch = {"command": cmd, "engine_sha256": digest(args.engine),
              "map_sha256": digest(map_path), "map_path": str(map_path),
              "content_root": str(fixture[1]) if fixture else "D:/code/rmmo_runtime", "source_before": before,
              "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "stage": args.stage, "legacy_publication": args.legacy_publication,
              "legacy_requeue": args.legacy_requeue,
              "suppress_sync_slow_logs": args.suppress_sync_slow_logs,
              "diagnostic": bool(fault_capture) or args.batch_timeline or args.profile_procedural_uploads or args.texture_profile, "fault_capture": fault_capture,
              "legacy_source_reads": args.legacy_source_reads,
              "legacy_vsync_submission": args.legacy_vsync_submission,
              "texture_profile": args.texture_profile,
              "batch_timeline": args.batch_timeline,
              "profile_procedural_uploads": args.profile_procedural_uploads,
              "closed_building_preparation": not args.without_closed_building_preparation,
              "closed_building_arrivals_override": True if args.closed_building_arrivals else (False if args.without_closed_building_arrivals else None),
              "covered_source_coalescing": not args.without_covered_source_coalescing,
              "prepared_road_paint": not args.without_prepared_road_paint,
              "covered_batch_borrow": not args.without_covered_batch_borrow,
              "uv_projection_elision": not args.without_uv_projection_elision,
              "parallel_chunk_textures": not args.serial_chunk_textures,
              "batched_texture_handoff": not args.without_batched_texture_handoff,
              "incremental_source_retirement": not args.without_incremental_source_retirement,
              "raw_face_reuse": not args.without_raw_face_reuse,
              "combined_material_publication": not args.separate_material_publication,
              "native_prefab_direct_specs": not args.without_native_prefab_direct_specs,
              "texture_plan_reuse": not args.without_texture_plan_reuse,
              "async_texture_headers": not args.sync_texture_headers,
              "incremental_cache_budget": not args.full_cache_trims,
              "capacity_eviction_accounting": not args.without_capacity_eviction_accounting,
              "native_cache_sort": not args.scripted_cache_sort,
              "background_pixel_retirement": not args.without_background_pixel_retirement,
              "lazy_terrain_height": not args.without_lazy_terrain_height,
              "incremental_stream_adoption": not args.full_stream_adoption,
              "owned_removal_accounting": not args.unaccounted_stream_removals,
              "reuse_demand_catalogues": not args.rebuild_demand_catalogues,
              "scope": {"map":"Map/prefab textures with imported-model materials still white", "white":"All-white baseline", "full":"Map/prefab textures and full native imported-model materials; core streaming only"}[args.stage],
              "full_fixture_before": full_before,
              "cache_scope": {"derived_index": "invalidated" if args.cold_index else "retained",
                              "geometry_cache": "disabled", "texture_disk_cache": "retained",
                              "native_products": "retained", "os_cache": "untouched"},
              "timing_contract": "Pipeline begin to three consecutive complete demand/job/stream/batch frames; map arm also drains pixel consumers. Not a full-game entry or physically cold disk test."}
    save(paths["launch.json"], launch)
    owned = {}

    def started(pid, tid):
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.GetPriorityClass.argtypes = [ctypes.c_void_p]
        kernel.GetPriorityClass.restype = ctypes.c_ulong
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            priority = kernel.GetPriorityClass(handle)
        finally:
            kernel.CloseHandle(handle)
        owned.update(pid=pid, main_thread_id=tid, priority_class=priority,
                     priority_modified=False, qos_modified=False)
        print(json.dumps(owned), flush=True)

    began = time.monotonic()
    try:
        result = run_background(cmd, cwd=ROOT, timeout=args.timeout, on_start=started)
        code, log = result.returncode, result.stdout
    except subprocess.TimeoutExpired as exc:
        code, log = 124, exc.stdout or b""
    paths["log"].write_bytes(log)
    report = json.loads(paths["json"].read_text(encoding="utf-8")) if paths["json"].exists() else {}
    errors = [line for line in log.decode("utf-8", errors="replace").splitlines()
              if "SCRIPT ERROR:" in line or line.startswith(("ERROR:", "FAIL "))]
    outcome = {"exit_code": code, "wall_seconds": time.monotonic() - began,
               "diagnostic": launch["diagnostic"],
               "owned": owned, "source_unchanged": before == sources(),
               "map_unchanged": launch["map_sha256"] == digest(map_path),
               "errors": errors, "failures": report.get("failures"),
               "entry_ms": report.get("entry_ms"), "full_ready": report.get("origin_first_ready"),
               "not_p95": "Single sample; do not infer stability or treat diagnostics as ordinary samples."}
    if full_before is not None:
        try:
            full_after = verify_full_fixture(fixture[1], map_path, args.full_fixture_manifest_sha256.lower(), args.expected_full_models)
            outcome["full_fixture_unchanged"] = full_before == full_after
        except Exception as exc:
            outcome["full_fixture_unchanged"] = False
            outcome["full_fixture_error"] = str(exc)
        outcome["full_controls_match"] = full_stage_controls_match(report)
    outcome["requeue_controls_match"] = requeue_controls_match(report, args.legacy_requeue, args.suppress_sync_slow_logs)
    outcome["functional_ok"] = (code == 0 and bool(report) and not errors and
                                report.get("failures") == [] and outcome["source_unchanged"] and
                                outcome["map_unchanged"] and bool(outcome["full_ready"]) and outcome["requeue_controls_match"])
    if full_before is not None:
        outcome["functional_ok"] &= outcome["full_fixture_unchanged"] and outcome["full_controls_match"]
    if fault_capture:
        raw = paths["fault.raw"].read_text(encoding="utf-8", errors="replace") if paths["fault.raw"].exists() else ""
        outcome["fault_capture_armed"] = "armed\t1" in raw
        outcome["first_chance_fault"] = "fault\t" in raw
        outcome["diagnostic_library_unchanged"] = digest(Path(fault_capture["library"])) == fault_capture["library_sha256"]
        outcome["functional_ok"] &= outcome["fault_capture_armed"] and outcome["diagnostic_library_unchanged"]
    save(paths["result.json"], outcome)
    print(json.dumps(outcome, ensure_ascii=False), flush=True)
    return 0 if outcome["functional_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
