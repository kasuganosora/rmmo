"""Serial private-desktop acceptance. No production map or source edits."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

REPO = Path('D:/code/rmmo')
sys.path.insert(0, str(REPO / 'tools'))
from profile_load_hardware import Sampler
from run_godot_background import run_background

OUT = Path('D:/code/rmmo_runtime/review_artifacts/joint_model_validation_20261011')
FIXTURE = Path('D:/code/rmmo_runtime/cache/world3d/joint_model_validation_20261011_1791726474152524200')
BASE = Path('D:/code/rmmo_runtime/cache/world3d/bridge_lod_checkpoint_20261011_1791699698203797000/map.gltf')
PREFERRED = FIXTURE / 'preferred/map.gltf'
COMBINED = FIXTURE / 'combined/map.gltf'
FORMAL = Path('D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf')
FORMAL_SHA = '779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f'
GODOT = 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe'
MAP_SHAS = {BASE: FORMAL_SHA,
            PREFERRED: 'efd34c1399225fc50076f0c85f9dee7ca5289087c1c9ed8c5db5be5e26788215',
            COMBINED: 'f362c6345d6cfcab5f94c003fec1564f339d6f81d6e71ef3b978fe6a2d74ef1c'}

def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def run_one(name, kind, map_path, collision='off', picking='off', sharing='off'):
    if sha(FORMAL) != FORMAL_SHA or sha(map_path) != MAP_SHAS[map_path]:
        raise RuntimeError('Formal/fixture identity changed before ' + name)
    result_path = OUT / (name + '.json')
    log = OUT / (name + '.log')
    hardware = OUT / (name + '.hardware.json')
    if any(p.exists() for p in (result_path, log, hardware)):
        raise RuntimeError('Refusing to overwrite earlier evidence: ' + name)
    script = 'profile_game_entry.gd' if kind == 'game' else 'test_house_town_editor_incremental.gd'
    cmd = [GODOT, '--path', str(REPO), '--script', 'res://tools/' + script, '--',
           '--map=' + map_path.as_posix(), '--output=' + result_path.as_posix(),
           '--model-texture-sharing=' + sharing]
    if kind == 'game':
        cmd += ['--spawn=321.2,0.9,160.3', '--monitor', '--probe-physics', '--collision-geometry=' + collision]
    else:
        cmd += ['--load-trace', '--expected-sha=' + MAP_SHAS[map_path],
                '--formal-sha=' + FORMAL_SHA, '--picking-lod=' + picking]
    sampler = Sampler()
    began = time.time()
    print('JOINT_START ' + json.dumps({'name': name, 'epoch': began, 'command': cmd}), flush=True)
    try:
        process = run_background(cmd, cwd=REPO, timeout=1200,
                                 on_start=sampler.start, on_poll=sampler.poll)
        log.write_bytes(process.stdout)
    except subprocess.TimeoutExpired as error:
        log.write_bytes(error.output or b'')
        raise
    finally:
        hardware.write_text(json.dumps(sampler.finish(), indent=2), encoding='utf-8')
    report = json.loads(result_path.read_text(encoding='utf-8')) if result_path.exists() else {}
    lines = log.read_text(encoding='utf-8', errors='replace').splitlines()
    errors = [line for line in lines if re.match(r'^\s*(SCRIPT ERROR:|ERROR:|FAIL[ :])', line)]
    warnings = [line for line in lines if re.match(r'^\s*WARNING:', line)]
    summary = {'name': name, 'exit_code': process.returncode, 'failures': report.get('failures'),
               'entry_ms': report.get('entry_ms'), 'load_ms': report.get('load_ms'),
               'errors': errors, 'warnings': warnings, 'wall_s': time.time() - began}
    print('JOINT_FINISH ' + json.dumps(summary), flush=True)
    if process.returncode or report.get('failures') != 0 or report.get('timeout') or errors:
        raise RuntimeError('Acceptance failed: ' + name)
    if sha(FORMAL) != FORMAL_SHA or sha(map_path) != MAP_SHAS[map_path]:
        raise RuntimeError('Formal/fixture identity changed after ' + name)
    return summary

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['resources', 'game_resources', 'picking', 'collision', 'sharing'])
    parser.add_argument('--tag', default='', help='Distinct evidence suffix for a changed, frozen code revision')
    args = parser.parse_args()
    if args.tag and not re.fullmatch(r'[a-z0-9_]+', args.tag):
        parser.error('tag must use lowercase letters, digits or underscore')
    OUT.mkdir(parents=True, exist_ok=True)
    if args.phase in ('resources', 'game_resources'):
        jobs = [('game_preferred_warm', 'game', PREFERRED)] if args.phase == 'resources' else []
        for kind in (('game', 'editor') if args.phase == 'resources' else ('game',)):
            jobs += [(kind + '_baseline_a1', kind, BASE), (kind + '_preferred_b1', kind, PREFERRED),
                     (kind + '_preferred_b2', kind, PREFERRED), (kind + '_baseline_a2', kind, BASE)]
    elif args.phase == 'picking':
        jobs = [('editor_picking_off_a1', 'editor', COMBINED, 'off', 'off'),
                ('editor_picking_on_b1', 'editor', COMBINED, 'off', 'on'),
                ('editor_picking_on_b2', 'editor', COMBINED, 'off', 'on'),
                ('editor_picking_off_a2', 'editor', COMBINED, 'off', 'off')]
    elif args.phase == 'collision':
        jobs = [('game_collision_off_a1', 'game', PREFERRED),
                ('game_collision_on_b1', 'game', PREFERRED, 'on'),
                ('game_collision_on_b2', 'game', PREFERRED, 'on'),
                ('game_collision_off_a2', 'game', PREFERRED)]
    else:
        # G1 did not improve the full-town comparison. Isolate sharing on the
        # preferred release models with the retained default picking behavior.
        jobs = [('editor_sharing_off_a1', 'editor', PREFERRED, 'off', 'off', 'off'),
                ('editor_sharing_on_b1', 'editor', PREFERRED, 'off', 'off', 'on'),
                ('editor_sharing_on_b2', 'editor', PREFERRED, 'off', 'off', 'on'),
                ('editor_sharing_off_a2', 'editor', PREFERRED, 'off', 'off', 'off')]
    if args.tag:
        jobs = [(job[0] + '_' + args.tag, *job[1:]) for job in jobs]
    code_paths = [REPO / name for name in (
        'scripts/world3d/model_parse_preparation.gd', 'scripts/world3d/deferred_asset_loader.gd',
        'scripts/world3d/model_collision_requirements.gd', 'scripts/world3d/model_texture_cache.gd',
        'scripts/world_editor/picking_lod_policy.gd', 'scripts/world_editor/load_job.gd',
        'tools/profile_game_entry.gd', 'tools/test_house_town_editor_incremental.gd')]
    code_state = {path.as_posix(): sha(path) for path in code_paths}
    receipt_name = args.phase + ('_' + args.tag if args.tag else '')
    code_receipt = OUT / (receipt_name + '_code_identity.json')
    with code_receipt.open('x', encoding='utf-8') as file:
        json.dump(code_state, file, indent=2)
    completed = []
    for job in jobs:
        if any(sha(Path(path)) != digest for path, digest in code_state.items()):
            raise RuntimeError('Measured code changed before ' + job[0])
        completed.append(run_one(*job))
        if any(sha(Path(path)) != digest for path, digest in code_state.items()):
            raise RuntimeError('Measured code changed during ' + job[0])
        (OUT / (receipt_name + '_run_receipts.json')).write_text(json.dumps(completed, indent=2), encoding='utf-8')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
