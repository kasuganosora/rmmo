"""Collect validated road preparation A/B evidence without touching any map."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = Path("D:/code/rmmo_runtime/review_artifacts/road_record_prepare_completed_20261017")
OUT = ROOT / "review_artifacts/road_record_prepare_20261017"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def identity(path):
    return {"sha256": sha(path.read_bytes()), "bytes": path.stat().st_size}


baseline = json.loads((OUT / "baseline.json").read_text(encoding="utf-8"))
original = subprocess.check_output(["git", "show", baseline["commit"] + ":" + baseline["path"]], cwd=ROOT)
assert original == (OUT / "road_tools_baseline.gd").read_bytes()
assert sha(original) == baseline["sha256"]
reports = {}
for name in ("remeasure_ui", "validation", "roads", "cpu", "ui", "district", "residential", "comparison"):
    data = json.loads((RAW / f"{name}.json").read_text(encoding="utf-8"))
    assert data["failures"] == 0 and data["checks"] and all(c["ok"] for c in data["checks"]), name
    reports[name] = {"checks": len(data["checks"]), "failures": 0, **identity(RAW / f"{name}.json")}
    for path, digest in data.get("sources", data.get("script_sha256", {})).items():
        if not path.startswith("res://"):
            continue
        if name == "remeasure_ui" and path == "res://scripts/world_editor/road_tools.gd":
            assert digest in (sha(original), sha(original.replace(b"\n", b"\r\n"))), path
        else:
            assert sha((ROOT / path.removeprefix("res://")).read_bytes()) == digest, (name, path)
    (OUT / f"{name}.json").write_bytes((RAW / f"{name}.json").read_bytes())
attribution = json.loads((RAW / "attribution.json").read_text(encoding="utf-8"))
assert attribution["failures"] == 0 and len(attribution["samples"]) == 6 and all(s["same"] for s in attribution["samples"])
(OUT / "attribution.json").write_bytes((RAW / "attribution.json").read_bytes())

cpu = json.loads((RAW / "cpu.json").read_text(encoding="utf-8"))
for path, digest in cpu["resources"].items():
    assert sha(Path(path).read_bytes()) == digest, path
ui = json.loads((RAW / "ui.json").read_text(encoding="utf-8"))
comparison = json.loads((RAW / "comparison.json").read_text(encoding="utf-8"))
for name, digest in comparison["inputs"].items():
    assert sha((RAW / f"{name}.json").read_bytes()) == digest, name
assert len({s["author_sha256"] for s in ui["samples"]}) == 1
assert all(s["publication"]["ok"] and s["publication"]["batch_stats"]["pending_groups"] == 0 for s in ui["samples"])

sources = {}
for folder in ("scripts/world_editor", "scripts/world3d", "scripts/asset"):
    for path in (ROOT / folder).rglob("*.gd"):
        sources[path.relative_to(ROOT).as_posix()] = {**identity(path), "sha256_lf": sha(path.read_bytes().replace(b"\r\n", b"\n"))}
for path in list((ROOT / "tools").glob("*road_record*")) + [ROOT / "tools" / name for name in ("test_road_material_validation.gd", "road_prepare_fixture.gd", "test_road_prepare_differential.gd", "test_road_projection_reuse.gd", "test_road_prepare_district_http.gd", "test_residential_placement_http.gd", "run_godot_background.py")] + [ROOT / "project.godot"]:
    if path.suffix in (".gd", ".py", ".godot"):
        sources[path.relative_to(ROOT).as_posix()] = {**identity(path), "sha256_lf": sha(path.read_bytes().replace(b"\r\n", b"\n"))}

logs = {}
for path in RAW.glob("*.log"):
    text = path.read_text(encoding="utf-8-sig")
    assert not any(token in text for token in ("SCRIPT ERROR", "ERROR:", "WARNING:", "FAIL ", "FAIL:")), path
    normalized = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    saved = OUT / path.name
    saved.write_text(normalized, encoding="utf-8", newline="\n")
    logs[path.name] = {"raw": identity(path), "archive": identity(saved), "normalization": "UTF-8 LF, trailing line spaces stripped; no diagnostic lines removed"}

data = {
    "created_utc": datetime.now(timezone.utc).isoformat(), "baseline": baseline,
    "source_parent": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
    "production_diff": subprocess.check_output(["git", "diff", "HEAD", "--", "scripts"], cwd=ROOT, text=True, encoding="utf-8"),
    "sources": sources, "reports": reports, "logs": logs,
    "total_checks": sum(r["checks"] for r in reports.values()), "failures": 0,
    "attribution_exact_output_observations": len(attribution["samples"]),
    "resources_rechecked": cpu["resources"],
    "artifacts": {path.name: identity(path) for path in OUT.iterdir() if path.is_file() and path.name != "evidence.json"},
    "raw_artifacts": {str(path): identity(path) for path in RAW.iterdir() if path.is_file()},
    "limits": [
        "W0-E remeasurement selected one bounded T1 hotspot. Mesh/shape publication was measured as part of callback-to-ready, but its implementation is unchanged; no claim that all publication bottlenecks are solved.",
        "Cache lifetime is a single synchronous prepare; there are no awaits or external file writes in that operation. Each preview, apply and nested candidate validates anew. Same-path texture byte edits are not newly version-locked.",
        "Full return/author bytes match the current b04623f baseline. All helper sources are shared and identified; counters and attribution copies are excluded from OFF timings.",
        "12 alternating A/B pairs and 4 A/A pairs, all slower samples retained. CPU has two warmups/version and UI one. Other user/session load is uncontrolled. No cold-OS, percentile, statistical significance, GPU/FPS, town-wide, RSS or VRAM claim.",
        "Actual UI apply-to-ready includes editor road nodes, picking bodies, settled shared batches, two physics frames and a later rendered frame. It is not gameplay or photon latency.",
        "Temporary native maps and packs only. Scene-building worktree, authored assets and formal maps are untouched. No new model or art change requiring model review."
    ]
}
(OUT / "evidence.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"total_checks": data["total_checks"], "failures": 0, "reports": {n: r["checks"] for n, r in reports.items()}}, ensure_ascii=False))
