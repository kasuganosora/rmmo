import unittest
from summarize_completed_job_latency import summarize
from compare_completed_job_latency import require_same_cache_contract


def event(kind, at, generation=1, **details):
    return dict(path='same-source', generation=generation, event=kind, at_us=at, details=details)


class QueueLatencyTests(unittest.TestCase):
    def test_directory_rebuild_cannot_masquerade_as_equal_queue_work(self):
        warm={'map_profile': {'reference_index_hit': True,
                              'reference_index_rebuilt_before_models': False}}
        cold={'map_profile': {'reference_index_hit': False,
                              'reference_index_rebuilt_before_models': True}}
        self.assertEqual(require_same_cache_contract([warm, warm, warm])['map_profile'],
                         warm['map_profile'])
        with self.assertRaisesRegex(ValueError, 'Mixed directory'):
            require_same_cache_contract([cold, warm, warm])

    def test_return_cache_state_also_has_to_match(self):
        before={'return_map_profile': {'reference_index_hit': True}}
        after={'return_map_profile': {'reference_index_hit': False}}
        with self.assertRaisesRegex(ValueError, 'Mixed directory'):
            require_same_cache_contract([before, before, after])

    def test_overlap_is_not_double_counted_as_cpu(self):
        events=[event('dispatch',0),event('worker_finished',300,started_us=100),
                event('main_unit',350,start_us=250,duration_us=100,stage='accept'),event('slot_released',1000)]
        result=summarize(dict(completed_job_trace=dict(origin_us=0,dropped=0,events=list(reversed(events)))))
        self.assertEqual(result['jobs'][0]['unattributed_residence_ms'],.75)
        self.assertEqual(result['jobs'][0]['main_work_wall_ms'],.1)
        self.assertEqual(result['units'][0]['start_ms'],.25)

    def test_missing_exit_stays_unknown(self):
        result=summarize(dict(completed_job_trace=dict(origin_us=0,dropped=2,events=[event('dispatch',100)])))
        self.assertIsNone(result['jobs'][0]['queue_residence_ms'])
        self.assertFalse(result['jobs'][0]['complete'])
        self.assertFalse(result['unit_clock_available'])
        self.assertEqual(result['dropped'],2)

    def test_continuations_and_same_path_generations_are_separate(self):
        events=[event('dispatch',0),event('worker_finished',300,started_us=100),event('joined',310),
                event('worker_finished',700,started_us=400),event('joined',710),event('slot_released',900),
                event('dispatch',1000,2),event('slot_released',1200,2)]
        result=summarize(dict(completed_job_trace=dict(origin_us=0,dropped=0,events=events)))
        self.assertEqual([r['generation'] for r in result['jobs']],[1,2])
        self.assertEqual(result['jobs'][0]['worker_invocations'],2)
        self.assertEqual(result['jobs'][0]['worker_wall_ms'],.5)
        self.assertEqual(result['jobs'][0]['unattributed_residence_ms'],.4)


if __name__=='__main__':unittest.main()
