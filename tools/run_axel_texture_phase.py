"""Run one owned, private-desktop map texture sample; preserve every outcome."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess
import time

from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]
MAP = Path("D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    files = list((ROOT / "scripts").rglob("*.gd"))
    # Custom material behavior is part of the measured source, too.
    files += list((ROOT / "scripts").rglob("*.gdshader"))
    files += list((ROOT / "scripts").rglob("*.gdshaderinc"))
    files += [ROOT / "tools" / name for name in (
        "profile_axel_game_pipeline.gd", "profile_axel_white_streaming.gd",
        "profile_axel_worker_capacity.gd", "run_godot_background.py",
        "run_axel_texture_phase.py")]
    return {str(p.relative_to(ROOT)).replace("\\", "/"): digest(p) for p in files}


def save(path, value):
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stage", choices=("white", "map"), default="map")
    parser.add_argument("--cold-index", action="store_true")
    parser.add_argument("--legacy-publication", action="store_true")
    parser.add_argument("--legacy-source-reads", action="store_true")
    parser.add_argument("--traverse", action="store_true")
    parser.add_argument("--texture-profile", action="store_true")
    parser.add_argument("--batch-timeline", action="store_true")
    parser.add_argument("--without-covered-batch-borrow", action="store_true")
    parser.add_argument("--without-uv-projection-elision", action="store_true")
    parser.add_argument("--serial-chunk-textures", action="store_true")
    parser.add_argument("--without-texture-plan-reuse", action="store_true")
    parser.add_argument("--sync-texture-headers", action="store_true")
    parser.add_argument("--full-cache-trims", action="store_true")
    parser.add_argument("--full-stream-adoption", action="store_true")
    parser.add_argument("--unaccounted-stream-removals", action="store_true")
    parser.add_argument("--screenshot", action="store_true")
    parser.add_argument("--timeout", type=int, default=420)
    args = parser.parse_args()
    output = args.output.resolve()
    paths = {suffix: output.with_suffix("." + suffix) for suffix in
             ("json", "log", "launch.json", "result.json")}
    if any(p.exists() for p in paths.values()):
        raise FileExistsError("Use a new output stem; failed samples are retained")
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(args.engine.resolve()), "--path", str(ROOT), "--script",
           "res://tools/profile_axel_worker_capacity.gd", "--",
           "--output=" + str(paths["json"]), "--mesh-only", "--without-mock-server",
           "--without-hud", "--uncapped-runtime", "--uncapped-loading",
           "--runtime-seconds=0", "--origin-seconds=8", "--steady-seconds=0",
           "--texture-lighting", "--post-ready-seconds=10",
           "--native-only", "--efficient-membership-probe", "--settle-demands",
           "--without-derived-geometry-cache", "--without-prefab-bounds-cache",
           "--without-model-metadata-cache"]
    cmd += ["--white-material", "--without-map-textures"] if args.stage == "white" else ["--map-texture-stage"]
    cmd += ["--native-departure", "--frame-split-probe"] if args.traverse else ["--origin-only"]
    if args.cold_index:
        cmd.append("--cold-index")
    if args.legacy_publication:
        cmd.append("--legacy-prepared-material-publication")
    if args.legacy_source_reads:
        cmd.append("--without-mounted-texture-source-reuse")
    if args.texture_profile:
        cmd.append("--texture-stage-profile")
    if args.batch_timeline:
        cmd.append("--batch-timeline")
    if args.without_covered_batch_borrow:
        cmd.append("--without-covered-batch-borrow")
    if args.without_uv_projection_elision:
        cmd.append("--without-uv-projection-elision")
    if args.serial_chunk_textures:
        cmd.append("--serial-chunk-textures")
    if args.without_texture_plan_reuse:
        cmd.append("--without-texture-plan-reuse")
    if args.sync_texture_headers:
        cmd.append("--sync-texture-headers")
    if args.full_cache_trims:
        cmd.append("--full-cache-trims")
    if args.full_stream_adoption:
        cmd.append("--full-stream-adoption")
    if args.unaccounted_stream_removals:
        cmd.append("--unaccounted-stream-removals")
    if args.screenshot:
        cmd.append("--stage-screenshot")
    before = sources()
    launch = {"command": cmd, "engine_sha256": digest(args.engine),
              "map_sha256": digest(MAP), "source_before": before,
              "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "stage": args.stage, "legacy_publication": args.legacy_publication,
              "legacy_source_reads": args.legacy_source_reads,
              "texture_profile": args.texture_profile,
              "batch_timeline": args.batch_timeline,
              "covered_batch_borrow": not args.without_covered_batch_borrow,
              "uv_projection_elision": not args.without_uv_projection_elision,
              "parallel_chunk_textures": not args.serial_chunk_textures,
              "texture_plan_reuse": not args.without_texture_plan_reuse,
              "async_texture_headers": not args.sync_texture_headers,
              "incremental_cache_budget": not args.full_cache_trims,
              "incremental_stream_adoption": not args.full_stream_adoption,
              "owned_removal_accounting": not args.unaccounted_stream_removals,
              "scope": "Map/prefab textures with imported-model materials still white" if args.stage == "map" else "All-white baseline",
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
               "owned": owned, "source_unchanged": before == sources(),
               "map_unchanged": launch["map_sha256"] == digest(MAP),
               "errors": errors, "failures": report.get("failures"),
               "entry_ms": report.get("entry_ms"), "full_ready": report.get("origin_first_ready"),
               "not_p95": "Single sample; do not infer stability or treat diagnostics as ordinary samples."}
    outcome["functional_ok"] = (code == 0 and bool(report) and not errors and
                                report.get("failures") == [] and outcome["source_unchanged"] and
                                outcome["map_unchanged"] and bool(outcome["full_ready"]))
    save(paths["result.json"], outcome)
    print(json.dumps(outcome, ensure_ascii=False), flush=True)
    return 0 if outcome["functional_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
