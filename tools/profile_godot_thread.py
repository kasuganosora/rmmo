"""Read-only Windows main-thread CPU sampling for a named background test.

Correlate unix_seconds with the route JSON's unix_offset + ticks_usec / 1e6.
Thread CPU time distinguishes running work from wall time spent off-CPU; it
does not identify which lock, driver wait, or scheduler event caused a pause.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import time

import psutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenThread.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.GetThreadTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    kernel.QueryThreadCycleTime.argtypes = [wintypes.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)]
    deadline = time.monotonic() + args.timeout
    process = None
    while process is None and time.monotonic() < deadline:
        for candidate in psutil.process_iter(["name", "cmdline"]):
            if "godot" in (candidate.info["name"] or "").lower() and "--label=" + args.label in (candidate.info["cmdline"] or []):
                process = candidate
                break
        if process is None:
            time.sleep(0.1)
    if process is None:
        raise RuntimeError("Named background test did not start")

    def timing(handle):
        fields = [wintypes.FILETIME() for _ in range(4)]
        if not kernel.GetThreadTimes(handle, *(ctypes.byref(value) for value in fields)):
            return None
        return [(value.dwHighDateTime << 32) | value.dwLowDateTime for value in fields]

    handles = []
    for thread in process.threads():
        handle = kernel.OpenThread(0x0800, False, thread.id)
        if handle:
            values = timing(handle)
            if values is not None:
                handles.append((values[0], thread.id, handle))
            else:
                kernel.CloseHandle(handle)
    if not handles:
        raise RuntimeError("Cannot read test thread times")
    handles.sort()
    _, tid, main_handle = handles[0]
    for _, _, handle in handles[1:]:
        kernel.CloseHandle(handle)
    samples = []
    memory_samples = []
    next_memory = 0.0
    try:
        while process.is_running() and time.monotonic() < deadline:
            values = timing(main_handle)
            cycles = ctypes.c_ulonglong()
            if values is None or values[1] != 0:
                break
            kernel.QueryThreadCycleTime(main_handle, ctypes.byref(cycles))
            samples.append([time.time_ns() / 1e9, (values[2] + values[3]) / 1e7, cycles.value])
            if time.monotonic() >= next_memory:
                try:
                    memory = process.memory_info()
                    memory_samples.append([time.time_ns() / 1e9, memory.rss, memory.vms, getattr(memory, "num_page_faults", None)])
                except psutil.Error:
                    pass
                next_memory = time.monotonic() + 0.1
            time.sleep(0.005)
    finally:
        kernel.CloseHandle(main_handle)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({"pid": process.pid, "thread_id": tid, "columns": ["unix_seconds", "cpu_seconds", "cycles"], "samples": samples, "memory_columns": ["unix_seconds", "rss_bytes", "vms_bytes", "page_faults"], "memory_samples": memory_samples}), encoding="utf-8")
    print(f"Recorded {len(samples)} samples for test PID {process.pid}, thread {tid}")


if __name__ == "__main__":
    main()
