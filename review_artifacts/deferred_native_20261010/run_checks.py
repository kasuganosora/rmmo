import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
GPU = {'test_collision_face_prefetch', 'test_prepared_collision_faces', 'test_loading_collision_preparation', 'test_terrain_collision_slices', 'test_collision_basis_preparation', 'test_deferred_native_preparation_gpu', 'test_deferred_asset_scene', 'test_deferred_reuse_final_verification',
       'test_model_parse_preparation_gpu', 'test_transfer_loading_gpu', 'test_reference_map_http'}
NAMES = ['test_collision_face_prefetch', 'test_prepared_collision_faces', 'test_loading_collision_preparation', 'test_terrain_collision_slices', 'test_collision_basis_preparation', 'test_deferred_native_admission', 'test_resource_admission', 'test_model_parse_preparation', 'test_native_source_retry',
         'test_deferred_native_preparation_gpu', 'test_deferred_asset_scene', 'test_deferred_asset_quiesce',
         'test_deferred_cached_source', 'test_deferred_reuse_admission', 'test_deferred_reuse_final_verification',
         'test_deferred_demand_scope', 'test_deferred_ready_progress', 'test_deferred_loading_workers',
         'test_deferred_loading_budget', 'test_deferred_entry_prefetch', 'test_deferred_admission_priority',
         'test_model_parse_preparation_gpu', 'test_transfer_loading_gpu', 'test_reference_map_http']
results = json.loads((ROOT / 'validation.json').read_text(encoding='utf-8')) if (ROOT / 'validation.json').exists() else []
for name in NAMES:
    if len(sys.argv) > 1 and name not in sys.argv[1:]:
        continue
    engine = ['D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo']
    if name not in GPU:
        engine.append('--headless')
    engine += ['--script', 'res://tools/' + name + '.gd']
    if name == 'test_reference_map_http':
        engine += ['--', '--compiled-assets', '--output=D:/code/rmmo_runtime/review_artifacts/deferred_native_20261010/reference_http.json']
    print('START', name, flush=True)
    run = subprocess.run([sys.executable, 'tools/run_godot_background.py', '--timeout', '240',
                          '--log', str(ROOT / (name + '.log')), '--', *engine], cwd='D:/code/rmmo')
    log = (ROOT / (name + '.log')).read_text(encoding='utf-8', errors='replace')
    row = dict(test=name, exit=run.returncode, passes=len(re.findall(r'^PASS[: ]', log, re.M)),
               failures=len(re.findall(r'^FAIL[: ]', log, re.M)), errors=len(re.findall(r'^(?:SCRIPT )?ERROR:', log, re.M)))
    row['expected_errors'] = 0
    if name == 'test_deferred_asset_scene' and 'PASS: bad source yields no publishable node' in log:
        bad = log.split('EXPECTED_BAD_SOURCE_BEGIN', 1)[-1].split('EXPECTED_BAD_SOURCE_END', 1)[0]
        allowed = ['ERROR: glTF: Error parsing .gltf JSON data: Expected', 'ERROR: Condition "err != OK" is true. Returning: err']
        row['expected_errors'] = sum(any(line.startswith(prefix) for prefix in allowed) for line in bad.splitlines())
    row['unexpected_errors'] = row['errors'] - row['expected_errors']
    results = [x for x in results if x['test'] != name] + [row]
    (ROOT / 'validation.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(row, flush=True)
    if row['exit'] or row['failures'] or row['unexpected_errors']:
        raise SystemExit('Validation failed')
