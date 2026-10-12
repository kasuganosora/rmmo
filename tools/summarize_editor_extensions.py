"""Collect reproducible identities and actual test outcomes; never modifies maps."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path('D:/code/rmmo_runtime')
OUT = RUNTIME / 'review_artifacts/editor_extensions_20261012'
NAMES = {
    'terrain_stroke_batch.gd', 'terrain_volume.gd', 'terrain_volume_tools.gd',
    'terrain_projection.gd', 'terrain_follow_tools.gd', 'terrain_river_tools.gd',
    'spline_route.gd', 'fortification_spline.gd', 'fortification_terrain.gd',
    'fortification_ring.gd', 'water_gate_mesh.gd', 'fortification_tools.gd',
    'structure_prefab.gd', 'bridge_mesh.gd', 'bridge_data.gd', 'bridge_tools.gd',
    'terrain_plant_support.gd', 'vegetation_scatter.gd', 'vegetation_render.gd',
    'scatter_tools.gd', 'ground_batcher.gd', 'ground_batch_geometry.gd',
    'world_document.gd', 'map_loader.gd', 'runtime_mesh_cache.gd',
}
files = sorted(p for p in (ROOT / 'scripts').rglob('*.gd') if p.name in NAMES)
logs = [
    'terrain_extensions_guards_live.log', 'structure_extensions_bed_live.log',
    'crop_extensions_wind_live.log', 'extensions_runtime_live.log',
    'extensions_structure_prefab_regression.log', 'extensions_batch_regression.log',
    'fort_visual_extensions_live.log',
]
results = []
for name in logs:
    text = (RUNTIME / name).read_text(encoding='utf-8')
    failures = [s for s in text.splitlines() if s.startswith(('FAIL', 'ERROR:', 'SCRIPT ERROR'))]
    ending = [s for s in text.splitlines() if 'FINISHED' in s or 'LIFETIME PASS' in s]
    results.append(dict(log=name, pass_lines=sum(s.startswith('PASS') for s in text.splitlines()), failures=failures, completion=ending))
formal = RUNTIME / 'maps/medieval_river_town/map.gltf'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
report = dict(source_hashes={str(p.relative_to(ROOT)):sha(p) for p in files},
              formal_map_sha256=sha(formal), tests=results)
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
assert report['formal_map_sha256'] == 'a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44'
assert all(not r['failures'] and r['completion'] for r in results)
print(f'EXTENSIONS_VERIFIED suites={len(results)} pass_lines={sum(r["pass_lines"] for r in results)} source_files={len(files)}')
