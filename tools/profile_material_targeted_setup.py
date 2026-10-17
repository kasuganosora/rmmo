"""Instrument archived copies; production and timed benchmarks stay unmodified."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "review_artifacts/material_targeted_20261017"
sources = {
    "baseline": OUT / "surface_material_library_baseline.gd",
    "current": ROOT / "scripts/world_editor/surface_material_library.gd",
}
manifest = {}
for version, source in sources.items():
    original = source.read_bytes()
    text = original.decode().replace("\r\n", "\n")
    text = text.replace("var directory: String", "static var descriptors_read := 0\nvar directory: String", 1)
    needle = "var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))"
    indent = "\t\t" if version == "baseline" else "\t"
    assert text.count(needle) == 1
    text = text.replace(indent + needle, indent + "descriptors_read += 1\n" + indent + needle)
    filename = f"library_{version}_profile.gd"
    if version == "current":
        original_guard = 'load("res://scripts/world_editor/surface_material_library.gd")'
        assert text.count(original_guard) == 1
        text = text.replace(original_guard, f'load("res://review_artifacts/material_targeted_20261017/{filename}")')
    output = OUT / filename
    output.write_text(text, encoding="utf-8", newline="\n")
    manifest[version] = {"source": source.relative_to(ROOT).as_posix(),
                         "source_sha256": hashlib.sha256(original).hexdigest(),
                         "profile_sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
(OUT / "profile_manifest.json").write_text(json.dumps({"files": manifest,
    "changes": "Read counter only; current copy's exact-script identity guard points to that same archived copy. No subclass bypass. Diagnostic counts, never OFF timings."}, indent=2), encoding="utf-8")
