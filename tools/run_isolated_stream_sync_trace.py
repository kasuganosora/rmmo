"""Diagnostic Stream.sync capture against a verified A-state private fixture.

The sample runner inherits a private environment in a separate process; GPU runs
use the existing hidden-desktop runner. File verification warms the OS cache.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from isolated_fixture_lock import fixture_lock
from isolated_sidecar_switch import load_fixture, check_state
from run_isolated_axel_sample import inside

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = Path('D:/code/rmmo_runtime/review_artifacts')
TRACE_SCRIPT = 'res://tools/profile_axel_stream_sync_trace.gd'
PHASES = ('white_native_unload', 'white_native_return', 'white_native_reload')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, obj):
    with Path(path).open('x', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def make_command(template, sample, target, content, map_path, suppress_slow_logs=False):
    if target not in PHASES:
        raise ValueError('invalid capture phase')
    cmd = list(template)
    # The private-desktop launcher substitutes a GUI executable for a console
    # path. Reject that indirection so the hashed executable is the one run.
    if not cmd or '_console.exe' in cmd[0]:
        raise ValueError('template must name the GUI executable directly')
    if cmd.count('--script') != 1 or cmd[cmd.index('--script') + 1] != 'res://tools/profile_axel_worker_capacity.gd':
        raise ValueError('unexpected template script')
    if cmd.count('--path') != 1 or Path(cmd[cmd.index('--path') + 1]).resolve() != ROOT:
        raise ValueError('template project differs from current checkout')
    for prefix, expected in (('--test-map=', map_path), ('--test-content-root=', content)):
        options = [s for s in cmd if s.startswith(prefix)]
        if len(options) != 1 or Path(options[0][len(prefix):]).resolve() != expected:
            raise ValueError('template fixture differs from selected private fixture')
    outs = [i for i,s in enumerate(cmd) if s.startswith('--output=')]
    if len(outs) != 1 or any(s.startswith('--sync-trace-phase=') or s == '--suppress-sync-slow-logs' for s in cmd):
        raise ValueError('unexpected output or preexisting trace argument')
    cmd[cmd.index('--script') + 1] = TRACE_SCRIPT
    cmd[outs[0]] = '--output=' + str(sample / 'sample.json')
    cmd.append('--sync-trace-phase=' + target)
    if suppress_slow_logs: cmd.append('--suppress-sync-slow-logs')
    return cmd


def source_snapshot(template):
    paths = set(template['source_before'])
    # Include newly added scripts as well as those present when the template
    # was captured; otherwise a concurrent untracked dependency can change
    # without invalidating the before/after check.
    paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / 'scripts').rglob('*.gd'))
    paths.update(('tools/profile_axel_stream_sync_trace.gd', 'tools/run_isolated_stream_sync_trace.py',
                  'tools/profile_axel_predictive_streaming.gd',
                  'tools/run_godot_background.py', 'tools/isolated_sidecar_switch.py',
                  'tools/isolated_fixture_lock.py', 'tools/run_isolated_axel_sample.py'))
    result = {}
    for rel in sorted(paths):
        path = (ROOT / rel).resolve(strict=True)
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError('unsafe source path')
        result[rel] = sha(path)
    return result


def capture_status(path, expected_suppression=None):
    """Reject missing, truncated, partial or overflowed captures explicitly."""
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
        if not isinstance(data, dict): raise ValueError('sample must be an object')
        trace = data.get('stream_sync_trace', {})
        if not isinstance(trace, dict): raise ValueError('trace must be an object')
        actual_suppression = data.get('sync_slow_logs_suppressed')
        matches = expected_suppression is None or actual_suppression is expected_suppression
        return {'status': data.get('stream_sync_trace_status', 'missing'),
                'dropped': trace.get('dropped'), 'failures': data.get('failures'),
                'sync_slow_logs_suppressed': actual_suppression,
                'suppression_matches': matches,
                'valid': data.get('stream_sync_trace_status') == 'complete_leg'
                and trace.get('dropped') == 0 and data.get('failures') == [] and matches}
    except (OSError, ValueError, TypeError) as exc:
        return {'status': 'unreadable', 'valid': False, 'error': str(exc)}


def child(command_path, timeout):
    from run_godot_background import run_background
    command = json.loads(Path(command_path).read_text(encoding='utf-8'))
    result = run_background(command, cwd=ROOT, timeout=timeout)
    sys.stdout.buffer.write(result.stdout)
    return result.returncode


def run(args):
    artifacts = ARTIFACTS.resolve(strict=True)
    sample = inside(args.sample_dir, artifacts)
    user = inside(args.user_dir, artifacts)
    content = inside(args.content_root, artifacts).resolve(strict=True)
    settings = inside(args.settings, artifacts).resolve(strict=True)
    template_path = inside(args.template, artifacts).resolve(strict=True)
    for a,b in ((sample,content),(user,content),(sample,user)):
        if a == b or a.is_relative_to(b) or b.is_relative_to(a):
            raise ValueError('sample, user and fixture must be disjoint')
    if settings.is_relative_to(user) or settings.is_relative_to(sample):
        raise ValueError('settings must be outside mutable directories')
    if args.timeout <= 0: raise ValueError('positive timeout required')
    template = json.loads(template_path.read_text(encoding='utf-8'))
    map_path = Path(template['map_path']).resolve(strict=True)
    if not map_path.is_relative_to(content): raise ValueError('map not inside fixture')
    engine = Path(template['command'][0]).resolve(strict=True)
    if sha(engine) != template['engine_sha256']: raise ValueError('engine SHA mismatch')
    settings_bytes = settings.read_bytes()
    settings_sha = hashlib.sha256(settings_bytes).hexdigest()
    if settings_sha != args.settings_sha256.lower(): raise ValueError('settings SHA mismatch')
    command = make_command(template['command'], sample, args.phase, content, map_path, args.suppress_slow_logs)
    with fixture_lock(content):
        verified_root, manifest, stable = load_fixture(content, args.manifest_sha256.lower(), args.expected_candidates)
        if Path(manifest['target_map']).resolve(strict=True) != map_path: raise ValueError('manifest map mismatch')
        before_state, before_variants = check_state(verified_root, manifest, stable)
        if before_state != 'A': raise ValueError('A state required, no automatic switching')
        if sha(map_path) != template['map_sha256']: raise ValueError('map SHA mismatch')
        before_source = source_snapshot(template)
        sample.mkdir(parents=True, exist_ok=False)
        user.mkdir(parents=True, exist_ok=False)
        roaming, local, temporary = user / 'roaming', user / 'local', sample / 'temp'
        for p in (roaming, local, temporary): p.mkdir()
        private_settings = roaming / 'Godot/app_userdata/rmmo/game_settings.cfg'
        private_settings.parent.mkdir(parents=True)
        private_settings.write_bytes(settings_bytes)
        env = os.environ.copy()
        env.update(APPDATA=str(roaming), LOCALAPPDATA=str(local), TEMP=str(temporary), TMP=str(temporary), TMPDIR=str(temporary), PYTHONDONTWRITEBYTECODE='1')
        for key in list(env):
            if key.startswith(('RMMO_WAIT','RMMO_RELEASE')) or key in ('RMMO_FILE_TRACE','RMMO_PROFILE_NATIVE_CALLERS'):
                env.pop(key)
        before = {'state':before_state, 'variants':before_variants, 'stable_files':{str(p):v for p,v in stable.items()}, 'sources':before_source, 'map_sha256':sha(map_path)}
        write_json(sample / 'before.json', before)
        write_json(sample / 'command.json', command)
        write_json(sample / 'launch.json', {'template':str(template_path), 'template_sha256':sha(template_path), 'engine_sha256':sha(engine), 'manifest_sha256':args.manifest_sha256.lower(), 'phase':args.phase, 'suppress_slow_logs':args.suppress_slow_logs, 'settings_sha256':settings_sha, 'appdata':str(roaming), 'localappdata':str(local), 'temp':str(temporary), 'contract':'Diagnostic only; fixture verification warms OS cache; lock only protects cooperating processes.'})
        result = {'exit_code':None}
        try:
            proc = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--child', str(sample / 'command.json'), '--timeout', str(args.timeout)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
            (sample / 'engine.log').write_bytes(proc.stdout)
            result['exit_code'] = proc.returncode
            result['capture'] = capture_status(sample / 'sample.json', args.suppress_slow_logs)
        finally:
            try:
                after_state, after_variants = check_state(verified_root, manifest, stable)
                after_source = source_snapshot(template)
                after = {'state':after_state, 'variants':after_variants, 'stable_files':{str(p):v for p,v in stable.items()}, 'sources':after_source, 'map_sha256':sha(map_path)}
                write_json(sample / 'after.json', after)
                result.update(fixture_unchanged=after == before and sha(content / 'fixture_manifest.json') == args.manifest_sha256.lower(), settings_unchanged=sha(settings) == settings_sha and sha(private_settings) == settings_sha, engine_unchanged=sha(engine) == template['engine_sha256'])
            except Exception as exc:
                result.update(fixture_unchanged=False, postcheck_error=str(exc))
            write_json(sample / 'result.json', result)
        return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--child', type=Path)
    p.add_argument('--timeout', type=int, default=420)
    for name in ('sample-dir','user-dir','content-root','settings','template'):
        p.add_argument('--'+name, type=Path)
    p.add_argument('--settings-sha256')
    p.add_argument('--manifest-sha256')
    p.add_argument('--expected-candidates', type=int, default=11)
    p.add_argument('--phase', choices=PHASES)
    p.add_argument('--suppress-slow-logs', action='store_true', help='Suppress selected synchronous slow prints only; keep profile_frame and tracing enabled')
    a = p.parse_args()
    if a.child: return child(a.child, a.timeout)
    if any(getattr(a,n) is None for n in ('sample_dir','user_dir','content_root','settings','template','settings_sha256','manifest_sha256','phase')):
        p.error('all fixture, settings, template and phase arguments are required')
    r = run(a)
    print(json.dumps(r), flush=True)
    return 0 if r.get('exit_code') == 0 and r.get('fixture_unchanged') and r.get('settings_unchanged') and r.get('engine_unchanged') and r.get('capture', {}).get('valid') else 1

if __name__ == '__main__':
    raise SystemExit(main())
