"""Discovery must not inspect unrelated applications or hide unreadable games."""
import unittest
from unittest.mock import patch

import psutil
import godot_process_monitor as monitor


class Process:
    def __init__(self, pid, name, *, denied=False, gone=False):
        self.info = {'pid': pid, 'name': name}
        self.denied = denied
        self.gone = gone
        self.queries = 0

    def as_dict(self, *, attrs):
        self.queries += 1
        if self.gone:
            raise psutil.NoSuchProcess(self.info['pid'])
        row = dict(self.info, cmdline=None if self.denied else ['test'], create_time=123.)
        return {key: row[key] for key in attrs}


class MonitorTests(unittest.TestCase):
    def test_unrelated_applications_never_receive_remote_detail_queries(self):
        games = [Process(1, 'GODOT.windows.editor.exe'), Process(2, 'blender.exe'),
                 Process(3, 'gdb.exe'), Process(4, 'cc1plus.exe')]
        unrelated = [Process(5, 'ChatGPT.exe'), Process(6, None), Process(7, 'python.exe')]
        with patch.object(monitor.psutil, 'process_iter', return_value=iter(games + unrelated)) as iterator:
            rows = monitor.workload_snapshot()
        self.assertEqual({row['pid'] for row in rows}, {1, 2, 3, 4})
        self.assertTrue(all(process.queries == 0 for process in unrelated))
        iterator.assert_called_once_with(['pid', 'name'])

    def test_denied_arguments_still_report_competing_engine(self):
        process = Process(1, 'godot.exe', denied=True)
        with patch.object(monitor.psutil, 'process_iter', return_value=iter([process])):
            rows = monitor.workload_snapshot()
        self.assertEqual(rows, [dict(process.info, cmdline=None, create_time=123.)])

    def test_departing_process_does_not_abort_discovery(self):
        processes = [Process(1, 'godot.exe', gone=True), Process(2, 'godot.exe')]
        with patch.object(monitor.psutil, 'process_iter', return_value=iter(processes)):
            self.assertEqual([r['pid'] for r in monitor.workload_snapshot()], [2])

    def test_named_sampler_filters_before_requesting_arguments(self):
        processes = [Process(1, 'godot.exe'), Process(2, 'blender.exe')]
        with patch.object(monitor.psutil, 'process_iter', return_value=iter(processes)):
            self.assertEqual(list(monitor.named_processes(('godot',))), processes[:1])
        self.assertTrue(all(process.queries == 0 for process in processes))


if __name__ == '__main__':
    unittest.main()
