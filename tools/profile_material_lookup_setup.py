"""Freeze the current library and add diagnostics only to an archived copy."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review_artifacts/material_lookup_20261017"
OUT.mkdir(parents=True, exist_ok=True)
BASE = "8ad5e103085199dedfdec838a82a0fb7f27da7fb"
source = subprocess.check_output(["git", "show", f"{BASE}:scripts/world_editor/surface_material_library.gd"], cwd=ROOT)
(OUT / "library_baseline.gd").write_bytes(source)
road = subprocess.check_output(["git", "show", f"{BASE}:scripts/world_editor/road_tools.gd"], cwd=ROOT)
(OUT / "road_baseline.gd").write_bytes(road)
old_token = b"JSON.stringify([settings,data.roads,editor._doc.records,old]).sha256_text()"
new_token = b"JSON.stringify([settings,data.roads,editor._doc.records,old,material,kerb_material]).sha256_text()"
assert road.count(old_token) == 1
(OUT / "road_guarded_baseline.gd").write_bytes(road.replace(old_token, new_token))
text = source.decode().replace("\r\n", "\n")
text = text.replace("var directory: String", "var measurements:Dictionary={}\nvar directory: String", 1)
text = text.replace("\tvar result: Array = [", "\tmeasurements={}\n\tvar total_start:=Time.get_ticks_usec()\n\tvar result: Array = [", 1)
text = text.replace("\treturn result\n", "\tmeasurements.total_us=Time.get_ticks_usec()-total_start\n\treturn result\n", 1)
text = text.replace('\t\tfor pack in preload("res://scripts/world_editor/resource_pack_catalog.gd").new(content_root).packs():', '\t\tvar pack_start:=Time.get_ticks_usec()\n\t\tvar packs:=preload("res://scripts/world_editor/resource_pack_catalog.gd").new(content_root).packs()\n\t\tmeasurements.pack_catalog_us=Time.get_ticks_usec()-pack_start\n\t\tfor pack in packs:')
text = text.replace('\t\tvar value: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))', '\t\tvar read_start:=Time.get_ticks_usec()\n\t\tvar value: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))\n\t\tmeasurements.read_parse_us=int(measurements.get("read_parse_us",0))+Time.get_ticks_usec()-read_start\n\t\tmeasurements.descriptors=int(measurements.get("descriptors",0))+1')
text = text.replace('\t\tif not Paint.material_valid(value.material, false, content_root): continue', '\t\tvar valid_start:=Time.get_ticks_usec()\n\t\tvar valid:=Paint.material_valid(value.material, false, content_root)\n\t\tmeasurements.validation_us=int(measurements.get("validation_us",0))+Time.get_ticks_usec()-valid_start\n\t\tif not valid: continue')
(OUT / "library_profile.gd").write_text(text, encoding="utf-8", newline="\n")
manifest = {"base_commit": BASE, "performance_baseline_adjustment": "road_guarded_baseline differs from frozen road_baseline only by adding selected material and kerb_material definitions to the plan token; both benchmark versions have the same correctness fix.", "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob("*.gd")}}
(OUT / "baseline.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
