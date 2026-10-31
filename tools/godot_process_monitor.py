"""Select test workloads before querying remote process command lines.

On Windows, querying every application's command line can consume seconds of
CPU per sweep and perturb the game being measured. Keep unrelated applications
out of that expensive path; retain inaccessible matching processes in reports.
"""
import psutil

WORKLOAD_NAMES = ('godot', 'blender', 'gdb', 'scons', 'cc1', 'clang', 'gcc', 'cl.exe')


def named_processes(tokens=WORKLOAD_NAMES):
    for process in psutil.process_iter(['pid', 'name']):
        if any(token in (process.info['name'] or '').lower() for token in tokens):
            yield process


def workload_snapshot():
    rows = []
    for process in named_processes():
        try:
            # as_dict preserves None for AccessDenied fields, so an engine
            # without readable arguments still appears as competing work.
            rows.append(process.as_dict(attrs=['pid', 'name', 'cmdline', 'create_time']))
        except psutil.NoSuchProcess:
            pass
    return rows
