"""Launch one isolated map sample; the existing runner owns the private desktop.

All mutable paths belong to review_artifacts. Supply a frozen copy of settings
and its SHA; this script never reads or writes the real user's settings.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

TOOLS_DIR = str(Path(__file__).resolve().parent)
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)
from isolated_fixture_lock import fixture_lock
from isolated_sidecar_switch import load_fixture, check_state

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = Path("D:/code/rmmo_runtime/review_artifacts")
RUNNER = ROOT / "tools" / "run_axel_texture_phase.py"


def inside(path, boundary):
    path, boundary = Path(path).resolve(), Path(boundary).resolve()
    if path == boundary or not path.is_relative_to(boundary):
        raise ValueError(f"path must be strictly inside review_artifacts: {path}")
    return path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def variant_audit(root, map_path, args):
    verified_root, data, stable = load_fixture(root, args.manifest_sha256.lower(), args.expected_candidates)
    if Path(data["target_map"]).resolve(strict=True) != map_path:
        raise ValueError("selected map does not match fixture manifest")
    state, variants = check_state(verified_root, data, stable)
    return {"state": state, "expected_state": args.expected_state,
            "manifest_sha256": args.manifest_sha256.lower(),
            "candidate_count": len(data["candidate_targets"]), "variants": variants,
            "stable_files": {str(path): sha for path, sha in sorted(stable.items(), key=lambda item: str(item[0]))},
            "cache_note": "Verification reads and hashes files and warms OS caches; not a physical cold disk sample."}


def write_json(path, value):
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)


def run_sample(args, *, runner=RUNNER, artifacts=ARTIFACTS):
    # Lock before reading the map hash, and retain the lock through the child
    # process and post-run checks. Only cooperating fixture consumers obey it.
    root = inside(args.content_root, Path(artifacts).resolve(strict=True))
    with fixture_lock(root, timeout=0.0):
        return _run_sample_locked(args, runner=runner, artifacts=artifacts)


def _run_sample_locked(args, *, runner, artifacts):
    artifacts = Path(artifacts).resolve(strict=True)
    sample = inside(args.sample_dir, artifacts)
    user = inside(args.user_dir, artifacts)
    content = inside(args.content_root, artifacts).resolve(strict=True)
    map_path = inside(args.map_path, artifacts).resolve(strict=True)
    settings = inside(args.settings, artifacts).resolve(strict=True)
    if not content.is_dir() or not map_path.is_file() or not settings.is_file():
        raise ValueError("content root must be a directory; map and settings must be files")
    if not map_path.is_relative_to(content):
        raise ValueError("test map must be inside test content root")
    # User caches and sample logs must not mutate either the copied package or
    # each other; symlinks have already been resolved by inside().
    for a, b in ((sample, content), (user, content), (sample, user)):
        if a == b or a.is_relative_to(b) or b.is_relative_to(a):
            raise ValueError("sample, user, and content directories must be disjoint")
    if settings.is_relative_to(user) or settings.is_relative_to(sample):
        raise ValueError("frozen settings must be outside mutable user and sample roots")
    if args.timeout <= 0:
        raise ValueError("timeout must be positive")
    if args.expected_state not in ("A", "B") or args.expected_candidates <= 0:
        raise ValueError("expected state or candidate count invalid")
    engine = Path(args.engine).resolve(strict=True)
    if not engine.is_file():
        raise ValueError("engine must be a file")
    settings_data = settings.read_bytes()
    settings_sha = digest(settings_data)
    if settings_sha != args.settings_sha256.lower():
        raise ValueError("frozen settings SHA does not match")
    map_sha = digest(map_path.read_bytes())
    sample.mkdir(parents=True, exist_ok=False)
    try:
        before = variant_audit(content, map_path, args)
    except Exception as exc:
        write_json(sample / "isolation.variants.before.json", {"ok": False, "error": str(exc)})
        raise
    before["ok"] = before["state"] == args.expected_state
    write_json(sample / "isolation.variants.before.json", before)
    if not before["ok"]:
        raise ValueError("fixture sidecar state does not match expected state")
    user.mkdir(parents=True, exist_ok=True)
    lock = user / ".isolated_axel_sample.lock"
    with lock.open("x", encoding="utf-8") as handle:
        handle.write(f"pid={os.getpid()}\n")
    try:
        roaming, local = user / "roaming", user / "local"
        roaming.mkdir(parents=True, exist_ok=True)
        local.mkdir(parents=True, exist_ok=True)
        temporary = sample / "temp"
        temporary.mkdir()
        target = roaming / "Godot" / "app_userdata" / "rmmo" / "game_settings.cfg"
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            with target.open("xb") as handle:
                handle.write(settings_data)
        except FileExistsError:
            if digest(target.read_bytes()) != settings_sha:
                raise ValueError("existing private settings differ from frozen snapshot")
        env = os.environ.copy()
        # The desktop runner uses tempfile.TemporaryFile for child output.
        # Keep that stream and Python bytecode out of shared system/project dirs.
        env.update(APPDATA=str(roaming), LOCALAPPDATA=str(local), TEMP=str(temporary),
                   TMP=str(temporary), TMPDIR=str(temporary), PYTHONDONTWRITEBYTECODE="1")
        cmd = [sys.executable, str(runner), "--engine", str(engine),
               "--output", str(sample / "sample"), "--map-path", str(map_path),
               "--content-root", str(content), "--stage", args.stage,
               "--timeout", str(args.timeout)]
        if args.traverse:
            cmd.append("--traverse")
        if args.cold_index:
            cmd.append("--cold-index")
        if args.texture_profile:
            cmd.append("--texture-profile")
        launch = {"command": cmd, "appdata": str(roaming), "localappdata": str(local), "temp": str(temporary),
                  "settings_sha256": settings_sha, "map_sha256": map_sha,
                  "settings_snapshot": str(settings), "map_path": str(map_path),
                  "content_root": str(content), "manifest_sha256": args.manifest_sha256.lower(),
                  "expected_state": args.expected_state, "expected_candidates": args.expected_candidates,
                  "cache_note": "Verification hashes warm OS caches; not physical cold disk. User directory may be reused; record cache state separately."}
        with (sample / "isolation.launch.json").open("x", encoding="utf-8") as handle:
            json.dump(launch, handle, indent=2)
        # The runner's CreateProcessW inherits THIS child's environment; never
        # change os.environ in the current process or other parallel samples.
        completed = subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, check=False)
        with (sample / "isolation.runner.log").open("xb") as handle:
            handle.write(completed.stdout)
        try:
            after = variant_audit(content, map_path, args)
            variants_unchanged = (after["state"] == args.expected_state and
                                  before["variants"] == after["variants"] and
                                  before["stable_files"] == after["stable_files"])
            after["ok"] = variants_unchanged
        except Exception as exc:
            variants_unchanged = False
            after = {"ok": False, "error": str(exc)}
        write_json(sample / "isolation.variants.after.json", after)
        result = {"exit_code": completed.returncode,
                  "frozen_settings_unchanged": digest(settings.read_bytes()) == settings_sha,
                  "private_settings_unchanged": target.is_file() and digest(target.read_bytes()) == settings_sha,
                  "map_unchanged": map_path.is_file() and digest(map_path.read_bytes()) == map_sha,
                  "variants_unchanged": variants_unchanged}
        with (sample / "isolation.result.json").open("x", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2)
        return result
    finally:
        lock.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("engine", "sample-dir", "user-dir", "content-root", "map-path", "settings"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--settings-sha256", required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--expected-state", choices=("A", "B"), required=True)
    parser.add_argument("--expected-candidates", type=int, default=11)
    parser.add_argument("--stage", choices=("white", "map"), default="map")
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--traverse", action="store_true")
    parser.add_argument("--cold-index", action="store_true")
    parser.add_argument("--texture-profile", action="store_true")
    args = parser.parse_args()
    result = run_sample(args)
    print(json.dumps(result), flush=True)
    return 0 if result["exit_code"] == 0 and all(v for k, v in result.items() if k != "exit_code") else 1


if __name__ == "__main__":
    raise SystemExit(main())
