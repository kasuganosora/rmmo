"""Sample only the owned private-desktop Godot process, not other applications.

CPU equivalents = process CPU seconds / wall seconds (not physical-core count).
I/O counters include logical/cache reads. PDH engine percentages are kept separate.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import json
import subprocess
import math
from pathlib import Path
import re
import time
import psutil
from run_godot_background import run_background


class GpuCounters:
    def __init__(self):
        self.api = ctypes.WinDLL('pdh')
        self.api.PdhOpenQueryW.argtypes = [w.LPCWSTR, ctypes.c_size_t, ctypes.POINTER(w.HANDLE)]
        self.api.PdhAddEnglishCounterW.argtypes = [w.HANDLE, w.LPCWSTR, ctypes.c_size_t, ctypes.POINTER(w.HANDLE)]
        self.api.PdhCollectQueryData.argtypes = [w.HANDLE]
        self.api.PdhGetFormattedCounterArrayW.argtypes = [w.HANDLE, w.DWORD, ctypes.POINTER(w.DWORD), ctypes.POINTER(w.DWORD), ctypes.c_void_p]
        self.api.PdhCloseQuery.argtypes = [w.HANDLE]
        self.query = w.HANDLE()
        self.counters = {}
        self.errors = {}
        if self.api.PdhOpenQueryW(None, 0, ctypes.byref(self.query)):
            raise RuntimeError('Cannot open PDH query')
        for key, path in [('engines', r'\GPU Engine(*)\Utilization Percentage'), ('dedicated', r'\GPU Process Memory(*)\Dedicated Usage'), ('shared', r'\GPU Process Memory(*)\Shared Usage')]:
            counter = w.HANDLE()
            status = self.api.PdhAddEnglishCounterW(self.query, path, 0, ctypes.byref(counter))
            if status:
                self.errors[key] = hex(status & 0xffffffff)
            else:
                self.counters[key] = counter
        self.api.PdhCollectQueryData(self.query)

    def sample(self, pid):
        class ValueUnion(ctypes.Union):
            _fields_ = [('double', ctypes.c_double), ('large', ctypes.c_longlong)]
        class Value(ctypes.Structure):
            _anonymous_ = ('value',)
            _fields_ = [('status', w.DWORD), ('value', ValueUnion)]
        class Item(ctypes.Structure):
            _fields_ = [('name', w.LPWSTR), ('value', Value)]
        collection = self.api.PdhCollectQueryData(self.query)
        result = {'collection_status': hex(collection & 0xffffffff)}
        for key, counter in self.counters.items():
            size, count = w.DWORD(), w.DWORD()
            status = self.api.PdhGetFormattedCounterArrayW(counter, 0x200 | 0x8000, ctypes.byref(size), ctypes.byref(count), None)
            if not size.value:
                result[key] = {'status': hex(status & 0xffffffff), 'items': {}}
                continue
            buffer = ctypes.create_string_buffer(size.value)
            status = self.api.PdhGetFormattedCounterArrayW(counter, 0x200 | 0x8000, ctypes.byref(size), ctypes.byref(count), buffer)
            values = {}
            if status == 0:
                for item in ctypes.cast(buffer, ctypes.POINTER(Item))[:count.value]:
                    if re.search(rf'(^|_)pid_{pid}_', item.name or '') and item.value.status in (0, 1) and math.isfinite(item.value.double):
                        values[item.name] = max(0.0, item.value.double)
            result[key] = {'status': hex(status & 0xffffffff), 'items': values}
        return result

    def close(self):
        self.api.PdhCloseQuery(self.query)


class Sampler:
    def __init__(self):
        self.process = None
        self.samples = []
        self.started = time.time()
        self.last = None
        self.previous_threads = {}
        self.errors = []
        self.gpu = None
        self.thread_names = {}
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
        self.kernel.OpenThread.restype = w.HANDLE
        self.kernel.GetThreadDescription.argtypes = [w.HANDLE, ctypes.POINTER(w.LPWSTR)]
        self.kernel.CloseHandle.argtypes = [w.HANDLE]
        self.kernel.LocalFree.argtypes = [ctypes.c_void_p]
        self.kernel.LocalFree.restype = ctypes.c_void_p
        try:
            self.gpu = GpuCounters()
        except Exception as error:
            self.errors.append('GPU counter initialization: ' + str(error))

    def start(self, pid, main_tid):
        self.process = psutil.Process(pid)
        self.pid = pid
        self.main_tid = main_tid
        self.started = time.time()
        self.poll(force=True)

    def poll(self, force=False):
        now = time.monotonic()
        if self.last is not None and now - self.last['monotonic_s'] < .5 and not force:
            return
        began = time.perf_counter()
        try:
            with self.process.oneshot():
                cpu = self.process.cpu_times()
                memory = self.process.memory_info()
                io = self.process.io_counters()
                threads = self.process.threads()
            snapshot = {'epoch_s': time.time(), 'monotonic_s': now, 'at_ms': (time.time()-self.started)*1000,
                        'cpu_s': cpu.user+cpu.system, 'rss_bytes': memory.rss,
                        'private_bytes': getattr(memory, 'private', None),
                        'read_bytes': io.read_bytes, 'write_bytes': io.write_bytes,
                        'read_operations': io.read_count, 'thread_count': len(threads)}
            current = {t.id: t.user_time+t.system_time for t in threads}
            for tid in current:
                if tid in self.thread_names:
                    continue
                handle = self.kernel.OpenThread(0x0800, False, tid)
                if handle:
                    name = w.LPWSTR()
                    try:
                        if self.kernel.GetThreadDescription(handle, ctypes.byref(name)) == 0 and name:
                            self.thread_names[tid] = name.value
                            self.kernel.LocalFree(ctypes.cast(name, ctypes.c_void_p))
                    finally:
                        self.kernel.CloseHandle(handle)
            if self.last is not None:
                elapsed = now - self.last['monotonic_s']
                snapshot['cpu_equivalents'] = max(0.0, (snapshot['cpu_s']-self.last['cpu_s'])/elapsed)
                snapshot['cpu_percent_total_logical'] = snapshot['cpu_equivalents']/psutil.cpu_count()*100
                snapshot['read_bytes_per_s'] = max(0, snapshot['read_bytes']-self.last['read_bytes'])/elapsed
                snapshot['threads'] = [{'id': tid, 'name': self.thread_names.get(tid, ''), 'cpu_s': value, 'cpu_equivalents': max(0, value-self.previous_threads.get(tid, 0))/elapsed}
                                       for tid, value in current.items()]
            if self.gpu is not None:
                snapshot['gpu'] = self.gpu.sample(self.pid)
            snapshot['sampler_ms'] = (time.perf_counter()-began)*1000
            self.samples.append(snapshot)
            self.last = snapshot
            self.previous_threads = current
        except (psutil.NoSuchProcess, psutil.AccessDenied) as error:
            self.errors.append(str(error))

    def finish(self):
        if self.gpu:
            self.gpu.close()
        return {'pid': getattr(self, 'pid', None), 'logical_cpus': psutil.cpu_count(),
                'main_thread_id': getattr(self, 'main_tid', None),
                'physical_cores': psutil.cpu_count(logical=False), 'system_ram_bytes': psutil.virtual_memory().total,
                'samples': self.samples, 'errors': self.errors, 'gpu_errors': self.gpu.errors if self.gpu else {},
                'thread_names': self.thread_names,
                'note': 'Thread CPU samples can miss short-lived threads. GPU engines are separate and must not be summed as one utilization percentage; process reads include cache hits. No OS waiting stacks are captured.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--hardware', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Godot command required after --')
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.hardware.parent.mkdir(parents=True, exist_ok=True)
    sampler = Sampler()
    try:
        result = run_background(command, cwd=Path(__file__).resolve().parents[1], timeout=args.timeout,
                                on_start=sampler.start, on_poll=sampler.poll)
        args.log.write_bytes(result.stdout)
        print(f'Background Godot exit={result.returncode}; log={args.log}; hardware={args.hardware}')
        return result.returncode
    except subprocess.TimeoutExpired as error:
        args.log.write_bytes(error.output or b'')
        print(f'Background Godot timed out; log={args.log}; hardware={args.hardware}')
        return 124
    finally:
        args.hardware.write_text(json.dumps(sampler.finish(), ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    raise SystemExit(main())
