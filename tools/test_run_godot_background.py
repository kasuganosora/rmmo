"""Windows capture contracts, using owned tiny Python child processes only."""
import os
import ctypes
from ctypes import wintypes
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

import psutil
from run_godot_background import run_background


@unittest.skipUnless(os.name == 'nt', 'private-desktop runner is Windows-only')
class BackgroundCaptureTests(unittest.TestCase):
    def tearDown(self):
        self.assertFalse(any(t.name == 'RMMO output capture' for t in threading.enumerate()))

    def child(self, source, *args, **options):
        return run_background([sys.executable, '-c', source, *args], timeout=options.pop('timeout', 15), **options)

    def test_large_stdout_stderr_and_unicode_are_byte_exact(self):
        source = "import os;os.write(1,bytes(range(256))*4096);os.write(2,'stderr 中文尾部'.encode('utf-8'))"
        result = self.child(source)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, bytes(range(256))*4096 + 'stderr 中文尾部'.encode('utf-8'))

    def test_nonzero_exit_and_last_bytes_survive(self):
        result = self.child("import os;os.write(2,b'last error');os._exit(7)")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, b'last error')

    def test_borrowed_desktop_allows_owned_native_window_close(self):
        user = ctypes.WinDLL('user32', use_last_error=True)
        user.SetThreadDesktop.argtypes = [wintypes.HANDLE]
        user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
        state = {}
        source = '''import ctypes,sys,time
from ctypes import wintypes as w
from pathlib import Path
u=ctypes.WinDLL('user32',use_last_error=True)
u.CreateWindowExW.argtypes=[w.DWORD,w.LPCWSTR,w.LPCWSTR,w.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,w.HWND,w.HMENU,w.HINSTANCE,ctypes.c_void_p]
u.CreateWindowExW.restype=w.HWND
u.IsWindow.argtypes=[w.HWND]
u.PeekMessageW.argtypes=[ctypes.POINTER(w.MSG),w.HWND,w.UINT,w.UINT,w.UINT]
u.DispatchMessageW.argtypes=[ctypes.POINTER(w.MSG)]
hwnd=u.CreateWindowExW(0,'STATIC','Owned native close',0xcf0000,0,0,32,32,None,None,None,None)
assert hwnd,ctypes.get_last_error()
Path(sys.argv[1]).write_text(str(hwnd))
message=w.MSG()
while u.IsWindow(hwnd):
    if u.PeekMessageW(ctypes.byref(message),None,0,0,1):u.DispatchMessageW(ctypes.byref(message))
    else:time.sleep(.01)
print('NATIVE_WINDOW_CLOSED',flush=True)
'''
        with tempfile.TemporaryDirectory(prefix='rmmo_native_close_') as folder:
            ready = Path(folder) / 'hwnd.txt'

            def poll():
                if state.get('sent') or not ready.exists():
                    return
                hwnd = int(ready.read_text())
                errors = []

                def send():
                    try:
                        self.assertTrue(user.SetThreadDesktop(state['desktop']))
                        owner = wintypes.DWORD()
                        self.assertTrue(user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner)))
                        self.assertEqual(owner.value, state['pid'])
                        self.assertTrue(user.PostMessageW(hwnd, 0x10, 0, 0))
                    except BaseException as error:
                        errors.append(error)

                sender = threading.Thread(target=send)
                sender.start(); sender.join(timeout=3)
                self.assertFalse(sender.is_alive())
                if errors:
                    raise errors[0]
                state['sent'] = True

            result = self.child(source, str(ready), on_start=lambda pid, tid: state.update(pid=pid),
                                on_desktop=lambda handle: state.update(desktop=handle), on_poll=poll)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(state['sent'])
            self.assertIn(b'NATIVE_WINDOW_CLOSED', result.stdout)

    def test_timeout_drains_output_and_stops_only_owned_child(self):
        owned = []
        with self.assertRaises(subprocess.TimeoutExpired) as error:
            self.child("import os,time;os.write(1,b'before timeout');time.sleep(20)", timeout=.6,
                       on_start=lambda pid, tid: owned.append(psutil.Process(pid)))
        self.assertEqual(error.exception.stdout, b'before timeout')
        self.assertFalse(owned[0].is_running())

    def test_callback_failure_closes_pipe_and_owned_process(self):
        owned = []
        def fail(pid, tid):
            owned.append(psutil.Process(pid))
            raise ValueError('test start callback')
        with self.assertRaisesRegex(ValueError, 'test start callback'):
            self.child('import time;time.sleep(20)', on_start=fail)
        self.assertFalse(owned[0].is_running())

    def test_failed_launch_closes_reader(self):
        with self.assertRaises(OSError):
            run_background(['Z:/rmmo_missing_test_executable.exe'], timeout=1)

    def test_unexpected_inherited_writer_is_not_silently_truncated(self):
        # The runner must bound its own read after the original process exits,
        # without terminating an unowned descendant or silently losing output.
        with tempfile.TemporaryDirectory(prefix='rmmo_capture_contract_') as folder:
            receipt = Path(folder)/'owned_descendant.txt'
            source = ("import os,subprocess,sys;from pathlib import Path;"
                      "p=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],"
                      "close_fds=False,creationflags=subprocess.CREATE_NO_WINDOW);"
                      "Path(sys.argv[1]).write_text(str(p.pid));os._exit(0)")
            began = time.time()
            try:
                with self.assertRaisesRegex(RuntimeError, 'output pipe did not close'):
                    self.child(source, str(receipt))
            finally:
                if receipt.exists():
                    descendant = psutil.Process(int(receipt.read_text()))
                    self.assertGreaterEqual(descendant.create_time(), began-1)
                    self.assertEqual(descendant.cmdline()[-1], 'import time;time.sleep(20)')
                    descendant.terminate();descendant.wait(timeout=5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
