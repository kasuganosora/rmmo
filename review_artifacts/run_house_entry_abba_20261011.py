import json
import pathlib
import statistics
import subprocess
import sys

ROOT = pathlib.Path('D:/code/rmmo')
OUT = pathlib.Path('D:/code/rmmo_runtime/review_artifacts')
CHECKPOINT = 'D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf'
rows = []
for label, enabled in [('warm', False), ('a1', False), ('b1', True), ('b2', True), ('a2', False)]:
    output = OUT / ('house_entry_cache_' + label + '_20261011.json')
    log = output.with_suffix('.log')
    command = [sys.executable, str(ROOT / 'tools/run_godot_background.py'), '--timeout', '240', '--log', str(log), '--',
               'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(ROOT), '--script', 'res://tools/profile_game_entry.gd', '--',
               '--map=' + CHECKPOINT, '--output=' + str(output), '--spawn=321.2,0.9,160.3', '--monitor']
    if enabled:
        command.append('--definition-cache')
    result = subprocess.run(command, cwd=ROOT, timeout=260)
    logs = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in logs or '\nERROR:' in logs:
        print(label, 'FAILED', logs[-4000:], flush=True)
        raise SystemExit(1)
    data = json.loads(output.read_text(encoding='utf-8'))
    row = {key: data.get(key) for key in ['entry_ms', 'failures', 'map_sha', 'formal_sha', 'screenshot_avatar_hidden', 'definition_cache']}
    row.update(label=label, enabled=enabled, report=str(output), warnings=[line for line in logs.splitlines() if line.startswith('WARNING:')])
    rows.append(row)
    (OUT / 'house_entry_cache_abba_20261011.json').write_text(json.dumps({'rows': rows, 'scope': 'Fresh process A/B/B/A after one excluded warm-up; same checkpoint/spawn, OS and asset caches not cleared; compare only outer-definition cache, other new fixes identical.'}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(row, ensure_ascii=False), flush=True)
    if row['failures'] or not row['screenshot_avatar_hidden'] or row['map_sha'] != row['formal_sha']:
        raise SystemExit(1)
print('off_mean_ms', statistics.mean(row['entry_ms'] for row in rows if row['label'] in ['a1', 'a2']), flush=True)
print('on_mean_ms', statistics.mean(row['entry_ms'] for row in rows if row['enabled']), flush=True)
