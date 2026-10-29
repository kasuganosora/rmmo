"""Serial private-desktop GPU and headless regression for this scoped batch."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path('D:/code/rmmo_runtime/review_artifacts/staged_far_20261017')
GODOT = 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for label, script in [('building_traversal_gpu', 'test_building_traversal_gpu'),
                          ('collision_first_gpu', 'test_collision_first_loading_gpu'),
                          ('entry_http', 'test_staged_entry_http')]:
        result = subprocess.run([sys.executable, 'tools/run_godot_background.py', '--timeout', '300',
                                 '--log', str(OUT / (label + '.log')), '--', GODOT, '--path', '.',
                                 '--log-file', str(OUT / (label + '_live.log')),
                                 '--script', 'res://tools/' + script + '.gd'], cwd=ROOT, timeout=330)
        print(label, result.returncode, flush=True)
        if result.returncode:
            return result.returncode
    for label in ['staged_far_contract', 'entry_readiness', 'local_entry_authority',
                  'ground_batch_lifetime', 'terrain_incremental', 'vegetation_scatter',
                  'wind_lod_optimization', 'bridge_lod_retention']:
        result = subprocess.run([GODOT.replace('.exe', '_console.exe'), '--headless', '--path', '.',
                                 '--script', 'res://tools/test_' + label + '.gd'], cwd=ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        (OUT / (('contract' if label == 'staged_far_contract' else label) + '.log')).write_bytes(result.stdout)
        print(label, result.returncode, flush=True)
        if result.returncode:
            return result.returncode
    result = subprocess.run([GODOT.replace('.exe', '_console.exe'), '--headless', '--path', '.',
                             '--script', 'res://tools/benchmark_terrain_render_lod.gd'], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (OUT / 'terrain_preparation.log').write_bytes(result.stdout)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
