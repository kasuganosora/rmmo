"""Correlate Godot wall spans with the owned process's sampled CPU counters."""
import argparse
from bisect import bisect_right
import json
from pathlib import Path


class Counters:
    def __init__(self, capture):
        self.main_tid = capture['metadata']['main_win32_tid']
        self.process_tid = capture['metadata'].get('process_counter_tid')
        self.series = {}
        previous = {}; offsets = {}
        for row in capture['samples']:
            for tid, cpu in row[2]:
                times, values = self.series.setdefault(tid, ([], []))
                # Win32 can reuse a departed worker TID. Preserve cumulative
                # execution across generations; the primary thread stays live.
                if tid in previous and cpu<previous[tid]:offsets[tid]=offsets.get(tid,0)+previous[tid]
                previous[tid]=cpu
                times.append(row[0] / 1000)
                values.append(cpu + offsets.get(tid,0))

    @staticmethod
    def value(series, when):
        times, values = series
        at = bisect_right(times, when)
        if at == 0:
            return 0
        if at == len(times):
            return values[-1]
        fraction = (when - times[at - 1]) / (times[at] - times[at - 1])
        return values[at - 1] + fraction * (values[at] - values[at - 1])

    def span(self, start, end):
        deltas = {tid: max(0, self.value(series, end) - self.value(series, start)) / 1000
                  for tid, series in self.series.items()}
        return {'wall_ms': round((end - start) / 1000, 3),
                'main_cpu_ms': round(deltas.get(self.main_tid, 0), 3),
                'all_threads_cpu_ms': round(deltas[self.process_tid] if self.process_tid is not None else sum(deltas.values()), 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--samples', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding='utf-8'))
    capture = json.loads(args.samples.read_text(encoding='utf-8'))
    if report['pid'] != capture['metadata']['pid']:
        parser.error('report and samples belong to different processes')
    counters = Counters(capture)
    anchor = report.get('cpu_time_anchor', {})
    offset = (anchor['unix_us'] - anchor['ticks_us']) if anchor else report['anchor_unix_us'] - report['anchor_ticks_us']
    output = {'counter_scope': 'sampled thread execution, not exclusive call-stack attribution',
              'caveat': '10 ms sampling plus Windows scheduler CPU accounting granularity; asynchronous wall spans contain other work',
              'metadata': capture['metadata'], 'spans': []}
    if 'spans' in report:
        for span in report['spans']:
            output['spans'].append({'label': span['mode'], **counters.span(span['start_us'] + offset, span['end_us'] + offset)})
    else:
        for frame in sorted(report['frames'], key=lambda row: row['ms'], reverse=True)[:15]:
            end = report['begin_ticks_us'] + frame['at_ms'] * 1000 + offset
            output['spans'].append({'label': 'frame:' + frame['phase'],
                                    **counters.span(end - frame['ms'] * 1000, end)})
        labels = {'deferred.publish_commit', 'method.world_stream.retire_specs',
                  'game.asset_generate', 'game.reference_integrity'}
        selected = [event for event in report['monitor']['trace']['events']
                    if event['thread_id'] == 1 and event['label'] in labels and event['duration_us'] >= 50000]
        for event in sorted(selected, key=lambda row: row['duration_us'], reverse=True)[:15]:
            output['spans'].append({'label': event['label'],
                                    **counters.span(event['start_us'] + offset, event['end_us'] + offset)})
    if args.output:
        args.output.write_text(json.dumps(output, indent=2), encoding='utf-8')
    print(json.dumps({'sampling_metadata': output['metadata'], 'spans': output['spans']}, indent=2))


if __name__ == '__main__':
    main()
