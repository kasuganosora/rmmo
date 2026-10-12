"""Collect this review's evidence separately from the original delivery tests."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path('D:/code/rmmo_runtime')
OUT = RUNTIME / 'review_artifacts/editor_boundaries_review_20261012'
LOGS = {
    'review_structure_boundary_guards.log': 'STRUCTURE_BOUNDARY_REVIEW_FINISHED failures=0',
    'review_structure_bridge_http_final.log': 'SLOPED_BRIDGE_FINISHED failures=0',
    'review_structure_bridge_gpu_live.log': 'SLOPED_BRIDGE_FINISHED failures=0',
    'river_boundary_review.log': 'RIVER_BOUNDARY_REVIEW_FINISHED failures=0',
    'river_material_save_review.log': 'RIVER_MATERIAL_SAVE_REVIEW_FINISHED failures=0',
    'terrain_follow_review.log': 'TERRAIN_FOLLOW_REVIEW_FINISHED failures=0',
    'terrain_follow_review_interaction_final.log': 'BOUNDARY_INTERACTION_FINISHED failures=0',
    'water_crown_follow_review_gpu.log': 'WATER_CROWN_REVIEW_FINISHED failures=0',
    'crop_boundary_review_gpu_final_live.log': 'CROP_BOUNDARY_REVIEW_FINISHED failures=0',
    'review_crop_http_gpu_live.log': 'CROP_EXTENSIONS_FINISHED failures=0',
    'review_lod_retention_headless.log': 'BRIDGE_LOD_RETENTION passed=33 failures=0',
    'review_ground_cpu_final.log': 'CPU_MESH_PASS',
    'review_ground_batch_lifetime_final.log': 'GROUND_BATCH_LIFETIME PASS',
    'review_extensions_runtime_final.log': 'EXTENSIONS_RUNTIME_FINISHED failures=0',
}
FILES = [
    'scripts/world3d/road_bridges.gd', 'scripts/world3d/road_plan.gd',
    'scripts/world_editor/bridge_road_tools.gd', 'scripts/world_editor/bridge_road_cut.gd',
    'scripts/world3d/terrain_river_layer.gd', 'scripts/world_editor/terrain_river_tools.gd',
    'scripts/world_editor/terrain_river_panel.gd', 'scripts/world3d/world_document.gd',
    'scripts/world3d/terrain_stroke_batch.gd', 'scripts/world_editor/terrain_brush.gd',
    'scripts/world3d/fortification_terrain.gd', 'scripts/world3d/fortification_art.gd',
    'scripts/world3d/ground_cpu_mesh.gd', 'scripts/world3d/ground_batcher.gd',
    'scripts/world3d/vegetation_render.gd', 'scripts/world_editor/mcp_schema.gd',
    'tools/test_structure_boundary_review.gd', 'tools/test_sloped_road_bridge.gd',
    'tools/test_river_boundary_review.gd', 'tools/test_river_material_save_review.gd',
    'tools/test_terrain_follow_review.gd', 'tools/test_water_crown_follow_review.gd',
    'tools/test_crop_boundary_review.gd',
]
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
tests, maps = [], {}
for name, marker in LOGS.items():
    path = RUNTIME / name
    lines = path.read_text(encoding='utf-8').splitlines()
    failures = [line for line in lines if re.match(r'^(FAIL\b|ERROR:|SCRIPT ERROR:)', line)]
    warnings = [line for line in lines if line.startswith('WARNING:')]
    completion = [line for line in lines if marker in line]
    tests.append(dict(log=str(path), sha256=sha(path),
                      pass_lines=sum(bool(re.match(r'^PASS\b', line)) for line in lines),
                      failures=failures, warnings=warnings, completion=completion))
    assert completion and not failures and not warnings, (name, failures, warnings, completion)
    for line in lines:
        if '_ARTIFACTS D:' in line:
            folder = Path('D:' + line.split('_ARTIFACTS D:', 1)[1])
            map_path = folder / 'map.gltf'
            if map_path.is_file(): maps[str(map_path)] = sha(map_path)
formal = RUNTIME / 'maps/medieval_river_town/map.gltf'
assert sha(formal) == 'a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44'
report = dict(
    scope='Correctness review of the six editor boundaries and directly affected resource lifecycle.',
    note='Checks include overlapping HTTP/GPU regression cases, not independent scenarios. CPU_MESH_PASS is a suite receipt rather than a PASS line.',
    tests=tests, pass_lines=sum(test['pass_lines'] for test in tests),
    source_hashes={name: sha(ROOT / name) for name in FILES},
    fixture_map_hashes=maps, formal_map_sha256=sha(formal),
    model_reports={name: sha(OUT / name) for name in ['structure_review.json', 'water_crown_review.json']},
    retained_performance_boundary='Existing frozen fortification merge uses base geometry only; procedural Art.build LOD retention does not establish merged-fortification LOD or performance gains. Historical skipped performance work remains skipped.',
)
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'EDITOR_BOUNDARY_REVIEW_VERIFIED suites={len(tests)} pass_lines={report["pass_lines"]} failures=0 warnings=0')
for test in tests: print(Path(test['log']).name, test['pass_lines'], test['completion'][-1])
