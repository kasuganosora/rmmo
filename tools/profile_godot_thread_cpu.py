"""Sample only the owned Godot process while using the private-desktop runner.

Windows thread CPU counters distinguish execution from wall-clock waits. Samples
are diagnostic, with scheduler accounting granularity; they are not call stacks.
No sampling files are written until the owned process has exited.
Optional system counters retain raw cycles and cumulative OS counters; they do
not identify effective CPU frequency, physical disk reads, or hard page faults.
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


class SystemCounters:
    """Opt-in counters sharing the sampler's read-only owned process handles."""

    columns = [
        'unix_ns', 'qpc_ns', 'thread_user_us', 'thread_kernel_us',
        'process_user_us', 'process_kernel_us', 'thread_cycles', 'process_cycles',
        'system_idle_us', 'system_kernel_us', 'system_user_us',
        'io_read_ops', 'io_write_ops', 'io_other_ops',
        'io_read_bytes', 'io_write_bytes', 'io_other_bytes',
        'process_page_faults', 'process_working_set_bytes', 'process_private_bytes',
        'system_available_physical_bytes', 'system_total_physical_bytes',
        'system_memory_load_pct',
    ]

    class IoCounters(ctypes.Structure):
        _fields_ = [(name, ctypes.c_ulonglong) for name in (
            'ReadOperationCount', 'WriteOperationCount', 'OtherOperationCount',
            'ReadTransferCount', 'WriteTransferCount', 'OtherTransferCount')]

    class ProcessMemoryCounters(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD)] + [
            (name, ctypes.c_size_t) for name in (
                'PeakWorkingSetSize', 'WorkingSetSize', 'QuotaPeakPagedPoolUsage',
                'QuotaPagedPoolUsage', 'QuotaPeakNonPagedPoolUsage',
                'QuotaNonPagedPoolUsage', 'PagefileUsage', 'PeakPagefileUsage',
                'PrivateUsage')]

    class MemoryStatus(ctypes.Structure):
        _fields_ = [('dwLength', wintypes.DWORD), ('dwMemoryLoad', wintypes.DWORD)] + [
            (name, ctypes.c_ulonglong) for name in (
                'ullTotalPhys', 'ullAvailPhys', 'ullTotalPageFile',
                'ullAvailPageFile', 'ullTotalVirtual', 'ullAvailVirtual',
                'ullAvailExtendedVirtual')]

    def __init__(self, kernel, process, thread, metadata, include_system_load=False):
        self.kernel = kernel
        self.process = process
        self.thread = thread
        self.metadata = metadata
        self.include_system_load = include_system_load
        self.functions = {}
        ft = ctypes.POINTER(wintypes.FILETIME)
        self._bind('GetThreadTimes', [wintypes.HANDLE] + [ft] * 4)
        self._bind('GetProcessTimes', [wintypes.HANDLE] + [ft] * 4)
        self._bind('QueryThreadCycleTime', [wintypes.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)])
        self._bind('QueryProcessCycleTime', [wintypes.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)])
        if include_system_load:
            self._bind('GetSystemTimes', [ft, ft, ft])
        self._bind('GetProcessIoCounters', [wintypes.HANDLE, ctypes.POINTER(self.IoCounters)])
        self._bind('K32GetProcessMemoryInfo', [wintypes.HANDLE, ctypes.POINTER(self.ProcessMemoryCounters), wintypes.DWORD])
        self._bind('GlobalMemoryStatusEx', [ctypes.POINTER(self.MemoryStatus)])
        self.created = wintypes.FILETIME()
        self.exited = wintypes.FILETIME()
        self.system = wintypes.FILETIME()
        self.user = wintypes.FILETIME()
        self.idle = wintypes.FILETIME()
        self.cycles = ctypes.c_ulonglong()
        self.io = self.IoCounters()
        self.memory = self.ProcessMemoryCounters()
        self.memory.cb = ctypes.sizeof(self.memory)
        self.status = self.MemoryStatus()
        self.status.dwLength = ctypes.sizeof(self.status)

    def _error(self, name, code):
        errors = self.metadata['api_failures']
        entry = errors.setdefault(name, {'count': 0, 'first_error': code})
        entry['count'] += 1
        entry['last_error'] = code

    def _bind(self, name, arguments):
        try:
            function = getattr(self.kernel, name)
        except AttributeError:
            self._error(name, 'unavailable')
            return
        function.argtypes = arguments
        function.restype = wintypes.BOOL
        self.functions[name] = function

    def _call(self, name, *arguments):
        function = self.functions.get(name)
        if function is None:
            return False
        began = time.perf_counter_ns()
        try:
            ok = function(*arguments)
        finally:
            cost = (time.perf_counter_ns() - began) // 1000
            entry = self.metadata['api_costs'].setdefault(name, {'calls': 0, 'wall_us': 0, 'max_wall_us': 0})
            entry['calls'] += 1
            entry['wall_us'] += cost
            entry['max_wall_us'] = max(entry['max_wall_us'], cost)
        if ok:
            return True
        self._error(name, ctypes.get_last_error())
        return False

    @staticmethod
    def _us(value):
        return ((value.dwHighDateTime << 32) | value.dwLowDateTime) // 10

    def _times(self, name, handle):
        if self._call(name, handle, ctypes.byref(self.created), ctypes.byref(self.exited),
                      ctypes.byref(self.system), ctypes.byref(self.user)):
            return [self._us(self.user), self._us(self.system)]
        return [None, None]

    def _cycles(self, name, handle):
        if self._call(name, handle, ctypes.byref(self.cycles)):
            return self.cycles.value
        return None

    def sample(self):
        began = time.perf_counter_ns()
        row = [time.time_ns(), began]
        row.extend(self._times('GetThreadTimes', self.thread))
        row.extend(self._times('GetProcessTimes', self.process))
        row.append(self._cycles('QueryThreadCycleTime', self.thread))
        row.append(self._cycles('QueryProcessCycleTime', self.process))
        if self.include_system_load and self._call('GetSystemTimes', ctypes.byref(self.idle), ctypes.byref(self.system), ctypes.byref(self.user)):
            row.extend([self._us(self.idle), self._us(self.system), self._us(self.user)])
        else:
            row.extend([None] * 3)
        if self._call('GetProcessIoCounters', self.process, ctypes.byref(self.io)):
            row.extend(getattr(self.io, name) for name, _ in self.IoCounters._fields_)
        else:
            row.extend([None] * 6)
        if self._call('K32GetProcessMemoryInfo', self.process, ctypes.byref(self.memory), self.memory.cb):
            row.extend([self.memory.PageFaultCount, self.memory.WorkingSetSize, self.memory.PrivateUsage])
        else:
            row.extend([None] * 3)
        if self._call('GlobalMemoryStatusEx', ctypes.byref(self.status)):
            row.extend([self.status.ullAvailPhys, self.status.ullTotalPhys, self.status.dwMemoryLoad])
        else:
            row.extend([None] * 3)
        cost = (time.perf_counter_ns() - began) // 1000
        self.metadata['sampling_cost_us'] += cost
        self.metadata['max_sampling_cost_us'] = max(self.metadata['max_sampling_cost_us'], cost)
        return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=650)
    parser.add_argument('--interval-ms', type=float, default=10)
    parser.add_argument('--system-counters', action='store_true',
                        help='Sample owned-process CPU/cycles/IO/memory and global memory; no system CPU query')
    parser.add_argument('--system-load-counters', action='store_true',
                        help='Also query GetSystemTimes (observed blocking); implies --system-counters')
    parser.add_argument('--system-interval-ms', type=float, default=50)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--samples', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Godot command required after --')
    if not 0 < args.system_interval_ms < float('inf'):
        parser.error('--system-interval-ms must be finite and positive')
    if args.system_load_counters:
        args.system_counters = True
    stop = threading.Event()
    rows = []
    system_rows = []
    system_info = None
    if args.system_counters:
        system_info = {
            'interval_ms': args.system_interval_ms, 'columns': SystemCounters.columns,
            'sampling_cost_us': 0, 'max_sampling_cost_us': 0, 'api_failures': {}, 'api_costs': {},
            'scope': 'Owned main thread/process and global memory; system CPU is separately opt-in; no other process enumeration',
            'system_load_counters': args.system_load_counters,
            'not_collected': {} if args.system_load_counters else {'GetSystemTimes': 'not_requested'},
            'counter_semantics': {
                'cpu': 'Cumulative user/kernel microseconds, not wall time; system kernel includes idle',
                'system_busy': 'For deltas: busy = kernel + user - idle; total = kernel + user. On >64 CPUs GetSystemTimes covers the calling processor group',
                'cycles': 'Raw CPU timer cycles; CPU-dependent semantics. Never convert to wall time or effective frequency',
                'io': 'Cumulative process operation/byte counters; not physical disk IO or cache-miss evidence',
                'memory': 'PageFaultCount includes soft/hard faults; PrivateUsage is committed private bytes, not physical residency',
                'missing': 'Failed/unavailable API values are null, never zero; see api_failures',
                'api_costs': 'Per-API wall microseconds include API waits/descheduling; not sampler CPU or proven game overhead',
            },
        }
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
                counters = None
                next_system_ns = 0
                if system_info is not None:
                    try:
                        counters = SystemCounters(kernel, process, thread, system_info, args.system_load_counters)
                    except Exception as error:
                        system_info['setup_error'] = repr(error)
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
                    if counters is not None and began >= next_system_ns:
                        try:
                            system_rows.append(counters.sample())
                        except Exception as error:
                            system_info['sampling_error'] = repr(error)
                            counters = None  # Preserve the original CPU sampler on optional failure.
                        next_system_ns = began + int(args.system_interval_ms * 1_000_000)
                    wait_cost = (time.perf_counter_ns() - began) / 1_000_000_000 if args.system_counters else cost / 1_000_000
                    stop.wait(max(0, args.interval_ms / 1000 - wait_cost))
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
    result = {'metadata': info, 'samples': rows}
    if system_info is not None:
        if len(system_rows) > 1:
            intervals = [(right[1] - left[1]) / 1_000_000 for left, right in zip(system_rows, system_rows[1:])]
            system_info['observed_interval_ms'] = {'median': statistics.median(intervals), 'max': max(intervals)}
        result.update(system_metadata=system_info, system_samples=system_rows)
    args.samples.write_text(json.dumps(result, separators=(',', ':')), encoding='utf-8')
    print(f'Owned Godot exit={code}; samples={len(rows)}; log={args.log}')
    return code


if __name__ == '__main__':
    raise SystemExit(main())
