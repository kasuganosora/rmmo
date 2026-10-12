import json
import subprocess
import sys
from pathlib import Path

REPORT = Path('D:/code/rmmo_runtime/review_artifacts/loading_path_20261010')
MAP = 'D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf'
cold = '--cold' in sys.argv
warmup = '--warmup' in sys.argv
runs = [('warmup', True)] if warmup else [('old_a', False), ('new_a', True), ('new_b', True), ('old_b', False)]
REPORT.mkdir(parents=True, exist_ok=True)
for name, enabled in runs:
    name = ('rebuild_' if cold else 'warm_') + name
    args = [sys.executable, 'tools/profile_load_hardware.py', '--timeout', '180',
            '--log', str(REPORT / (name + '.log')), '--hardware', str(REPORT / (name + '.hardware.json')),
            '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', 'D:/code/rmmo',
            '--script', 'res://tools/profile_game_entry.gd', '--', '--map=' + MAP,
            '--spawn=321.2,0.9,160.3', '--monitor', '--output=' + str(REPORT / (name + '.json'))]
    if not enabled:
        args += ['--without-index-path-batching', '--without-cpu-river-overrides']
    if cold:
        args.append('--reset-derived-cache')
    print('START', name, flush=True)
    subprocess.run(args, cwd='D:/code/rmmo', check=True)
    data = json.loads((REPORT / (name + '.json')).read_text(encoding='utf-8'))
    print('RESULT', name, data['entry_ms'], data['failures'], flush=True)
    if data['failures']:
        raise SystemExit('Probe failed')
