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
import threading
import time


class _PipeCapture:
    """Drain inherited stdout independently; never let the child fsync our file."""

    def __init__(self, output):
        import msvcrt
        self.output = output
        self.read_fd, self.write_fd = os.pipe()
        self.handle = msvcrt.get_osfhandle(self.write_fd)
        os.set_handle_inheritable(self.handle, True)
        self.error = None
        self.cancelled = threading.Event()
        self.reader = threading.Thread(target=self._drain, name='RMMO output capture', daemon=True)
        self.reader.start()

    def _drain(self):
        try:
            while not self.cancelled.is_set():
                data = os.read(self.read_fd, 65536)
                if not data:
                    break
                self.output.write(data)
        except OSError as error:
            if not self.cancelled.is_set():
                self.error = error
        finally:
            os.close(self.read_fd)

    def close_parent_write(self):
        if self.write_fd is not None:
            os.close(self.write_fd)
            self.write_fd = None

    def finish(self):
        self.close_parent_write()
        self.reader.join(timeout=5)
        if self.reader.is_alive():
            # An unexpected descendant may keep the write handle open after
            # the owned engine exits. Cancel our own reader, not that process.
            # Cancellation is asynchronous: join before closing its output.
            self.cancelled.set()
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            kernel.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
            kernel.OpenThread.restype = w.HANDLE
            kernel.CancelSynchronousIo.argtypes = [w.HANDLE]
            kernel.CloseHandle.argtypes = [w.HANDLE]
            thread_handle = kernel.OpenThread(0x0001, False, self.reader.native_id)
            if thread_handle:
                try:
                    kernel.CancelSynchronousIo(thread_handle)
                finally:
                    kernel.CloseHandle(thread_handle)
            self.reader.join(timeout=5)
            raise RuntimeError('Owned engine exited but its output pipe did not close; capture is incomplete')
        if self.error is not None:
            raise RuntimeError('Failed to capture engine output') from self.error


def run_background(command, *, cwd=None, timeout=360, on_start=None, on_poll=None,
                   capture_mode='pipe'):
    if os.name != 'nt':
        raise RuntimeError('Private-desktop GPU runner currently supports Windows only')
    if capture_mode not in ('pipe', 'file'):
        raise ValueError('Unknown output capture mode')
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
            capture = _PipeCapture(output) if capture_mode == 'pipe' else None
            startup = Startup()
            startup.cb = ctypes.sizeof(startup)
            startup.lpDesktop = 'winsta0\\' + desktop_name
            startup.dwFlags = 0x100  # STARTF_USESTDHANDLES
            startup.hStdInput = msvcrt.get_osfhandle(null.fileno())
            # Debug Godot calls FlushFileBuffers(stdout) after every print.
            # A disk handle forces a durable write in the scene thread; a pipe
            # only waits for this independent reader. Preserve every byte/error.
            startup.hStdOutput = startup.hStdError = capture.handle if capture else msvcrt.get_osfhandle(output.fileno())
            for handle in (startup.hStdInput, startup.hStdOutput):
                os.set_handle_inheritable(handle, True)
            line = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
            try:
                ok = kernel.CreateProcessW(command[0], line, None, None, True,
                                           0x08000000, None, str(cwd) if cwd else None,
                                           ctypes.byref(startup), ctypes.byref(process))
                if not ok:
                    raise ctypes.WinError(ctypes.get_last_error())
                if capture:
                    capture.close_parent_write()
                if on_start is not None:
                    on_start(process.pid, process.tid)
                deadline = time.monotonic() + timeout
                # Short native waits also let KeyboardInterrupt cancel the owned engine.
                while True:
                    wait = kernel.WaitForSingleObject(process.process, 200)
                    if on_poll is not None and wait == 258:
                        on_poll()
                    if wait != 258 or time.monotonic() >= deadline:
                        break
                code = w.DWORD()
                if not kernel.GetExitCodeProcess(process.process, ctypes.byref(code)):
                    raise ctypes.WinError(ctypes.get_last_error())
            finally:
                # Drain even after timeout, callback failure or startup error;
                # the pipe reader must finish before its backing file closes.
                status = w.DWORD()
                if process.process and kernel.GetExitCodeProcess(process.process, ctypes.byref(status)) and status.value == 259:
                    kernel.TerminateProcess(process.process, 124)
                    kernel.WaitForSingleObject(process.process, 5000)
                if capture:
                    capture.finish()
            output.seek(0)
            if wait != 0:
                raise subprocess.TimeoutExpired(command, timeout, output=output.read())
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
