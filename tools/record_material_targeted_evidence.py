"""Bind this batch's validation, frozen baseline, probes and timings to source bytes."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = Path("D:/code/rmmo_runtime/review_artifacts/material_targeted_20261017")
OUT = ROOT / "review_artifacts/material_targeted_20261017"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def identity(path):
    data = path.read_bytes()
    return {"sha256": sha(data), "bytes": len(data)}

baseline = json.loads((OUT/"baseline.json").read_text(encoding="utf-8"))
for name, digest in baseline["files"].items():
    data = (OUT/name).read_bytes()
    assert sha(data) == digest, name
    original_name = name.removesuffix("_baseline.gd") + ".gd"
    assert data == subprocess.check_output(["git", "show", baseline["commit"]+":scripts/world_editor/"+original_name], cwd=ROOT)
profile = json.loads((OUT/"profile_manifest.json").read_text(encoding="utf-8"))
for version, entry in profile["files"].items():
    assert sha((ROOT/entry["source"]).read_bytes()) == entry["source_sha256"]
    assert sha((OUT/f"library_{version}_profile.gd").read_bytes()) == entry["profile_sha256"]

sources = {}
paths = [p for folder in ("scripts/world_editor", "scripts/world3d", "scripts/asset") for p in (ROOT/folder).rglob("*.gd")]
paths += [p for p in (ROOT/"tools").iterdir() if "material_targeted" in p.name or p.name in ("test_material_lookup_targeted.gd", "freeze_targeted_material_lookup.py")]
paths += [ROOT/"tools"/name for name in ("road_prepare_fixture.gd", "test_road_prepare_differential.gd", "test_road_projection_reuse.gd", "test_road_prepare_district_http.gd", "test_residential_placement_http.gd", "test_terrain_catalog_scope.gd", "run_godot_background.py")]
paths += [ROOT/"project.godot"]
for path in paths:
    if path.suffix not in (".gd", ".py", ".godot"): continue
    sources[path.relative_to(ROOT).as_posix()] = {**identity(path), "sha256_lf": sha(path.read_bytes().replace(b"\r\n", b"\n"))}

reports = {}
for name in ("targeted_tests", "roads", "cpu", "ui", "work_counts", "district", "residential"):
    value = json.loads((RAW/(name+".json")).read_text(encoding="utf-8"))
    assert value["failures"] == 0, name
    reports[name] = {"checks": len(value["checks"]), "failures": 0, "skipped": value.get("skipped", []), **identity(RAW/(name+".json"))}
    for path, digest in value.get("sources", value.get("script_sha256", {})).items():
        if path.startswith("res://"):
            assert sha((ROOT/path.removeprefix("res://")).read_bytes()) == digest, (name, path)
catalog_log = (RAW/"catalog.log").read_text(encoding="utf-8")
assert "TERRAIN_CATALOG_FAILED=0" in catalog_log and "FAIL:" not in catalog_log
reports["catalog"] = {"checks": sum(line.startswith("PASS:") for line in catalog_log.splitlines()), "failures": 0, **identity(RAW/"catalog.log")}
resources = json.loads((RAW/"cpu.json").read_text(encoding="utf-8"))["resources"]
for path, digest in resources.items():
    assert sha(Path(path).read_bytes()) == digest, ("texture changed since timed CPU run", path)
for name in ("comparison.json", "work_counts.json", "targeted_tests.json"):
    (OUT/name).write_bytes((RAW/name).read_bytes())

data = {"baseline": baseline, "profile": profile,
        "source_parent": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "production_diff": subprocess.check_output(["git", "diff", "HEAD", "--", "scripts"], cwd=ROOT, text=True, encoding="utf-8"),
        "sources": sources, "reports": reports, "texture_sha256_rechecked_at_archival": resources,
        "artifacts": {p.as_posix(): identity(p) for p in RAW.rglob("*") if p.is_file()},
        "limits": [
            "Only native find_many takes the targeted path. Scalar find, full listings and custom subclasses retain original traversal behavior.",
            "Every call still enumerates names and shared pack identities. Conservative JSON-count or directory-budget fallback adds preflight work before the original full catalog traversal; no universal speedup claim.",
            "Selected descriptor definitions retain the preceding batch's token guard. No same-path texture-byte SHA version lock, persistent validated-file cache or cross-request index was added.",
            "Initial targeted test had one environment failure creating a Windows file symlink. It is retained; final test explicitly skips that unavailable fixture. Mandatory directory-junction replacement rejection passed. No file-symlink runtime proof is claimed.",
            "Frozen road/library baseline is exactly commit 7be7f41. Broader direct projection comparisons inherit the previous unchanged projection references, identified in roads.json.",
            "Work counters instrument archived copies only. Exact-script identity points to each copy itself, so the native fast path is measured; all outputs are compared to uninstrumented native code. These counts are not OFF timings.",
            "A/A and all slower observations retained. Measurements ran serially on a private Windows desktop where applicable, with other user/session load unmanaged. No cold, percentile, significance, FPS, whole-city or RSS/VRAM claim.",
            "Only isolated checkout and disposable maps/packs changed. No scene-building checkout, formal map/model or export writes. No unrelated interior or whole-city traversal revalidation."
        ]}
(OUT/"evidence.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"reports": {k:{f:v for f,v in r.items() if f in ("checks", "failures")} for k,r in reports.items()}, "source_files": len(sources), "artifacts": len(data["artifacts"])}, ensure_ascii=False))
