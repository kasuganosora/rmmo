"""Sequential private-desktop runs; no concurrent scene benchmarks."""
import subprocess
import sys
from pathlib import Path

root = Path('D:/code/rmmo')
for label, enabled in [('none_a1', False), ('none_b1', True), ('none_b2', True), ('none_a2', False)]:
    name = f'loading_collision_{label}_20261011'
    args = [sys.executable, 'tools/profile_load_hardware.py', '--timeout', '600',
            '--log', f'review_artifacts/{name}.log', '--hardware', f'review_artifacts/{name}.hardware.json',
            '--', 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe', '--path', str(root),
            '--script', 'res://tools/profile_game_entry.gd', '--',
            '--map=D:/code/rmmo_runtime/cache/world3d/reference_pennant_checkpoint_20261009/map.gltf',
            f'--output=D:/code/rmmo_runtime/review_artifacts/{name}.json', '--spawn=321.2,0.9,160.3',
            '--monitor', '--with-collision-first',
            '--with-no-collision-proof' if enabled else '--without-no-collision-proof']
    print(f'Start {label}', flush=True)
    code = subprocess.run(args, cwd=root).returncode
    if code:
        sys.exit(code)
print('ABBA complete', flush=True)
