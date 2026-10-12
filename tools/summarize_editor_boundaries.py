"""Verify final boundary acceptance evidence without changing maps or assets."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path('D:/code/rmmo_runtime')
OUT = RUNTIME / 'review_artifacts/editor_boundaries_20261012'
LOGS = [
    'boundaries_guards.log', 'boundaries_structures.log',
    'boundaries_contract_final.log', 'boundaries_final_visual_live.log',
    'boundaries_interaction.log', 'boundaries_terrain_final.log',
    'boundaries_bridge_visual_live.log', 'boundaries_bridge_lift_final.log',
    'boundaries_crop_batch_final_live.log', 'boundaries_crop_lod_final_live.log',
    'boundaries_runtime_final.log', 'boundaries_publish_live.log',
]
NAMES = {
    'road_bridges.gd', 'bridge_road_tools.gd', 'bridge_road_cut.gd',
    'bridge_panel.gd', 'road_plan.gd', 'road_tools.gd',
    'fortification_plan.gd', 'fortification_data.gd', 'fortification_ring.gd',
    'fortification_tools.gd', 'fortification_panel.gd',
    'terrain_river_layer.gd', 'terrain_river_tools.gd', 'terrain_river_panel.gd',
    'terrain_stroke_batch.gd', 'terrain_follow_tools.gd', 'terrain_tools.gd',
    'terrain_brush.gd', 'city_layout.gd', 'mcp_schema.gd', 'mcp_ops.gd',
    'model_lod_preparation.gd',
}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
results, maps = [], {}
for name in LOGS:
    path = RUNTIME / name
    lines = path.read_text(encoding='utf-8').splitlines()
    failures = [s for s in lines if s.startswith(('FAIL', 'ERROR:', 'SCRIPT ERROR'))]
    ending = [s for s in lines if 'FINISHED' in s or 'CROPS_PUBLISHED' in s]
    results.append(dict(log=str(path), sha256=sha(path),
                        pass_lines=sum(s.startswith('PASS') for s in lines),
                        failures=failures, completion=ending))
    for line in lines:
        if '_ARTIFACTS D:' in line:
            folder = Path('D:' + line.split('_ARTIFACTS D:', 1)[1])
            map_path = folder / 'map.gltf'
            if map_path.is_file():
                maps[str(map_path)] = sha(map_path)
published = json.loads((OUT / 'crops_published.json').read_text(encoding='utf-8'))
for item in published:
    asset = Path(item['entry']['asset_path'])
    assert sha(asset) == item['sha256'], f'Published source changed: {asset}'
    assert Path(item['entry']['thumbnail_path']).is_file()
formal = RUNTIME / 'maps/medieval_river_town/map.gltf'
report = dict(
    scope='Six functional boundaries; historical skipped performance work unchanged.',
    source_hashes={str(p.relative_to(ROOT)): sha(p) for p in sorted((ROOT/'scripts').rglob('*.gd')) if p.name in NAMES},
    formal_map_sha256=sha(formal), tests=results, fixture_map_hashes=maps,
    pass_lines_note='Assertions across overlapping integration and visual reruns, not independent scenarios.',
    crop_assets=published,
    crop_render=json.loads((OUT/'crops/render.json').read_text(encoding='utf-8')),
    crop_pixel_comparison=json.loads((OUT/'crops/pixel_comparison.json').read_text(encoding='utf-8')),
)
(OUT/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
assert report['formal_map_sha256'] == 'a2808a3fc088c601c4a5913ec8f97ea7603b4de49858c29ff7bd742861696f44'
assert all(not r['failures'] and r['completion'] for r in results)
assert all('failures=0' in s or 'CROPS_PUBLISHED' in s for r in results for s in r['completion'])
print(f'BOUNDARIES_VERIFIED suites={len(results)} pass_lines={sum(r["pass_lines"] for r in results)} source_files={len(report["source_hashes"])}')
for result in results:
    print(Path(result['log']).name, result['pass_lines'], result['completion'][-1])
