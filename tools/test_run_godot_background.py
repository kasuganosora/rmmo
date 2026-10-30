"""Windows capture contracts, using owned tiny Python child processes only."""
import os
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
