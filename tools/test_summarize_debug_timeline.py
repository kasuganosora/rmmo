import csv
import json
from pathlib import Path
import struct
import tempfile
import unittest

from summarize_debug_timeline import analyze, export, read_capture


class TimelineTests(unittest.TestCase):
    def header(self, count=0, cpu=False):
        return dict(version=1, format='QQQqqIIQ', byte_order='little', event_bytes=56,
                    events=count, labels=['unknown','outer','inner'], cpu_clock=cpu,
                    start_us=0, end_us=100, dropped=0)

    def test_nested_and_parallel_spans_do_not_double_count(self):
        rows=[(10,0,1,11,0,1,1,4),(20,0,2,11,0,2,1,4),
              (25,0,3,12,0,1,1,5),(40,0,2,0,0,0,2,4),
              (70,0,3,0,0,0,2,5),(80,0,1,0,0,0,2,4)]
        result=analyze(self.header(),rows)
        spans={r['span']:r for r in result['spans']}
        self.assertEqual(spans[1]['wall_us'],70)
        self.assertEqual(spans[1]['exclusive_wall_us'],50)
        self.assertEqual(spans[2]['parent_span'],1)
        self.assertEqual(spans[3]['exclusive_wall_us'],45)
        self.assertTrue(all(r['cpu_us'] is None for r in spans.values()))

    def test_unfinished_and_orphan_events_are_reported(self):
        result=analyze(self.header(),[(10,0,1,0,0,1,1,4),(20,0,2,0,0,0,2,4)])
        self.assertEqual(result['incomplete_spans'],1)
        self.assertEqual(len(result['orphan_ends']),1)
        self.assertIsNone(result['spans'][0]['wall_us'])

    def test_coarse_cpu_quantization_is_not_clamped_or_called_idle(self):
        result=analyze(self.header(cpu=True),[(10,0,1,0,0,1,1,4),(20,15000,1,0,0,0,2,4)])
        self.assertEqual(result['spans'][0]['cpu_us'],15000)
        self.assertEqual(result['spans'][0]['wall_us'],10)

    def test_binary_round_trip_and_truncation(self):
        header=self.header(2)
        rows=[(10,0,1,11,0,1,1,4),(20,0,1,0,0,0,2,4)]
        metadata=json.dumps(header).encode()
        data=b'RMMOTRC1'+struct.pack('<Q',len(metadata))+metadata+b''.join(struct.pack('<QQQqqIIQ',*r) for r in rows)
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'capture.rmtrace';path.write_bytes(data)
            actual,events=read_capture(path)
            self.assertEqual(actual,header);self.assertEqual(events,rows)
            path.write_bytes(data[:-1])
            with self.assertRaisesRegex(ValueError,'Truncated event'):read_capture(path)
            path.write_bytes(data[:-56])
            with self.assertRaisesRegex(ValueError,'count disagrees'):read_capture(path)

    def test_equal_timestamp_preserves_each_writers_begin_before_end(self):
        rows=[(10,0,1,11,0,1,1,4),(10,0,1,0,0,0,2,4)]
        result=analyze(self.header(),rows)
        self.assertEqual(result['spans'][0]['wall_us'],0)
        self.assertEqual(result['orphan_ends'],[])

    def test_equal_boundary_nested_scopes_keep_actual_begin_order(self):
        rows=[(10,0,1,0,0,1,1,4),(10,0,2,0,0,2,1,4),
              (20,0,2,0,0,0,2,4),(20,0,1,0,0,0,2,4)]
        spans={r['span']:r for r in analyze(self.header(),rows)['spans']}
        self.assertEqual(spans[2]['parent_span'],1)
        self.assertEqual(spans[1]['exclusive_wall_us'],0)

    def test_crossing_spans_do_not_claim_exclusive_work(self):
        rows=[(10,0,1,0,0,1,1,4),(20,0,2,0,0,2,1,4),
              (30,0,1,0,0,0,2,4),(40,0,2,0,0,0,2,4)]
        result=analyze(self.header(),rows)
        self.assertEqual(result['crossing_spans'],1)
        self.assertTrue(all(r['exclusive_wall_us'] is None for r in result['rankings']))

    def test_native_tasks_from_different_pools_keep_separate_queues(self):
        header=self.header();header['labels']=['unknown','worker.enqueue','worker.execute','worker.wait']
        rows=[(1,0,0,7,100,1,0,1),(2,0,0,7,200,1,0,1),
              (3,0,1,7,100,2,1,4),(4,0,2,7,200,2,1,5),
              (5,0,1,0,0,0,2,4),(6,0,2,0,0,0,2,5)]
        jobs=analyze(header,rows)['jobs']
        self.assertEqual(len(jobs),2)
        self.assertEqual({r['context'] for r in jobs},{100,200})
        self.assertTrue(all(r['enqueue_to_first_start_us']==2 for r in jobs))

    def test_names_link_by_task_and_context_and_conflicts_are_visible(self):
        header=self.header();header['labels']=['unknown','worker.name','worker.enqueue','worker.execute']
        header['task_names']={'1':'prepare/石材','2':'release/木材','3':'conflicting'}
        rows=[(1,0,1,7,100,1,0,1),(2,0,0,7,100,2,0,1),
              (3,0,2,7,200,1,0,5),(4,0,3,7,200,1,0,5),
              (5,0,10,7,100,3,1,4),(6,0,11,7,200,3,1,5),
              (7,0,10,0,0,0,2,4),(8,0,11,0,0,0,2,5)]
        result=analyze(header,rows)
        self.assertEqual(result['spans'][0]['task_name'],'prepare/石材')
        self.assertEqual(len(result['task_rankings']),2)
        self.assertEqual(result['task_name_conflicts'],[dict(context=200,task=7,names=['conflicting','release/木材'])])
        del header['task_names']['1']
        with self.assertRaisesRegex(ValueError,'Missing task name'):analyze(header,rows)

    def test_csv_preserves_unicode_names_and_wait_execution_relationship(self):
        header=self.header(6);header['columns']='wall_us,cpu_us,span,task,value,label,kind,thread_id'
        header['labels']=['unknown','worker.name','worker.enqueue','worker.execute','worker.wait']
        task_name='prepare, "石材"\nphase2'
        header['task_names']={'1':task_name}
        rows=[(1,0,1,7,100,1,0,1),(2,0,0,7,100,2,0,1),
              (3,0,10,7,100,3,1,4),(4,0,11,7,100,4,1,1),
              (7,0,10,0,0,0,2,4),(8,0,11,0,0,0,2,1)]
        meta=json.dumps(header).encode()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);path=root/'capture.rmtrace'
            path.write_bytes(b'RMMOTRC1'+struct.pack('<Q',len(meta))+meta+b''.join(struct.pack('<QQQqqIIQ',*r) for r in rows))
            export(path,root/'decoded')
            with (root/'decoded/dependencies.csv').open(encoding='utf-8-sig',newline='') as file:
                records=list(csv.DictReader(file))
            self.assertEqual(len(records),1)
            self.assertEqual(records[0]['task_name'],task_name)
            self.assertEqual(records[0]['waiter_thread'],'1')
            self.assertEqual(records[0]['executor_thread'],'4')
            self.assertEqual(records[0]['enqueue_to_first_start_us'],'1')
            self.assertEqual(records[0]['executor_wall_us'],'4')

    def test_wait_links_to_worker_and_keeps_group_segments(self):
        header=self.header();header['labels']=['unknown','worker.enqueue','worker.execute','worker.wait']
        rows=[(1,0,0,7,100,1,0,1),(2,0,11,7,100,2,1,4),
              (3,0,12,7,100,2,1,5),(4,0,13,7,100,3,1,1),
              (8,0,11,0,0,0,2,4),(9,0,12,0,0,0,2,5),(10,0,13,0,0,0,2,1)]
        result=analyze(header,rows)
        self.assertEqual(len(result['dependencies']),1)
        dep=result['dependencies'][0]
        self.assertEqual(dep['waiter_thread'],1)
        self.assertEqual(dep['enqueue_to_first_start_us'],1)
        self.assertEqual({e['thread'] for e in dep['executions']},{4,5})
        self.assertEqual(dep['wait_wall_us'],6)


if __name__=='__main__':unittest.main()
