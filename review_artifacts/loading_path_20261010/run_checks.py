import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
NAMES = [
    ('test_index_path_batch', False), ('test_map_dependency_index', False),
    ('test_dependency_index_proof', False), ('test_chunk_reference_preparation', False),
    ('test_road_dependency_index', False), ('test_structure_dependency_index', False),
    ('test_cpu_river_materials_gpu', True), ('test_transfer_loading_gpu', True),
    ('test_reference_map_http', True), ('test_editor_terrain_texture_scope', True),
]
results = json.loads((ROOT / 'validation.json').read_text(encoding='utf-8')) if (ROOT / 'validation.json').exists() else []
for name, gpu in NAMES:
    if len(sys.argv) > 1 and name not in sys.argv[1:]:
        continue
    engine = ['D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo']
    if not gpu:
        engine.append('--headless')
    engine += ['--script', 'res://tools/' + name + '.gd']
    if name == 'test_reference_map_http':
        engine += ['--', '--compiled-assets', '--output=D:/code/rmmo_runtime/review_artifacts/loading_path_20261010/reference_http.json']
    print('START', name, flush=True)
    run = subprocess.run([sys.executable, 'tools/run_godot_background.py', '--timeout', '240',
                          '--log', str(ROOT / (name + '.log')), '--', *engine], cwd='D:/code/rmmo')
    log = (ROOT / (name + '.log')).read_text(encoding='utf-8', errors='replace')
    row = dict(test=name, exit=run.returncode, passes=len(re.findall(r'^PASS[: ]', log, re.M)),
               failures=len(re.findall(r'^FAIL[: ]', log, re.M)), errors=len(re.findall(r'^(?:SCRIPT )?ERROR:', log, re.M)))
    # This fixture deliberately overwrites color.png with invalid bytes. Keep
    # all engine error counts visible; only classify the known decoder trio.
    row['expected_errors'] = 0
    if name == 'test_editor_terrain_texture_scope' and 'PASS: existing but corrupt PNG cannot reuse old texture or shader' in log:
        patterns = [r'ERROR: Condition "!success" is true\. Returning: ERR_FILE_CORRUPT',
                    r"ERROR: Error loading image: 'D:/code/rmmo_runtime/cache/world3d/terrain_texture_scope_[0-9]+/color\.png'\.",
                    r'ERROR: Failed to load image\. Error 16']
        row['expected_errors'] = sum(bool(any(re.fullmatch(p, line) for p in patterns)) for line in log.splitlines())
    row['unexpected_errors'] = row['errors'] - row['expected_errors']
    results = [x for x in results if x['test'] != name] + [row]
    (ROOT / 'validation.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(row, flush=True)
    if row['exit'] or row['failures'] or row['unexpected_errors']:
        raise SystemExit('Validation failed')
