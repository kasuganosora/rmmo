"""GPU regression for the bounded native StandardMaterial3D shader cache."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    fixture = ROOT / "tests/test_material_shader_reuse.gd"
    engine_sha, fixture_sha = digest(args.engine), digest(fixture)
    command = [str(args.engine.resolve()), "--path", str(ROOT), "--script",
               "res://tests/test_material_shader_reuse.gd"]
    report = {"engine_sha256": engine_sha, "fixture_sha256": fixture_sha,
              "command": command, "samples": [], "failures": []}
    names = ("RMMO_STANDARD_SHADER_CACHE_LIMIT", "RMMO_STANDARD_SHADER_CACHE_PROFILE")
    original = {name: os.environ.get(name) for name in names}
    try:
        os.environ[names[1]] = "1"
        for limit in (0, 2, 32, 0):
            tag = f"sample_{len(report['samples'])}_limit_{limit}"
            os.environ[names[0]] = str(limit)
            result = run_background(command, cwd=ROOT, timeout=180)
            (output / (tag + ".log")).write_bytes(result.stdout)
            raw = result.stdout.decode("utf-8", errors="replace")
            checks = re.search(r"MATERIAL_SHADER_CHECKS (\{[^\r\n]+\})", raw)
            rows = re.search(r"MATERIAL_SHADER_REUSE (\[[^\r\n]+\])", raw)
            stats = re.search(r"RMMO_STANDARD_SHADER_CACHE limit=(\d+) created=(\d+) reused=(\d+) evicted=(\d+) unused=(\d+)", raw)
            sample = {"tag": tag, "limit": limit, "exit_code": result.returncode,
                      "checks": json.loads(checks[1]) if checks else {},
                      "rows": json.loads(rows[1]) if rows else [],
                      "stats": dict(zip(("limit", "created", "reused", "evicted", "unused"), map(int, stats.groups()))) if stats else {},
                      "errors": [line for line in raw.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:"))]}
            report["samples"].append(sample)
            valid = (result.returncode == 0 and checks and rows and stats and
                     not sample["errors"] and not sample["checks"].get("failures") and
                     sample["stats"]["limit"] == limit and sample["stats"]["unused"] <= limit)
            if limit and stats:
                valid = valid and sample["stats"]["reused"] > 0 and sample["stats"]["evicted"] > 0
            if not valid:
                report["failures"].append(tag)
            (output / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print(json.dumps({k: v for k, v in sample.items() if k != "rows"}), flush=True)
            if not valid:
                break
    finally:
        for name, value in original.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
    if len(report["samples"]) == 4:
        samples = report["samples"]
        if not all(s["checks"]["image_sha256"] == samples[0]["checks"]["image_sha256"] for s in samples):
            report["failures"].append("render readback differs across cache limits")
        if samples[2]["stats"]["created"] >= min(samples[0]["stats"]["created"], samples[3]["stats"]["created"]):
            report["failures"].append("cache did not reduce actual shader creation work")
    else:
        report["failures"].append("incomplete four-process regression")
    report["source_unchanged"] = digest(fixture) == fixture_sha and digest(args.engine) == engine_sha
    report["ok"] = not report["failures"] and report["source_unchanged"]
    (output / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "failures": report["failures"]}), flush=True)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
