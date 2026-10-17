"""Record final source and raw result identities; never replace earlier evidence."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = Path("D:/code/rmmo_runtime/review_artifacts/material_lookup_20261017")
OUT = ROOT / "review_artifacts/material_lookup_20261017"
def sha(data): return hashlib.sha256(data).hexdigest()
def identity(path):
    data = path.read_bytes()
    return {"sha256": sha(data), "bytes": len(data)}

baseline = json.loads((OUT/"baseline.json").read_text(encoding="utf-8"))
for name, value in baseline["files"].items():
    assert sha((OUT/name).read_bytes()) == value, name
for source, frozen in (("road_tools", "road_baseline"), ("surface_material_library", "library_baseline")):
    original = subprocess.check_output(["git", "show", baseline["base_commit"]+f":scripts/world_editor/{source}.gd"], cwd=ROOT)
    assert original == (OUT/(frozen+".gd")).read_bytes()
assert (OUT/"road_guarded_baseline.gd").read_bytes() == (OUT/"road_baseline.gd").read_bytes().replace(
    b"JSON.stringify([settings,data.roads,editor._doc.records,old]).sha256_text()",
    b"JSON.stringify([settings,data.roads,editor._doc.records,old,material,kerb_material]).sha256_text()")
sources = {}
for folder in ("scripts/world_editor", "scripts/world3d", "scripts/asset"):
    for path in (ROOT/folder).rglob("*.gd"):
        data = path.read_bytes()
        sources[path.relative_to(ROOT).as_posix()] = {**identity(path), "sha256_lf": sha(data.replace(b"\r\n", b"\n"))}
for path in list((ROOT/"tools").glob("*material_lookup*"))+[ROOT/"project.godot"]:
    if path.suffix not in (".gd", ".py", ".godot"): continue
    sources[path.relative_to(ROOT).as_posix()] = {**identity(path), "sha256_lf":sha(path.read_bytes().replace(b"\r\n",b"\n"))}
reports = {}
for name in ("batch_tests", "cpu", "ui", "district", "residential"):
    value = json.loads((RAW/(name+".json")).read_text(encoding="utf-8"))
    assert value["failures"] == 0, name
    reports[name] = {"checks":len(value["checks"]), "failures":value["failures"]}
roads_path = Path("D:/code/rmmo_runtime/review_artifacts/road_projection_20261017/material_lookup_guarded.json")
roads = json.loads(roads_path.read_text(encoding="utf-8"))
assert roads["failures"] == 0
reports["roads"] = {"checks":len(roads["checks"]), "failures":0, "path":roads_path.as_posix(), **identity(roads_path),
                    "comparison":"Full inherited terrain/road matrix; road comparisons use road_guarded_baseline, direct projection comparisons retain the prior frozen projection baseline. See test_material_lookup_roads.gd override."}
data = {"baseline":baseline,"source_parent":subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip(),
        "production_diff":subprocess.check_output(["git","diff","HEAD","--","scripts"],cwd=ROOT,text=True,encoding="utf-8"),
        "sources":sources,"reports":reports,
        "artifacts":{p.as_posix():identity(p) for p in RAW.rglob("*") if p.is_file()},
        "limits":["Only road preparation batches its selected IDs; other find callers and full catalog listing are unchanged. Selected descriptor definitions now participate in preview tokens; same-path texture-byte SHA identity is not added.",
                  "Catalog scan/validation still executes once per preparation; no targeted filesystem index or persistent cache.",
                  "Private GPU desktop; disposable maps/packs only. No scene-building checkout, formal asset, model geometry or export changes.",
                  "Initial batch_tests_initial: one invalid unsplit junction fixture made single-material prepare reject before lookup; corrected to a legal straight road.",
                  "batch_tests.log: intermediate harness parse failure, replaced by batch_tests_final.log; no production change.",
                  "batch_guarded.log: duplicate temporary variable name in test harness caused parse failure, corrected in batch_guarded_final.log (80/0).",
                  "cpu_initial plain control inherited builtin:white; retained as builtin-only historical observation. Final cpu explicitly clears material_id and records every request and result SHA.",
                  "ui_initial: 466 passes/3 failures exposed existing missing descriptor identity in road plan_token. Performance is not used as final validation. Both final benchmark versions include the descriptor-token correction; original 8ad5e10 source is retained separately.",
                  "A/A and all slower samples retained. Other sessions/system load unmanaged; no cold, percentile, statistical-significance or whole-city claim."]}
(OUT/"evidence.json").write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"reports":reports,"source_files":len(sources),"artifacts":len(data["artifacts"])},ensure_ascii=False))
