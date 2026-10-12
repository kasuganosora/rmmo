"""Analyze queue-lane ABBA without conflating worker wall spans and CPU work."""
import json
from pathlib import Path
import statistics
import sys

ROOT = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/review_artifacts')


def union_us(spans):
    merged = []
    for begin, end in sorted(spans):
        if not merged or begin > merged[-1][1]:
            merged.append([begin, end])
        else:
            merged[-1][1] = max(end, merged[-1][1])
    return sum(end - begin for begin, end in merged)


def main():
    tag = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--tag=')), 'editor_lanes')
    assert tag in ['editor_lanes', 'editor_lanes_v2']
    source = json.loads((OUT / f'{tag}_abba_20261011.json').read_text(encoding='utf-8'))
    rows = []
    for run in source['rows']:
        data = json.loads(Path(run['report']).read_text(encoding='utf-8'))
        hw = json.loads(Path(run['hardware']).read_text(encoding='utf-8'))
        samples = [s for s in hw['samples'] if data['load_start_epoch_s'] <= s['epoch_s'] <= data['load_end_epoch_s']]
        assert len(samples) >= 2
        first, last = samples[0], samples[-1]
        wall = last['monotonic_s'] - first['monotonic_s']
        cpu = (last['cpu_s'] - first['cpu_s']) / wall
        events = data['load_trace']['events']
        start = min(e['start_us'] for e in events if e['label'] == 'editor.source_read')
        validate_end = max(e['end_us'] for e in events if e['label'] == 'editor.validate')
        terrain = [e for e in events if e['label'] == 'editor.terrain_prepare']
        models = [e for e in events if e['label'] == 'editor.model_parse']
        first_model = min(e['start_us'] for e in models)
        intersections = [(max(t['start_us'], m['start_us']), min(t['end_us'], m['end_us']))
                         for t in terrain for m in models
                         if max(t['start_us'], m['start_us']) < min(t['end_us'], m['end_us'])]
        boundaries = sorted([(e['start_us'], 1) for e in models] + [(e['end_us'], -1) for e in models])
        active = 0
        intervals = {}
        previous = boundaries[0][0]
        for stamp, delta in boundaries:
            intervals[active] = intervals.get(active, 0) + stamp - previous
            active += delta
            previous = stamp
        timings = data['load_result']['timings']
        queue = timings['preparation']
        tasks = queue['diagnostics']['tasks']
        assert queue['diagnostics']['enabled'] and not queue['diagnostics']['tasks_dropped']
        lane_times = {}
        for lane in ['model', 'texture', 'neutral']:
            group = [dict(key=key, **value) for key, value in tasks.items() if value['lane'] == lane]
            dispatched = [t for t in group if t['first_start_us'] > 0]
            lane_times[lane] = {
                'tasks': len(group), 'attempts': sum(t['attempts'] for t in group),
                'restarted': [{k: t[k] for k in ['key', 'attempts']} for t in group if t['attempts'] > 1],
                'first_dispatch_from_source_ms': (min(t['first_start_us'] for t in dispatched) - start) / 1000 if dispatched else None,
                'blocked_observed_ms_sum': sum(t['blocked_observed_us'] for t in group) / 1000,
                'enqueue_to_first_dispatch_ms_sum': sum(t['first_start_us'] - t['enqueued_us'] for t in dispatched) / 1000,
            }
        first_models = sorted([(key, value) for key, value in tasks.items() if value['lane'] == 'model'],
                              key=lambda item: item[1]['first_start_us'])[:3]
        rows.append({
            'label': run['label'], 'mode': run['mode'], 'load_ms': data['load_ms'],
            'asset_wait_ms': run['units']['asset_wait']['total_ms'],
            'prefab_texture_wait_ms': run['units']['prefab_texture_wait']['total_ms'],
            'terrain_texture_wait_ms': run['units']['terrain_texture_wait']['total_ms'],
            'validation_ms': timings['validate_ms'],
            'passes': run['passes'], 'warnings': run['warnings'],
            'first_model_from_source_ms': (first_model - start) / 1000,
            'first_model_after_validation_ms': (first_model - validate_end) / 1000,
            'model_terrain_overlap_union_ms': union_us(intersections) / 1000,
            'model_activity_ms': {str(k): v / 1000 for k, v in intervals.items()},
            'model_worker_wall_sum_ms': sum(e['end_us'] - e['start_us'] for e in models) / 1000,
            'first_three_model_lifecycle': [dict(
                key=key, attempts=value['attempts'],
                first_dispatch_from_source_ms=(value['first_start_us'] - start) / 1000,
                last_join_from_source_ms=(value['last_join_us'] - start) / 1000,
                last_acquire_from_source_ms=(value['last_acquire_us'] - start) / 1000,
                final_join_to_acquire_ms=(value['last_acquire_us'] - value['last_join_us']) / 1000,
            ) for key, value in first_models],
            'lane_times': lane_times, 'queue': queue, 'lookahead': run['lookahead'],
            'hardware': {
                'samples': len(samples), 'sampled_wall_s': wall, 'cpu_equivalents': cpu,
                'logical_cpus': hw['logical_cpus'], 'cpu_percent_total_logical': 100 * cpu / hw['logical_cpus'],
                'peak_rss_bytes': max(s['rss_bytes'] for s in samples),
                'peak_private_bytes': max(s.get('private_bytes') or 0 for s in samples),
                'logical_read_bytes': last['read_bytes'] - first['read_bytes'],
                'sampler_mean_ms': statistics.mean(s['sampler_ms'] for s in samples),
                'errors': hw['errors'], 'gpu_errors': hw['gpu_errors'],
            },
            'trace_dropped': data['load_trace']['dropped'], 'report': run['report'], 'hardware_report': run['hardware'],
        })
    result = {
        'rows': rows, 'map_sha': source['map_sha'], 'source_fingerprint': source['source_fingerprint'],
        'scope': 'Excluded FIFO warm then FIFO/fair/fair/FIFO. Same native footprints, workers2/budget4GiB/ready4. CPU samples within loading epoch. Worker intervals include waiting; lane blocked durations overlap and include pump gaps, not CPU or removable critical-path time. Model activity covers first model start to last return. Terrain overlap is interval union, not sum. No OS/disk-cache reset or cache-cold claim.',
    }
    if len(rows) == 5:
        result['means'] = {}
        for mode in ['fifo', 'fair']:
            group = [r for r in rows if r['mode'] == mode and r['label'] != 'warm']
            result['means'][mode] = {key: statistics.mean(r[key] for r in group) for key in [
                'load_ms', 'asset_wait_ms', 'prefab_texture_wait_ms', 'terrain_texture_wait_ms',
                'first_model_from_source_ms', 'first_model_after_validation_ms', 'model_terrain_overlap_union_ms',
            ]}
            result['means'][mode].update({key: statistics.mean(r['hardware'][key] for r in group) for key in [
                'cpu_equivalents', 'peak_rss_bytes', 'peak_private_bytes',
            ]})
        result['load_change_percent'] = 100 * (result['means']['fair']['load_ms'] / result['means']['fifo']['load_ms'] - 1)
    output = ROOT / f'review_artifacts/{tag}_analysis_20261011.json'
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result.get('means', {}), indent=2))
    for row in rows:
        print(json.dumps({key: row[key] for key in ['label', 'load_ms', 'asset_wait_ms', 'first_model_from_source_ms',
                                                  'model_terrain_overlap_union_ms', 'passes', 'warnings', 'hardware']}))


if __name__ == '__main__':
    main()
