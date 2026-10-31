"""Private-desktop Windows event trace contract; never a performance score."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sys


def post_owned(output):
    target = json.loads((output / 'target.json').read_text(encoding='utf8'))
    if os.getppid() != target['pid']:
        raise RuntimeError('Message helper must be a child of the owned Godot process')
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenThread.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
    kernel.OpenThread.restype = ctypes.c_void_p
    kernel.GetProcessIdOfThread.argtypes = [ctypes.c_void_p]
    kernel.GetProcessIdOfThread.restype = ctypes.c_ulong
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenThread(0x0800, False, target['tid'])
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        if kernel.GetProcessIdOfThread(handle) != target['pid']:
            raise RuntimeError('Thread ownership changed')
        user = ctypes.WinDLL('user32', use_last_error=True)
        user.PostThreadMessageW.argtypes = [ctypes.c_ulong, ctypes.c_uint, ctypes.c_size_t, ctypes.c_ssize_t]
        user.PostThreadMessageW.restype = ctypes.c_int
        for _ in range(3):
            if not user.PostThreadMessageW(target['tid'], 0, 0, 0):  # WM_NULL
                raise ctypes.WinError(ctypes.get_last_error())
        (output / 'posted.json').write_text(json.dumps(dict(target, posted=3)), encoding='utf8')
    finally:
        kernel.CloseHandle(handle)


def run(args):
    from run_godot_background import run_background
    from summarize_debug_timeline import export
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for key in ['APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP']:
        directory = output / key
        directory.mkdir()
        os.environ[key] = str(directory)
    target = {}

    def started(pid, tid):
        target.update(pid=pid, tid=tid)
        (output / 'target.json').write_text(json.dumps(target), encoding='utf8')

    command = [str(args.engine), '--path', str(args.project), '--script',
               'res://tools/test_windows_event_timeline.gd', '--',
               '--output-dir=' + str(output), '--python=' + sys.executable,
               '--harness=' + str(Path(__file__).resolve())]
    result = run_background(command, cwd=args.project, timeout=120, on_start=started)
    (output / 'engine.log').write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(result.stdout.decode('utf8', errors='replace')[-3000:])
    report = json.loads((output / 'result.json').read_text(encoding='utf8'))
    posted = json.loads((output / 'posted.json').read_text(encoding='utf8'))
    assert not report['failures'] and posted == dict(target, posted=3)
    data = export(output / 'events.rmtrace', output / 'csv')
    assert not data['orphan_ends'] and not data['crossing_spans'] and not data['task_name_conflicts']
    spans = [r for r in data['spans'] if r['complete'] and r['thread'] == target['tid']]
    labels = ['windows.loop', 'windows.events', 'windows.sdl', 'windows.lock_wait',
              'windows.raw_input', 'windows.messages', 'windows.dispatch',
              'windows.key_events', 'windows.input_flush', 'windows.hdr_poll',
              'windows.dialogs', 'sdl.poll', 'main.iteration']
    counts = {label: sum(r['label'] == label for r in spans) for label in labels}
    failures = []
    if not all(counts.values()):
        failures.append('native_windows_ranges_missing')
    messages = [r for r in spans if r['label'] == 'windows.dispatch' and r['context'] == 0]
    if len(messages) < 3:
        failures.append('posted_WM_NULL_not_traced')
    pairs = 0
    for loop in [r for r in spans if r['label'] == 'windows.loop']:
        main = [r for r in spans if r['label'] == 'main.iteration'
                and loop['start_us'] <= r['start_us'] and r['end_us'] <= loop['end_us']]
        if len(main) != 1:
            failures.append('loop_main_membership')
            continue
        before = [r for r in spans if r['label'] == 'windows.events'
                  and loop['start_us'] <= r['start_us'] and r['end_us'] <= main[0]['start_us']]
        if len(before) != 1:
            failures.append('events_before_main_membership')
            continue
        pairs += 1
    delay = [r for r in spans if r['label'] == 'test.event_pump.main_delay']
    assert len(delay) == 1 and delay[0]['wall_us'] >= 24000
    assert all(r['end_us'] <= delay[0]['start_us'] or r['start_us'] >= delay[0]['end_us']
               for r in spans if r['label'] == 'windows.events')
    evidence = dict(engine_sha256=hashlib.sha256(args.engine.read_bytes()).hexdigest(),
                    posted=3, traced_WM_NULL=len(messages), counts=counts,
                    ordered_loop_pairs=pairs, coverage_failures=failures,
                    incomplete_capture_boundary_scopes=data['incomplete_spans'], events=report['stats']['events'])
    (output / 'coverage.json').write_text(json.dumps(evidence, indent=2), encoding='utf8')
    print(json.dumps(evidence), flush=True)
    if args.expect_missing:
        assert failures == ['native_windows_ranges_missing', 'posted_WM_NULL_not_traced']
    else:
        assert not failures and pairs > 100


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--post', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--engine', type=Path)
    parser.add_argument('--project', type=Path)
    parser.add_argument('--expect-missing', action='store_true')
    args = parser.parse_args()
    if args.post:
        post_owned(args.output)
    else:
        if args.engine is None or args.project is None:
            parser.error('--engine and --project are required')
        run(args)
