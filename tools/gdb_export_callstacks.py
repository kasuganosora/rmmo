"""Source in GDB: rmmo-dump-stacks INCLUDE_WORKERS [MAIN_OS_TID] [DEPTH].

Reads debugger memory only. Execution control belongs to the standard GDB/MI
client; no timers or injected application-side timing hooks are installed.
"""
import json
import gdb


def stack(thread, depth=64):
    thread.switch()
    result = []
    frame = gdb.newest_frame()
    while frame is not None and len(result) < depth:
        try:
            row = {"pc": hex(frame.pc()), "function": frame.name() or "?"}
        except gdb.error as issue:
            result.append({"unwind_error": str(issue)})
            break
        try:
            line = frame.find_sal()
            if line.symtab is not None:
                row.update(file=line.symtab.fullname(), line=line.line)
            if "GDScriptFunction::call" in row["function"]:
                function = frame.read_var("this").dereference()
                row.update(script_function=str(function["name"]),
                           script_source=str(function["source"]))
        except (gdb.error, RuntimeError):
            pass
        result.append(row)
        try:
            frame = frame.older()
        except gdb.error as issue:
            result.append({"unwind_error": str(issue)})
            break
    return {"gdb_thread": thread.global_num, "os_thread": list(thread.ptid),
            "name": thread.name, "frames": result}


class ExportCallstacks(gdb.Command):
    def __init__(self):
        super().__init__("rmmo-dump-stacks", gdb.COMMAND_USER)

    def invoke(self, argument, _from_tty):
        inferior = gdb.selected_inferior()
        threads = inferior.threads()
        if not threads:
            raise gdb.GdbError("No stopped test process")
        args = argument.split()
        main_tid = (int(args[1]) or None) if len(args) > 1 else None
        depth = int(args[2]) if len(args) > 2 else 64
        if not 8 <= depth <= 128:raise gdb.GdbError("Stack depth outside diagnostic limits")
        main = next((thread for thread in threads if main_tid in thread.ptid[1:]), None) if main_tid is not None else min(threads, key=lambda thread: thread.global_num)
        if main is None:raise gdb.GdbError("The supplied main OS thread is not present")
        result = [stack(main, depth)]
        if args and args[0] == "1":
            result.extend(stack(thread, 16) for thread in threads
                          if thread != main and thread.is_stopped())
        gdb.write("RMMO_NATIVE_STACKS " + json.dumps(result) + "\n")


ExportCallstacks()
