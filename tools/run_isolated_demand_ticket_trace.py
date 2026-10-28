"""Capture ticket counters in a disposable diagnostic overlay and private fixture.

Uses the same fixture lock, source-before/after check and hidden desktop as the
isolated stream trace runner. These are diagnostic, never frame performance runs.
"""
import argparse
import itertools
import json
from pathlib import Path

import run_isolated_stream_sync_trace as base
from prepare_demand_ticket_overlay import files_snapshot, sha

SOURCE_ROOT = Path(__file__).resolve().parents[1]
PHASES = ('white_native_return', 'white_walk_return')
CAPACITY = 16384
CACHE_FILES = ('.godot/global_script_class_cache.cfg', '.godot/uid_cache.bin')


def disjoint_roots(overlay, sample, user, content):
    roots = [Path(value).resolve() for value in (overlay, sample, user, content)]
    for first, second in itertools.combinations(roots, 2):
        if first == second or first.is_relative_to(second) or second.is_relative_to(first):
            raise ValueError('overlay, sample, user and fixture must be disjoint')


def class_cache_snapshot(root):
    """Track class/UID cache bytes; mutable shader and imported caches excluded."""
    result = {}
    for relative in CACHE_FILES:
        path = Path(root) / relative
        if not path.resolve().is_relative_to(Path(root).resolve()) or path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError('invalid class-cache file: ' + str(path))
        result[relative] = sha(path.read_bytes()) if path.exists() else None
    return result


def make_command(template, sample, target, content, map_path, _suppressed):
    if target not in PHASES:
        raise ValueError('invalid ticket trace phase')
    command = list(template)
    base.require_full_template(command)
    if not command or '_console.exe' in command[0]:
        raise ValueError('template must name GUI executable directly')
    if command.count('--script') != 1 or command[command.index('--script') + 1] != 'res://tools/profile_axel_worker_capacity.gd':
        raise ValueError('unexpected template script')
    if command.count('--path') != 1 or Path(command[command.index('--path') + 1]).resolve() != SOURCE_ROOT:
        raise ValueError('template source project differs from original checkout')
    for prefix, expected in (('--test-map=', map_path), ('--test-content-root=', content)):
        options = [value for value in command if value.startswith(prefix)]
        if len(options) != 1 or Path(options[0][len(prefix):]).resolve() != expected:
            raise ValueError('template fixture differs from selected private fixture')
    outs = [i for i,value in enumerate(command) if value.startswith('--output=')]
    if len(outs) != 1 or any(value.startswith('--demand-ticket-') for value in command):
        raise ValueError('unexpected output or existing ticket flags')
    command[command.index('--path') + 1] = str(base.ROOT)
    command[command.index('--script') + 1] = 'res://tools/profile_axel_demand_tickets.gd'
    command[outs[0]] = '--output=' + str(sample / 'sample.json')
    command.extend(('--demand-ticket-trace', '--demand-ticket-phase=' + target, '--demand-ticket-capacity=' + str(CAPACITY)))
    return command


def capture_status(path, expected_phase, expected_capacity=CAPACITY):
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
        if not isinstance(data, dict): raise ValueError('sample must be an object')
        trace = data.get('demand_ticket_trace', {})
        if not isinstance(trace, dict): raise ValueError('trace must be an object')
        status = data.get('demand_ticket_status', 'missing')
        events = trace.get('events')
        boundaries = data.get('demand_ticket_boundaries')
        if not isinstance(events, list) or not events: raise ValueError('no ticket events')
        if not isinstance(boundaries, list) or len(boundaries) < 2: raise ValueError('missing phase boundaries')
        if not all(isinstance(row, dict) for row in boundaries): raise ValueError('invalid boundary')
        if not all(isinstance(row.get('phase'), str) and row['phase'] for row in boundaries): raise ValueError('invalid boundary phase')
        if boundaries[0].get('kind') != 'start' or boundaries[-1].get('kind') != 'end': raise ValueError('unclosed phase boundaries')
        allowed_phases = {expected_phase}
        if expected_phase == 'white_walk_return': allowed_phases.update(('white_walk_return_straight', 'white_walk_return_turn'))
        if any(row.get('phase') not in allowed_phases for row in boundaries[:-1]) or boundaries[-1].get('phase') in allowed_phases:
            raise ValueError('phase boundary mismatch')
        if any(row.get('kind') != 'transition' for row in boundaries[1:-1]): raise ValueError('invalid phase transition')
        observed_phases = {row['phase'] for row in boundaries[:-1]}
        if expected_phase == 'white_walk_return' and 'white_walk_return' not in observed_phases and not {'white_walk_return_straight', 'white_walk_return_turn'} <= observed_phases:
            raise ValueError('missing walk return segment')
        def integer(value):
            return isinstance(value, int) and not isinstance(value, bool) and value >= 0
        frames = [row.get('frame') for row in boundaries]
        ticks = [row.get('ticks_us') for row in boundaries]
        if not all(integer(value) for value in frames + ticks): raise ValueError('invalid boundary clock')
        if frames != sorted(frames) or ticks != sorted(ticks): raise ValueError('nonmonotonic phase boundaries')
        if data.get('demand_ticket_boundaries_dropped') != 0: raise ValueError('boundary overflow')
        if data.get('demand_ticket_phase') != expected_phase or data.get('demand_ticket_capacity') != expected_capacity or trace.get('capacity') != expected_capacity:
            raise ValueError('phase or capacity differs from request')
        if not all(integer(trace.get(name)) for name in ('dropped', 'untracked', 'evicted')): raise ValueError('invalid overflow counters')
        if len(events) > expected_capacity: raise ValueError('event count exceeds capacity')
        fields = ('input_rows', 'kind_excluded', 'published', 'new_uuid', 'duplicate_uuid', 'winner_changes', 'support_visits')
        event_frames = []
        for row in events:
            if not isinstance(row, dict) or not integer(row.get('frame')) or not frames[0] <= row['frame'] <= frames[-1]:
                raise ValueError('ticket outside capture boundary')
            event_frames.append(row['frame'])
            if not isinstance(row.get('id'), str) or not row['id'] or row.get('id_truncated') is not False or not isinstance(row.get('complete_members'), bool):
                raise ValueError('invalid ticket identity or membership status')
            if not all(integer(row.get(name)) for name in fields): raise ValueError('invalid event counts')
            if row['input_rows'] != sum(row[name] for name in ('kind_excluded', 'published', 'new_uuid', 'duplicate_uuid')):
                raise ValueError('event input partition mismatch')
            if row['winner_changes'] > row['duplicate_uuid']: raise ValueError('winner changes exceed duplicates')
        if event_frames != sorted(event_frames): raise ValueError('nonmonotonic ticket frames')
        return {'status':status, 'dropped':trace.get('dropped'), 'untracked':trace.get('untracked'), 'evicted':trace.get('evicted'),
                'failures':data.get('failures'), 'phase':data.get('demand_ticket_phase'),
                'capacity':data.get('demand_ticket_capacity'), 'events':len(events),
                'incomplete_members':sum(row.get('complete_members') is not True for row in events),
                'valid':status == 'complete_return_leg' and trace.get('dropped') == 0
                        and trace.get('untracked') == 0 and data.get('failures') == []}
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        return {'status':'unreadable', 'valid':False, 'error':str(exc)}


def checked_sources(_template):
    manifest_path = base.ROOT / 'ticket_trace_overlay_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if Path(manifest['source_project']).resolve() != SOURCE_ROOT or Path(manifest['output_project']).resolve() != base.ROOT:
        raise ValueError('overlay identity mismatch')
    expected = dict(manifest['source_files'])
    if files_snapshot(SOURCE_ROOT) != expected:
        raise ValueError('original source differs from overlay snapshot')
    if not manifest.get('finalized_after_import'):
        raise ValueError('overlay was not finalized after class-cache initialization')
    overlay_expected = manifest['overlay_files']
    if files_snapshot(base.ROOT) != overlay_expected:
        raise ValueError('overlay source differs from recorded snapshot')
    diff_path = base.ROOT / 'ticket_trace_injection.diff'
    if sha(diff_path.read_bytes()) != manifest['injection_diff_sha256']:
        raise ValueError('overlay injection diff changed')
    return {'original':expected, 'overlay':overlay_expected, 'class_cache':class_cache_snapshot(base.ROOT),
            'manifest':sha(manifest_path.read_bytes()), 'injection_diff':sha(diff_path.read_bytes())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('overlay','sample-dir','user-dir','content-root','settings','template'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--settings-sha256', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--phase', required=True, choices=PHASES)
    parser.add_argument('--timeout', type=int, default=420)
    parser.add_argument('--expected-full-models', type=int, default=49)
    args = parser.parse_args()
    args.overlay = base.inside(args.overlay, base.ARTIFACTS.resolve(strict=True)).resolve(strict=True)
    disjoint_roots(args.overlay, args.sample_dir, args.user_dir, args.content_root)
    args.suppress_slow_logs = False
    base.ROOT = args.overlay
    base.make_command = make_command
    base.capture_status = lambda path, _suppressed: capture_status(path, args.phase)
    base.source_snapshot = checked_sources
    result = base.run(args)
    print(json.dumps(result), flush=True)
    return 0 if result.get('exit_code') == 0 and result.get('fixture_unchanged') and result.get('settings_unchanged') and result.get('engine_unchanged') and result.get('template_unchanged') and result.get('capture', {}).get('valid') else 1


if __name__ == '__main__':
    raise SystemExit(main())
