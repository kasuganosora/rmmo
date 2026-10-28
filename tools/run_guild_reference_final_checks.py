"""Serial isolated GPU checks for the frozen 2026-10-13 guild candidate.

Never publishes to a formal library/map. Each child writes its own evidence.
"""
from pathlib import Path
import json
import subprocess
import argparse
from run_godot_background import run_background

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'review_artifacts/guild_reference_recheck_20261013'
ART = Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
GODOT = Path('D:/tools/godot/godot.windows.editor.x86_64.exe')
OPT = ROOT / 'review_artifacts/axel_guild_finish_20261012/reference_v3_optimization_20261013'


def gpu(label, script, args, timeout=1200):
    print('BEGIN', label, flush=True)
    result = run_background([GODOT, '--path', ROOT, '--script', script, '--', *args],
                            cwd=ROOT, timeout=timeout)
    (OUT / (label + '.log')).write_bytes(result.stdout)
    print('END', label, result.returncode, flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-street', action='store_true')
    parser.add_argument('--skip-tower', action='store_true')
    options = parser.parse_args()
    gpu('accepted_http_retry', 'res://tools/test_guild_reference_import.gd', [
        f'--source-dir={ART.as_posix()}', f'--out={(OUT / "accepted_http_retry").as_posix()}',
        f'--http-from={(OUT / "accepted_import/import_report.json").as_posix()}'], 2400)
    if not options.skip_street:
        print('BEGIN street_http_and_native_traversal', flush=True)
        result = subprocess.run(['python', 'tools/run_required_street_acceptance_recheck.py'], cwd=ROOT)
        if result.returncode:
            raise SystemExit(result.returncode)
    if not options.skip_tower:
        gpu('accepted_tower', 'res://tools/review_guild_reference_camera.gd', [
            f'--source={(ART / "guild_alarm_tower.glb").as_posix()}', '--kind=tower',
            f'--out={(OUT / "accepted_tower").as_posix()}'])
    gpu('accepted_hall_lamp', 'res://tools/review_guild_reference_camera.gd', [
        f'--source={(ART / "library/guild_hall_lantern.glb").as_posix()}', '--kind=prop',
        '--views=near,near_night', f'--out={(OUT / "accepted_hall_lamp").as_posix()}'])
    evidence = json.loads((OUT / 'accepted_import/import_report.json').read_text('utf8'))
    actual = next(row['output_path'] for row in evidence['items'] if row['id'] == 'axel_guild_repaired')
    gpu('accepted_runtime', 'res://tools/test_guild_repaired_runtime.gd', [
        f'--source={actual}', f'--out={(OUT / "accepted_runtime").as_posix()}'])
    args = [f'--source={(ART / "axel_guild_repaired.glb").as_posix()}',
            f'--candidate={(ART / "axel_guild_repaired.glb").as_posix()}', f'--out={OPT.as_posix()}']
    for case in ['baseline', 'candidate']:
        gpu('opt_' + case, 'res://tools/review_guild_reference_optimization.gd', args + [f'--case={case}'])
    result = subprocess.run([str(GODOT), '--headless', '--path', str(ROOT), '--script',
                             'res://tools/review_guild_reference_optimization.gd', '--',
                             *args, '--case=compare'], cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    (OUT / 'opt_compare.log').write_bytes(result.stdout)
    print('END opt_compare', result.returncode, flush=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
