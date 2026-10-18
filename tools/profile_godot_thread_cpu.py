"""Sample only the owned Godot process while using the private-desktop runner.

Windows thread CPU counters distinguish execution from wall-clock waits. Samples
are diagnostic, with scheduler accounting granularity; they are not call stacks.
No sampling files are written until the owned process has exited.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import statistics
import threading
import time

from run_godot_background import run_background


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=650)
    parser.add_argument('--interval-ms', type=float, default=10)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--samples', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Godot command required after --')
    stop = threading.Event()
    rows = []
    workers = []
    info = {'interval_ms': args.interval_ms, 'scope': 'owned process only',
            'columns': ['unix_ns', 'qpc_ns', 'cpu_totals_us'],
            'counter': 'Win32 GetThreadTimes + GetProcessTimes, cached owned handles',
            'process_counter_tid': 0,
            'sampling_cost_us': 0, 'max_sampling_cost_us': 0}

    def started(pid, tid):
        info.update(pid=pid, main_win32_tid=tid)

        def sample():
            cpu_started = time.thread_time_ns()
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel.OpenProcess.restype = wintypes.HANDLE
            kernel.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel.OpenThread.restype = wintypes.HANDLE
            kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            pointers = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
            kernel.GetThreadTimes.argtypes = pointers
            kernel.GetProcessTimes.argtypes = pointers
            process = kernel.OpenProcess(0x1000, False, pid)
            thread = kernel.OpenThread(0x0800, False, tid)
            created = wintypes.FILETIME(); exited = wintypes.FILETIME()
            system = wintypes.FILETIME(); user = wintypes.FILETIME()

            def read(function, handle):
                if not function(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(system), ctypes.byref(user)):
                    return None
                return (((system.dwHighDateTime << 32) | system.dwLowDateTime)
                        + ((user.dwHighDateTime << 32) | user.dwLowDateTime)) // 10

            try:
                if not process or not thread:
                    info['error'] = f'Cannot open owned handles: {ctypes.get_last_error()}'
                    return
                while not stop.is_set():
                    began = time.perf_counter_ns()
                    main_cpu = read(kernel.GetThreadTimes, thread)
                    process_cpu = read(kernel.GetProcessTimes, process)
                    if main_cpu is None or process_cpu is None:
                        break
                    now = time.time_ns()
                    cost = (time.perf_counter_ns() - began) // 1000
                    info['sampling_cost_us'] += cost
                    info['max_sampling_cost_us'] = max(info['max_sampling_cost_us'], cost)
                    rows.append([now, began, [[tid, main_cpu], [0, process_cpu]]])
                    stop.wait(max(0, args.interval_ms / 1000 - cost / 1_000_000))
            finally:
                if thread:kernel.CloseHandle(thread)
                if process:kernel.CloseHandle(process)
                info['sampler_thread_cpu_us'] = (time.thread_time_ns() - cpu_started) // 1000

        worker = threading.Thread(target=sample, name='owned-godot-cpu', daemon=True)
        workers.append(worker)
        worker.start()

    try:
        result = run_background(command, cwd=Path(__file__).resolve().parents[1],
                                timeout=args.timeout, on_start=started)
        output = result.stdout
        code = result.returncode
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or b'') + b'\nBACKGROUND TEST TIMEOUT\n'
        code = 124
    finally:
        stop.set()
        for worker in workers:
            worker.join(timeout=2)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    if len(rows)>1:
        intervals = [(right[1]-left[1])/1_000_000 for left, right in zip(rows, rows[1:])]
        info['observed_interval_ms'] = {'median':statistics.median(intervals),'max':max(intervals)}
    args.samples.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_bytes(output)
    args.samples.write_text(json.dumps({'metadata': info, 'samples': rows}, separators=(',', ':')), encoding='utf-8')
    print(f'Owned Godot exit={code}; samples={len(rows)}; log={args.log}')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
