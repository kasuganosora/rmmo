import json
from pathlib import Path
import tempfile
import unittest

import prepare_demand_ticket_overlay as overlay
import run_isolated_demand_ticket_trace as runner


class TicketOverlayTest(unittest.TestCase):
    def test_injection_is_exact_and_fail_closed(self):
        source = (overlay.ROOT / overlay.LOADER).read_text(encoding='utf-8')
        result = overlay.instrument(source)
        self.assertIn('_demand_ticket_trace.member(ticket_trace,item.get("record"))', result)
        self.assertIn('ticket_trace.winner_changes+=1', result)
        with self.assertRaises(ValueError):
            overlay.instrument(result)
        with self.assertRaises(ValueError):
            overlay.instrument(source.replace('var eligible:Array=[]', 'var missing:Array=[]'))

    def test_command_keeps_fixture_and_records_overlay(self):
        old_root = runner.base.ROOT
        try:
            runner.base.ROOT = Path('D:/diagnostic-overlay').resolve()
            content = Path('D:/test-content').resolve()
            map_path = content / 'map.gltf'
            template = ['D:/godot.exe', '--path', str(runner.SOURCE_ROOT), '--script',
                        'res://tools/profile_axel_worker_capacity.gd', '--test-map='+str(map_path),
                        '--test-content-root='+str(content), '--output=old.json', '--mesh-only', '--native-only', '--full-material-stage']
            cmd = runner.make_command(template, Path('D:/sample'), 'white_native_return', content, map_path, False)
            self.assertEqual(cmd[cmd.index('--path')+1], str(runner.base.ROOT))
            self.assertIn('res://tools/profile_axel_demand_tickets.gd', cmd)
            self.assertIn('--demand-ticket-capacity=16384', cmd)
            with self.assertRaises(ValueError):
                runner.make_command(template + ['--demand-ticket-trace'], Path('D:/sample'), 'white_native_return', content, map_path, False)
            with self.assertRaises(ValueError):
                runner.make_command(template + ['--white-material'], Path('D:/sample'), 'white_native_return', content, map_path, False)
            with self.assertRaises(ValueError):
                runner.make_command([value for value in template if value != '--full-material-stage'], Path('D:/sample'), 'white_native_return', content, map_path, False)
        finally:
            runner.base.ROOT = old_root

    def test_capture_requires_complete_and_no_overflow(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'sample.json'
            phase = 'white_native_return'
            self.assertFalse(runner.capture_status(p, phase)['valid'])
            sample = {
                'demand_ticket_status': 'complete_return_leg', 'demand_ticket_phase': phase,
                'demand_ticket_capacity': runner.CAPACITY, 'demand_ticket_boundaries_dropped': 0, 'failures': [],
                'demand_ticket_boundaries': [
                    {'kind': 'start', 'phase': phase, 'frame': 10, 'ticks_us': 100},
                    {'kind': 'end', 'phase': 'white_native_reload', 'frame': 20, 'ticks_us': 200},
                ],
                'demand_ticket_trace': {
                    'capacity': runner.CAPACITY, 'dropped': 0, 'untracked': 0, 'evicted': 0,
                    'events': [{'id': 'player', 'id_truncated': False, 'complete_members': True,
                                'frame': 11, 'input_rows': 1, 'kind_excluded': 0, 'published': 0,
                                'new_uuid': 1, 'duplicate_uuid': 0, 'winner_changes': 0, 'support_visits': 0}],
                },
            }
            p.write_text(json.dumps(sample));self.assertTrue(runner.capture_status(p, phase)['valid'])
            sample['demand_ticket_trace']['dropped'] = 1
            p.write_text(json.dumps(sample));self.assertFalse(runner.capture_status(p, phase)['valid'])
            sample['demand_ticket_trace']['dropped'] = 0;sample['demand_ticket_trace']['untracked'] = 1
            p.write_text(json.dumps(sample));self.assertFalse(runner.capture_status(p, phase)['valid'])
            sample['demand_ticket_trace']['untracked'] = 0;sample['demand_ticket_status'] = 'not_started'
            p.write_text(json.dumps(sample));self.assertFalse(runner.capture_status(p, phase)['valid'])
            sample['demand_ticket_status'] = 'complete_return_leg'
            sample['demand_ticket_trace']['events'][0]['input_rows'] = 2
            p.write_text(json.dumps(sample));self.assertFalse(runner.capture_status(p, phase)['valid'])


if __name__ == '__main__':
    unittest.main()
