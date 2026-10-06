"""Run Godot on a private, never-activated Windows desktop.

Unlike --headless (dummy renderer in this Godot build), this retains Vulkan.
No SwitchDesktop call is made. Test windows cannot take focus on the user's
desktop. Use the GUI executable directly so the waited process owns the engine.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import os
from pathlib import Path
import subprocess
import tempfile
import time


def run_background(command, *, cwd=None, timeout=360):
    if os.name != 'nt':
        raise RuntimeError('Private-desktop GPU runner currently supports Windows only')
    import msvcrt
    user = ctypes.WinDLL('user32', use_last_error=True)
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)

    class Startup(ctypes.Structure):
        _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR),
                    ('lpTitle', w.LPWSTR), ('dwX', w.DWORD), ('dwY', w.DWORD),
                    ('dwXSize', w.DWORD), ('dwYSize', w.DWORD),
                    ('dwXCountChars', w.DWORD), ('dwYCountChars', w.DWORD),
                    ('dwFillAttribute', w.DWORD), ('dwFlags', w.DWORD),
                    ('wShowWindow', w.WORD), ('cbReserved2', w.WORD),
                    ('lpReserved2', ctypes.POINTER(w.BYTE)), ('hStdInput', w.HANDLE),
                    ('hStdOutput', w.HANDLE), ('hStdError', w.HANDLE)]

    class Process(ctypes.Structure):
        _fields_ = [('process', w.HANDLE), ('thread', w.HANDLE),
                    ('pid', w.DWORD), ('tid', w.DWORD)]

    user.CreateDesktopW.argtypes = [w.LPCWSTR, w.LPCWSTR, ctypes.c_void_p,
                                   w.DWORD, w.DWORD, ctypes.c_void_p]
    user.CreateDesktopW.restype = w.HANDLE
    user.CloseDesktop.argtypes = [w.HANDLE]
    kernel.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p,
                                     ctypes.c_void_p, w.BOOL, w.DWORD,
                                     ctypes.c_void_p, w.LPCWSTR,
                                     ctypes.POINTER(Startup), ctypes.POINTER(Process)]
    kernel.CreateProcessW.restype = w.BOOL
    kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    kernel.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]
    kernel.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
    kernel.CloseHandle.argtypes = [w.HANDLE]
    desktop_name = f'RMMO_test_{os.getpid()}_{time.time_ns()}'
    # Full desktop object access, but never activate it or move the user's windows.
    desktop = user.CreateDesktopW(desktop_name, None, None, 0, 0x01FF, None)
    if not desktop:
        raise ctypes.WinError(ctypes.get_last_error())
    process = Process()
    command = list(map(str, command))
    gui = Path(command[0].replace('_console.exe', '.exe'))
    if gui.is_file():
        command[0] = str(gui)
    try:
        with tempfile.TemporaryFile() as output, open(os.devnull, 'rb') as null:
            startup = Startup()
            startup.cb = ctypes.sizeof(startup)
            startup.lpDesktop = 'winsta0\\' + desktop_name
            startup.dwFlags = 0x100  # STARTF_USESTDHANDLES
            startup.hStdInput = msvcrt.get_osfhandle(null.fileno())
            startup.hStdOutput = startup.hStdError = msvcrt.get_osfhandle(output.fileno())
            for handle in (startup.hStdInput, startup.hStdOutput):
                os.set_handle_inheritable(handle, True)
            line = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
            ok = kernel.CreateProcessW(command[0], line, None, None, True,
                                       0x08000000, None, str(cwd) if cwd else None,
                                       ctypes.byref(startup), ctypes.byref(process))
            if not ok:
                raise ctypes.WinError(ctypes.get_last_error())
            deadline = time.monotonic() + timeout
            # Short native waits also let KeyboardInterrupt cancel the owned engine.
            while True:
                wait = kernel.WaitForSingleObject(process.process, 200)
                if wait != 258 or time.monotonic() >= deadline:
                    break
            if wait != 0:
                kernel.TerminateProcess(process.process, 124)
                kernel.WaitForSingleObject(process.process, 5000)
                output.seek(0)
                raise subprocess.TimeoutExpired(command, timeout, output=output.read())
            code = w.DWORD()
            if not kernel.GetExitCodeProcess(process.process, ctypes.byref(code)):
                raise ctypes.WinError(ctypes.get_last_error())
            output.seek(0)
            return subprocess.CompletedProcess(command, code.value, output.read())
    finally:
        if process.process:
            status = w.DWORD()
            if kernel.GetExitCodeProcess(process.process, ctypes.byref(status)) and status.value == 259:
                kernel.TerminateProcess(process.process, 124)
                kernel.WaitForSingleObject(process.process, 5000)
        for handle in (process.thread, process.process):
            if handle:
                kernel.CloseHandle(handle)
        user.CloseDesktop(desktop)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=int, default=360)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Godot command required after --')
    args.log.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = run_background(command, cwd=Path(__file__).resolve().parents[1], timeout=args.timeout)
    except subprocess.TimeoutExpired as error:
        args.log.write_bytes((error.stdout or b'') + b'\nBACKGROUND TEST TIMEOUT\n')
        print(f'Background Godot timed out; log={args.log}')
        return 124
    args.log.write_bytes(result.stdout)
    print(f'Background Godot exit={result.returncode}; log={args.log}')
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
