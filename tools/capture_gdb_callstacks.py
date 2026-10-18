"""Sample an explicitly identified owned test process through standard GDB/MI.

Debugger stops distort frame times. Use this for native attribution, and measure
benefits in a separate run with the unmodified distribution engine.
"""
import argparse
import ast
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time

import psutil


class MI:
    def __init__(self, executable, log):
        self.process = subprocess.Popen([str(executable), "-nx", "-q", "--interpreter=mi3"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.lines = queue.Queue()
        self.log = log
        self.token = 0
        self.stopped = False
        self.exited = False
        self.console = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.rstrip())
        self.lines.put(None)

    def receive(self, timeout=30):
        line = self.lines.get(timeout=timeout)
        if line is None:
            raise EOFError("GDB exited")
        self.log.write(line + "\n")
        if line.startswith("*stopped"):
            self.stopped = True
            self.exited = "exited" in line
        elif line.startswith("*running"):
            self.stopped = False
        elif line.startswith('~"'):
            self.console.append(ast.literal_eval(line[1:]))
        return line

    def command(self, command, timeout=30):
        self.token += 1
        prefix = str(self.token) + "^"
        self.process.stdin.write(str(self.token) + command + "\n")
        self.process.stdin.flush()
        while True:
            line = self.receive(timeout)
            if line.startswith(prefix):
                if line.startswith(prefix + "error"):
                    raise RuntimeError(line)
                return line

    def wait_stopped(self):
        while not self.stopped:
            self.receive()

    def cli(self, text):
        self.console = []
        self.command("-interpreter-exec console " + json.dumps(text))
        return self.console


def capture(pid, executable, gdb, output, seconds=120., interval_ms=100., main_tid=None):
    if not 0 < seconds <= 600 or not 10 <= interval_ms <= 5000 or (main_tid is not None and main_tid <= 0):
        raise ValueError("Sampling duration, interval or main thread is invalid")
    # Resolve the exact executable before attaching. Never select a process
    # merely by name when another Godot/editor may belong to the user.
    target = psutil.Process(pid)
    if Path(target.exe()).resolve() != executable.resolve():
        raise ValueError("PID does not own the explicitly supplied executable")
    created = target.create_time()
    with output.with_suffix(".mi.log").open("x", encoding="utf-8") as log, \
            output.open("x", encoding="utf-8") as result:
        mi = MI(gdb, log)
        attached = False
        try:
            mi.command("-gdb-set mi-async on")
            mi.command("-gdb-set print thread-events off")
            mi.command("-file-exec-and-symbols " + json.dumps(executable.as_posix()), timeout=120)
            pretty = executable.parent.parent / "misc/utility/godot_gdb_pretty_print.py"
            if pretty.is_file():
                mi.cli("source " + pretty.as_posix())
            exporter = Path(__file__).with_name("gdb_export_callstacks.py")
            mi.cli("source " + exporter.as_posix())
            fresh = psutil.Process(pid)
            if fresh.create_time() != created or Path(fresh.exe()).resolve() != executable.resolve():
                raise ValueError("Test process identity changed before attach")
            mi.command("-target-attach " + str(pid)); attached = True
            mi.wait_stopped()
            began = time.monotonic(); seq = 0
            result.write(json.dumps({"kind":"header", "pid":pid, "process_create_time":created, "executable":str(executable),
                "seconds":seconds, "interval_ms":interval_ms, "main_os_tid":main_tid,
                "start_unix_ns":time.time_ns(), "start_monotonic_ns":time.monotonic_ns(),
                "note":"All-stop debugger samples; collection time and symbol loading are diagnostic overhead."}) + "\n")
            while time.monotonic() - began < seconds and not mi.exited:
                mi.command("-exec-continue")
                time.sleep(interval_ms / 1000)
                try:
                    mi.command("-exec-interrupt --all"); mi.wait_stopped()
                except RuntimeError:
                    if mi.exited:break
                    raise
                if mi.exited:
                    break
                stopped = time.monotonic_ns()
                dump = "rmmo-dump-stacks " + ("1" if seq % 20 == 0 else "0")
                if main_tid is not None:dump += " " + str(main_tid)
                lines = mi.cli(dump)
                for line in lines:
                    if line.startswith("RMMO_NATIVE_STACKS "):
                        result.write(json.dumps({"kind":"sample", "seq":seq,
                            "at_ms":(time.monotonic()-began)*1000, "unix_ns":time.time_ns(),
                            "collector_stop_us":(time.monotonic_ns()-stopped)/1000,
                            "threads":json.loads(line.removeprefix("RMMO_NATIVE_STACKS "))}) + "\n")
                        result.flush(); seq += 1
            print("GDB_NATIVE_SAMPLES", seq, "output", output, flush=True)
        finally:
            if attached and not mi.exited:
                try:
                    if not mi.stopped:
                        mi.command("-exec-interrupt --all"); mi.wait_stopped()
                    mi.command("-target-detach"); attached = False
                except (EOFError, RuntimeError, queue.Empty):
                    pass
            try:
                mi.command("-gdb-exit")
            except (EOFError, RuntimeError, queue.Empty, BrokenPipeError):
                pass
            mi.process.wait(timeout=15)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--gdb", type=Path, default=Path("C:/mingw64/bin/gdb.exe"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seconds", type=float, default=120.)
    parser.add_argument("--interval-ms", type=float, default=100.)
    parser.add_argument("--main-tid", type=int)
    args = parser.parse_args()
    if not 0 < args.seconds <= 600 or not 10 <= args.interval_ms <= 5000:
        parser.error("Sampling duration or interval outside diagnostic limits")
    capture(args.pid, args.executable, args.gdb, args.output, args.seconds, args.interval_ms, args.main_tid)
