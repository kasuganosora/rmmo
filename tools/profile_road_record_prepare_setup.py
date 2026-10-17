"""Verify frozen diagnostic adapters and bind their bytes to this measured slice."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review_artifacts/road_record_prepare_20261017"
COMMIT = "b04623f0eb7ac9efefefb23b68c8a964ee55f977"


def sha(data):
    return hashlib.sha256(data).hexdigest()


baseline = (OUT / "road_tools_baseline.gd").read_bytes()
assert baseline == subprocess.check_output(["git", "show", COMMIT + ":scripts/world_editor/road_tools.gd"], cwd=ROOT)
(OUT / "baseline.json").write_text(json.dumps({"commit": COMMIT, "path": "scripts/world_editor/road_tools.gd", "sha256": sha(baseline)}, indent=2) + "\n", encoding="utf-8")

paint = (ROOT / "scripts/world3d/surface_materials.gd").read_text(encoding="utf-8")
count = paint.replace("static func material_valid(", "static var material_visits:=0\nstatic var material_cache_hits:=0\nstatic var material_path_checks:=0\n\nstatic func material_valid(", 1)
count = count.replace("\t# Callers may share", "\tmaterial_visits+=1\n\t# Callers may share", 1)
count = count.replace("if validation_cache.has(cache_key): return true", "if validation_cache.has(cache_key):material_cache_hits+=1;return true", 1)
count = count.replace("\t\tif not Paths.allowed(path,content_root)", "\t\tmaterial_path_checks+=1\n\t\tif not Paths.allowed(path,content_root)", 1)
assert count == (OUT / "surface_materials_count.gd").read_text(encoding="utf-8")

manifest = {"surface_materials": {"source_sha256": sha((ROOT / "scripts/world3d/surface_materials.gd").read_bytes()), "copy_sha256": sha((OUT / "surface_materials_count.gd").read_bytes())}}
for version, source in (("baseline", OUT / "road_tools_baseline.gd"), ("current", ROOT / "scripts/world_editor/road_tools.gd")):
    copy = OUT / f"road_tools_{version}_count.gd"
    assert copy.read_text(encoding="utf-8") == source.read_text(encoding="utf-8").replace("res://scripts/world3d/surface_materials.gd", "res://review_artifacts/road_record_prepare_20261017/surface_materials_count.gd")
    manifest[version] = {"source_sha256": sha(source.read_bytes()), "copy_sha256": sha(copy.read_bytes())}
(OUT / "count_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print("Frozen baseline and counter adapters match their declared production sources")
