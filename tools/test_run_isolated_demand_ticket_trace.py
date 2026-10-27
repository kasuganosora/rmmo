import copy
import json
import tempfile
import unittest
from pathlib import Path

import run_isolated_demand_ticket_trace as runner


class TicketRunnerContract(unittest.TestCase):
    def sample(self):
        event = {'id': 'player', 'id_truncated': False, 'complete_members': True,
                 'frame': 11, 'input_rows': 4, 'kind_excluded': 1, 'published': 0,
                 'new_uuid': 1, 'duplicate_uuid': 2, 'winner_changes': 1, 'support_visits': 3}
        return {'demand_ticket_status': 'complete_return_leg', 'demand_ticket_phase': 'white_native_return',
                'demand_ticket_capacity': runner.CAPACITY, 'failures': [],
                'demand_ticket_boundaries_dropped': 0,
                'demand_ticket_boundaries': [
                    {'kind': 'start', 'phase': 'white_native_return', 'frame': 10, 'ticks_us': 100},
                    {'kind': 'end', 'phase': 'white_native_reload', 'frame': 20, 'ticks_us': 200}],
                'demand_ticket_trace': {'capacity': runner.CAPACITY, 'dropped': 0, 'untracked': 0,
                                        'evicted': 0, 'events': [event]}}

    def status(self, data, phase='white_native_return'):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sample.json'
            path.write_text(json.dumps(data), encoding='utf-8')
            return runner.capture_status(path, phase)

    def test_disjoint_roots_rejects_all_nested_pairs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            roots = [root / name for name in ('overlay', 'sample', 'user', 'fixture')]
            runner.disjoint_roots(*roots)
            for first in range(4):
                for second in range(first + 1, 4):
                    changed = roots.copy()
                    changed[second] = changed[first] / 'nested'
                    with self.subTest(first=first, second=second):
                        with self.assertRaises(ValueError): runner.disjoint_roots(*changed)
            with self.assertRaises(ValueError): runner.disjoint_roots(roots[0], roots[0], roots[2], roots[3])

    def test_class_and_uid_cache_identity_captures_missing_and_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before = runner.class_cache_snapshot(root)
            self.assertEqual(set(before), set(runner.CACHE_FILES))
            self.assertTrue(all(value is None for value in before.values()))
            (root / '.godot').mkdir()
            (root / runner.CACHE_FILES[0]).write_bytes(b'class cache')
            (root / runner.CACHE_FILES[1]).write_bytes(b'uid cache')
            after = runner.class_cache_snapshot(root)
            self.assertNotEqual(before, after)
            (root / runner.CACHE_FILES[1]).write_bytes(b'different uid')
            self.assertNotEqual(after, runner.class_cache_snapshot(root))

    def test_valid_capture_and_membership_unknown_are_distinct(self):
        data = self.sample()
        self.assertTrue(self.status(data)['valid'])
        data['demand_ticket_trace']['evicted'] = 1
        data['demand_ticket_trace']['events'][0]['complete_members'] = False
        result = self.status(data)
        self.assertTrue(result['valid'])
        self.assertEqual(result['incomplete_members'], 1)
        self.assertEqual(result['evicted'], 1)

    def test_malformed_or_incomplete_capture_is_rejected(self):
        variants = []
        def add(change):
            item = copy.deepcopy(self.sample()); change(item); variants.append(item)
        add(lambda d: d.update(demand_ticket_phase='white_walk_return'))
        add(lambda d: d.update(demand_ticket_capacity=1))
        add(lambda d: d['demand_ticket_trace'].update(capacity=1))
        add(lambda d: d['demand_ticket_trace'].update(events=[]))
        add(lambda d: d['demand_ticket_trace'].update(dropped=1))
        add(lambda d: d['demand_ticket_trace'].update(untracked=1))
        add(lambda d: d['demand_ticket_trace']['events'][0].update(frame=9))
        add(lambda d: d['demand_ticket_trace']['events'][0].update(input_rows=5))
        add(lambda d: d['demand_ticket_trace']['events'][0].update(winner_changes=3))
        add(lambda d: d['demand_ticket_trace']['events'][0].update(id_truncated=True))
        add(lambda d: d['demand_ticket_boundaries'][1].update(ticks_us=99))
        add(lambda d: d['demand_ticket_boundaries'][1].update(phase='white_native_return'))
        add(lambda d: d.update(demand_ticket_boundaries_dropped=1))
        add(lambda d: d.update(failures=['failure']))
        for index, value in enumerate(variants):
            with self.subTest(index=index): self.assertFalse(self.status(value)['valid'])

    def test_split_walk_requires_both_observed_segments(self):
        data = self.sample()
        data['demand_ticket_phase'] = 'white_walk_return'
        data['demand_ticket_boundaries'][0]['phase'] = 'white_walk_return_straight'
        data['demand_ticket_boundaries'][-1]['phase'] = 'white_walk_reload'
        self.assertFalse(self.status(data, 'white_walk_return')['valid'])
        data['demand_ticket_boundaries'].insert(1, {'kind': 'transition', 'phase': 'white_walk_return_turn', 'frame': 15, 'ticks_us': 150})
        self.assertTrue(self.status(data, 'white_walk_return')['valid'])


if __name__ == '__main__':
    unittest.main()
