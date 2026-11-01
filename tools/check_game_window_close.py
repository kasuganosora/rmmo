"""Exercise actual game entry and native X/WM_CLOSE on a private desktop."""
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time

from godot_process_monitor import workload_snapshot
from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--map', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    ready = output / 'ready.json'
    report = {'engine': str(args.engine), 'engine_sha256': hashlib.sha256(args.engine.read_bytes()).hexdigest(),
              'map': str(args.map), 'map_sha256': hashlib.sha256(args.map.read_bytes()).hexdigest(),
              'workload_before': workload_snapshot(), 'status': 'prepared', 'pid': None}
    for key in ('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP'):
        private = output / key
        private.mkdir()
        os.environ[key] = str(private)
    for key in list(os.environ):
        if key.startswith(('RMMO_', 'VK_')):
            os.environ.pop(key)
    os.environ['RMMO_CLOSE_PROBE_MAP'] = args.map.resolve().as_posix()
    os.environ['RMMO_CLOSE_PROBE_READY'] = ready.as_posix()
    user = ctypes.WinDLL('user32', use_last_error=True)
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user.GetWindowThreadProcessId.restype = wintypes.DWORD
    user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user.PostMessageW.restype = wintypes.BOOL
    user.SetThreadDesktop.argtypes = [wintypes.HANDLE]
    user.SetThreadDesktop.restype = wintypes.BOOL
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel.TerminateProcess.restype = wintypes.BOOL
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    owned_handle = None
    owned_desktop = None
    sent = None

    def save():
        (output / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

    def desktop_created(handle):
        nonlocal owned_desktop
        owned_desktop = handle

    def started(pid, tid):
        nonlocal owned_handle
        owned_handle = kernel.OpenProcess(0x0001, False, pid)
        assert owned_handle, ctypes.get_last_error()
        report['pid'] = pid
        report['main_tid'] = tid
        report['status'] = 'running'
        save()

    def poll():
        nonlocal sent
        if sent is not None:
            if time.monotonic() - sent > 20 and not report.get('close_timeout'):
                report['close_timeout'] = True
                save()
                # The retained handle belongs to the process this runner started,
                # so even PID reuse cannot target a different application.
                assert kernel.TerminateProcess(owned_handle, 124), ctypes.get_last_error()
            return
        if not ready.exists():
            return
        try:
            handshake = json.loads(ready.read_text(encoding='utf-8'))
        except json.JSONDecodeError:
            return
        assert handshake['pid'] == report['pid'], 'Handshake belongs to another process'
        report['handshake'] = handshake
        report['workload_at_close'] = workload_snapshot()
        delivery = {}

        def deliver():
            try:
                # HWND lookup is desktop-local. Attach only a fresh helper thread
                # to the owned, never-activated desktop; never SwitchDesktop.
                assert owned_desktop and user.SetThreadDesktop(owned_desktop), ctypes.get_last_error()
                owner = wintypes.DWORD()
                tid = user.GetWindowThreadProcessId(handshake['hwnd'], ctypes.byref(owner))
                delivery.update(window_thread=tid, window_pid=owner.value)
                assert tid and owner.value == report['pid'], 'Refuse another process window'
                delivery['sent_monotonic'] = time.monotonic()
                delivery['sent_epoch_s'] = time.time()
                assert user.PostMessageW(handshake['hwnd'], 0x0010, 0, 0), ctypes.get_last_error()
            except BaseException as error:
                delivery['error'] = repr(error)

        sender = threading.Thread(target=deliver, name='Owned desktop WM_CLOSE', daemon=True)
        sender.start()
        sender.join(timeout=5)
        report['close_delivery'] = delivery
        if sender.is_alive() or delivery.get('error'):
            report['delivery_failed'] = True
            kernel.TerminateProcess(owned_handle, 125)
        else:
            sent = delivery['sent_monotonic']
            report['close_sent_epoch_s'] = delivery['sent_epoch_s']
        save()

    command = [str(args.engine.resolve()), '--path', str(args.project.resolve()),
               '--script', 'res://tools/test_game_window_close.gd']
    try:
        result = run_background(command, cwd=args.project, timeout=270, on_start=started,
                                on_poll=poll, on_desktop=desktop_created)
        (output / 'engine.log').write_bytes(result.stdout)
        # Includes the host's <=200ms process poll and output-pipe cleanup.
        report.update(exit=result.returncode, host_close_to_runner_return_s=time.monotonic() - sent if sent else None)
        report['events'] = [json.loads(line.split('WINDOW_CLOSE_PROBE ', 1)[1])
                            for line in result.stdout.decode('utf-8', 'replace').splitlines()
                            if line.startswith('WINDOW_CLOSE_PROBE ')]
        report['errors'] = [line for line in result.stdout.decode('utf-8', 'replace').splitlines()
                            if line.startswith(('ERROR:', 'SCRIPT ERROR:'))]
        assert sent is not None and any(row['event'] == 'native_close_received' for row in report['events'])
        assert result.returncode == 0 and not report['errors'], 'Game shutdown failed'
        expected = ['playable', 'waiting_for_native_close', 'native_close_received',
                    'world_tree_exited', 'root_tree_exited', 'scene_tree_finalized']
        observed = [row['event'] for row in report['events']]
        positions = [observed.index(event) for event in expected]
        assert positions == sorted(positions), 'Missing or out-of-order exit lifecycle'
        close = next(row for row in report['events'] if row['event'] == 'native_close_received')
        assert close['auto_accept_quit'], 'This game window is not using normal close policy'
        assert not report['handshake']['viewport_disabled'], 'Game was still behind a 3D cover'
        finalized = next(row for row in report['events'] if row['event'] == 'scene_tree_finalized')
        report['close_event_to_scene_finalize_us'] = finalized['ticks_us'] - close['ticks_us']
        report['status'] = 'native_close_passed'
    except BaseException as error:
        report.update(status='failed_or_incomplete', error=repr(error))
        if isinstance(error, subprocess.TimeoutExpired) and error.output:
            (output / 'engine.log').write_bytes(error.output)
        save()
        raise
    finally:
        if owned_handle:
            kernel.CloseHandle(owned_handle)
        report['workload_after'] = workload_snapshot()
        save()
    print(json.dumps({key: report.get(key) for key in (
        'status', 'exit', 'host_close_to_runner_return_s',
        'close_event_to_scene_finalize_us', 'errors')}, indent=2), flush=True)


if __name__ == '__main__':
    main()
