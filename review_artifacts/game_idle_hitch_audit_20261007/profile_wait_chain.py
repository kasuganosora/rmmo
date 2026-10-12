"""Read-only WCT sampling of one explicitly named Godot diagnostic process.

No injection, suspension, token adjustment, or automatic elevation. A single
thread node does NOT prove an absence of unsupported waits. GetThreadWaitChain
requires suitable access (Microsoft documents SE_DEBUG_NAME); access denial is
reported and sampling stops. Synchronous WCT may block this sampler, never the
target explicitly. Keep external CPU sampling for wall/CPU correlation.

Definitions checked against Windows SDK 10.0.22621.0/um/wct.h and:
https://learn.microsoft.com/en-us/windows/win32/api/wct/nf-wct-getthreadwaitchain
https://learn.microsoft.com/en-us/windows/win32/api/wct/ns-wct-waitchain_node_info
https://learn.microsoft.com/en-us/windows/win32/debug/wait-chain-traversal
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import threading
import subprocess
import sys
import time

import psutil


class LockObject(c.Structure):
    _fields_ = [("ObjectName", w.WCHAR * 128), ("Timeout", c.c_longlong), ("Alertable", w.BOOL)]


class ThreadObject(c.Structure):
    _fields_ = [("ProcessId", w.DWORD), ("ThreadId", w.DWORD), ("WaitTime", w.DWORD), ("ContextSwitches", w.DWORD)]


class ObjectInfo(c.Union):
    _fields_ = [("LockObject", LockObject), ("ThreadObject", ThreadObject)]


class WaitNode(c.Structure):
    _fields_ = [("ObjectType", c.c_int), ("ObjectStatus", c.c_int), ("Info", ObjectInfo)]


TYPES = ["invalid", "critical_section", "send_message", "mutex", "alpc", "com", "thread_wait", "process_wait", "thread", "com_activation", "unknown", "socket_io", "smb_io"]
STATUSES = ["invalid", "no_access", "running", "blocked", "pid_only", "pid_only_rpcss", "owned", "not_owned", "abandoned", "unknown", "error"]


WCT_OUT_OF_PROC_CS_FLAG = 0x4  # wct.h: query external target critical sections, without following out-of-process owners.


class Wct:
    def __init__(self, critical_sections=False):
        if os.name != "nt":
            raise RuntimeError("Windows-only candidate")
        assert c.sizeof(WaitNode) == 280, "Unexpected Windows WCT structure layout"
        self.api = c.WinDLL("advapi32", use_last_error=True)
        self.api.OpenThreadWaitChainSession.argtypes = [w.DWORD, c.c_void_p]
        self.api.OpenThreadWaitChainSession.restype = w.HANDLE
        self.api.CloseThreadWaitChainSession.argtypes = [w.HANDLE]
        self.api.CloseThreadWaitChainSession.restype = None
        self.api.GetThreadWaitChain.argtypes = [w.HANDLE, c.c_size_t, w.DWORD, w.DWORD, c.POINTER(w.DWORD), c.POINTER(WaitNode), c.POINTER(w.BOOL)]
        self.api.GetThreadWaitChain.restype = w.BOOL
        self.handle = self.api.OpenThreadWaitChainSession(0, None)
        if not self.handle:
            raise c.WinError(c.get_last_error())
        self.nodes = (WaitNode * 16)()
        self.flags = WCT_OUT_OF_PROC_CS_FLAG if critical_sections else 0

    def query(self, tid):
        count, cycle = w.DWORD(16), w.BOOL()
        begin = time.time_ns() / 1e9
        start = time.perf_counter_ns()
        ok = self.api.GetThreadWaitChain(self.handle, 0, self.flags, tid, c.byref(count), self.nodes, c.byref(cycle))
        error = 0 if ok else c.get_last_error()
        elapsed = (time.perf_counter_ns() - start) / 1e6
        row = {"unix_begin": begin, "query_ms": elapsed, "ok": bool(ok), "error": error, "cycle": bool(cycle.value), "count": count.value, "nodes": []}
        # ERROR_MORE_DATA / ERROR_TOO_MANY_THREADS retain a valid partial chain.
        if ok or error in (234, 565):
            for node in self.nodes[:min(16, count.value)]:
                item = {"type_id": node.ObjectType, "status_id": node.ObjectStatus,
                        "type": TYPES[node.ObjectType] if 0 <= node.ObjectType < len(TYPES) else "unknown",
                        "status": STATUSES[node.ObjectStatus] if 0 <= node.ObjectStatus < len(STATUSES) else "unknown"}
                if node.ObjectType == 8:
                    data = node.Info.ThreadObject
                    item.update(pid=data.ProcessId, tid=data.ThreadId, wait_time=data.WaitTime, context_switches=data.ContextSwitches)
                else:
                    item["name"] = node.Info.LockObject.ObjectName
                row["nodes"].append(item)
        return row

    def close(self):
        if self.handle:
            self.api.CloseThreadWaitChainSession(self.handle)
            self.handle = None


def self_test(critical_sections=False):
    kernel = c.WinDLL("kernel32", use_last_error=True)
    kernel.CreateMutexW.argtypes = [c.c_void_p, w.BOOL, w.LPCWSTR]
    kernel.CreateMutexW.restype = w.HANDLE
    kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    kernel.WaitForSingleObject.restype = w.DWORD
    kernel.ReleaseMutex.argtypes = [w.HANDLE]
    kernel.CloseHandle.argtypes = [w.HANDLE]
    mutex = kernel.CreateMutexW(None, True, None)
    if not mutex:
        raise c.WinError(c.get_last_error())
    waiting = threading.Event()
    identity = []

    def waiter():
        identity.append(threading.get_native_id())
        waiting.set()
        if kernel.WaitForSingleObject(mutex, 2000) == 0:
            kernel.ReleaseMutex(mutex)

    thread = threading.Thread(target=waiter, daemon=True)
    thread.start()
    waiting.wait(1)
    wct = Wct(critical_sections)
    try:
        time.sleep(.03)
        row = wct.query(identity[0])
        passed = row["ok"] and any(n["type"] == "mutex" for n in row["nodes"]) and any(n.get("tid") == threading.get_native_id() for n in row["nodes"])
        print(json.dumps({"self_test_passed": passed, "flags": wct.flags, "current_pid": os.getpid(), "main_tid": threading.get_native_id(), "result": row}, indent=2))
        return 0 if passed else 1
    finally:
        kernel.ReleaseMutex(mutex)
        thread.join(2)
        kernel.CloseHandle(mutex)
        wct.close()



def critical_section_child():
    # Native layout from winnt.h RTL_CRITICAL_SECTION; valid on this 64-bit host.
    class CriticalSection(c.Structure):
        _fields_ = [("DebugInfo", c.c_void_p), ("LockCount", w.LONG),
                    ("RecursionCount", w.LONG), ("OwningThread", w.HANDLE),
                    ("LockSemaphore", w.HANDLE), ("SpinCount", c.c_size_t)]
    kernel = c.WinDLL("kernel32", use_last_error=True)
    for name in ("InitializeCriticalSection", "EnterCriticalSection", "LeaveCriticalSection", "DeleteCriticalSection"):
        getattr(kernel, name).argtypes = [c.POINTER(CriticalSection)]
        getattr(kernel, name).restype = None
    assert c.sizeof(CriticalSection) == 40
    section = CriticalSection()
    kernel.InitializeCriticalSection(c.byref(section))
    kernel.EnterCriticalSection(c.byref(section))
    identity, entered = [], threading.Event()

    def waiter():
        identity.append(threading.get_native_id())
        entered.set()
        kernel.EnterCriticalSection(c.byref(section))
        kernel.LeaveCriticalSection(c.byref(section))

    thread = threading.Thread(target=waiter, daemon=True)
    thread.start()
    try:
        if not entered.wait(.5):
            return 2
        print(json.dumps({"pid": os.getpid(), "owner_tid": threading.get_native_id(), "waiting_tid": identity[0]}), flush=True)
        time.sleep(2)  # Parent queries while held; bounded release even if parent disappears.
    finally:
        kernel.LeaveCriticalSection(c.byref(section))
        thread.join(1)
        if not thread.is_alive():
            kernel.DeleteCriticalSection(c.byref(section))
    return 0 if not thread.is_alive() else 2


def external_cs_self_test():
    child = subprocess.Popen([sys.executable, "-u", str(Path(__file__).resolve()), "--critical-section-child"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                             creationflags=subprocess.CREATE_NO_WINDOW)
    results = []
    try:
        # Child has a bounded lifetime, including its owner release and worker join.
        line = child.stdout.readline()
        if not line:
            raise RuntimeError("External critical-section child failed: " + child.stderr.read())
        identity = json.loads(line)
        time.sleep(.05)
        for flag in (False, True):
            wct = Wct(flag)
            try:
                results.append({"flags": wct.flags, "result": wct.query(identity["waiting_tid"])})
            finally:
                wct.close()
        _, stderr = child.communicate(timeout=4)
        cs_result = results[1]["result"]
        passed = child.returncode == 0 and cs_result["ok"] and any(n["type"] == "critical_section" for n in cs_result["nodes"]) and any(n.get("tid") == identity["owner_tid"] for n in cs_result["nodes"])
        print(json.dumps({"external_cs_self_test_passed": passed, "child": identity, "child_exit": child.returncode, "stderr": stderr, "results": results}, indent=2))
        return 0 if passed else 1
    finally:
        if child.poll() is None:
            child.kill()
            child.communicate(timeout=3)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--external-cs-self-test", action="store_true")
    parser.add_argument("--critical-section-child", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--label")
    parser.add_argument("--critical-sections", action="store_true", help="Read critical-section info from the external target (WCT flag 0x4 only); do not follow owners into other processes")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--interval-ms", type=float, default=25)
    args = parser.parse_args()
    if args.critical_section_child:
        return critical_section_child()
    if args.external_cs_self_test:
        return external_cs_self_test()
    if args.self_test:
        return self_test(args.critical_sections)
    if not args.label or args.out is None:
        parser.error("--label and --out are required for named-test sampling")
    if args.interval_ms < 10 or not 0 < args.timeout <= 1200:
        parser.error("interval >= 10 ms and timeout in (0,1200] required")
    deadline = time.monotonic() + args.timeout
    process = None
    while process is None and time.monotonic() < deadline:
        found = []
        for candidate in psutil.process_iter(["name", "cmdline"]):
            if "godot" in (candidate.info["name"] or "").lower() and "--label=" + args.label in (candidate.info["cmdline"] or []):
                found.append(candidate)
        if len(found) > 1:
            raise RuntimeError("Ambiguous Godot label; refusing to pick a process")
        process = found[0] if found else None
        if process is None:
            time.sleep(.1)
    if process is None:
        raise RuntimeError("Named Godot diagnostic process did not start")
    kernel = c.WinDLL("kernel32", use_last_error=True)
    kernel.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    kernel.OpenThread.restype = w.HANDLE
    kernel.GetThreadTimes.argtypes = [w.HANDLE] + [c.POINTER(w.FILETIME)] * 4
    kernel.GetThreadTimes.restype = w.BOOL
    kernel.CloseHandle.argtypes = [w.HANDLE]
    created = []
    for thread in process.threads():
        handle = kernel.OpenThread(0x0800, False, thread.id)
        if not handle:
            continue
        try:
            times = [w.FILETIME() for _ in range(4)]
            if kernel.GetThreadTimes(handle, *(c.byref(value) for value in times)):
                created.append(((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime, thread.id))
        finally:
            kernel.CloseHandle(handle)
    if not created:
        raise RuntimeError("Cannot identify earliest-created test thread")
    _, tid = min(created)
    wct = Wct(args.critical_sections)
    rows = []
    stopped = "target_exit_or_timeout"
    try:
        while process.is_running() and time.monotonic() < deadline:
            started = time.monotonic()
            row = wct.query(tid)
            rows.append(row)
            if row["error"] in (5, 50, 1168):
                stopped = "wct_error_%d" % row["error"]
                break
            time.sleep(max(0, args.interval_ms / 1000 - (time.monotonic() - started)))
    finally:
        wct.close()
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({"pid": process.pid, "tid": tid, "label": args.label, "flags": wct.flags, "critical_sections": args.critical_sections, "follow_out_of_process": False, "stop": stopped,
                                        "single_node_does_not_exclude_unsupported_waits": True, "samples": rows}), encoding="utf-8")
    print(f"WCT recorded {len(rows)} samples for PID {process.pid}, TID {tid}; {stopped}")
    return 1 if stopped in ("wct_error_5", "wct_error_50") else 0


if __name__ == "__main__":
    raise SystemExit(main())
