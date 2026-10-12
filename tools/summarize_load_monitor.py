"""Correlate opt-in Godot load events with owned-process Windows samples."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re


def hardware_span(hardware, start, end):
    duration = end-start
    if duration <= 0:
        return {}
    cpu = main_cpu = read = coverage = 0.0
    gpu = defaultdict(float)
    gpu_coverage = defaultdict(float)
    peak_rss = peak_private = peak_dedicated = 0
    origin = hardware['samples'][0] if hardware['samples'] else {}
    for previous, sample in zip(hardware['samples'], hardware['samples'][1:]):
        interval = sample['monotonic_s']-previous['monotonic_s']
        # Use a fixed clock mapping so sampling cost/clock jitter cannot create
        # overlapping hardware intervals and coverage greater than wall time.
        stop = origin['epoch_s'] + sample['monotonic_s']-origin['monotonic_s']
        overlap = max(0.0, min(end, stop)-max(start, stop-interval))
        if not overlap:
            continue
        coverage += overlap
        cpu += sample.get('cpu_equivalents', 0)*overlap
        read += sample.get('read_bytes_per_s', 0)*overlap
        main_cpu += sum(t['cpu_equivalents'] for t in sample.get('threads', []) if t['id']==hardware.get('main_thread_id'))*overlap
        peak_rss = max(peak_rss, sample['rss_bytes'])
        peak_private = max(peak_private, sample.get('private_bytes') or 0)
        values = sample.get('gpu', {}).get('engines', {}).get('items', {})
        by_type = defaultdict(float)
        for instance, value in values.items():
            match = re.search(r'engtype_(.+)$', instance)
            if match:
                by_type[match[1]] = max(by_type[match[1]], value)
        for kind, value in by_type.items():
            gpu[kind] += value*overlap
            gpu_coverage[kind] += overlap
        peak_dedicated = max(peak_dedicated, sum(sample.get('gpu', {}).get('dedicated', {}).get('items', {}).values()))
    return {'wall_s': duration, 'cpu_seconds': cpu, 'cpu_equivalents': cpu/coverage if coverage else None,
            'cpu_percent_total_logical': cpu/coverage/hardware['logical_cpus']*100 if coverage else None,
            'main_thread_cpu_seconds': main_cpu, 'main_thread_cpu_equivalents': main_cpu/coverage if coverage else None,
            'logical_read_mib': read/2**20, 'rss_peak_gib': peak_rss/2**30,
            'private_peak_gib': peak_private/2**30, 'dedicated_gpu_peak_gib': peak_dedicated/2**30,
            'sampling_coverage_s': coverage,
            'gpu_engine_busy_percent': {k: gpu[k]/gpu_coverage[k] for k in gpu},
            'gpu_valid_coverage_s': dict(gpu_coverage)}


def hardware_windows(hardware, windows):
    """Sum disjoint phase intervals rather than including other phases' gaps."""
    rows = [hardware_span(hardware, start, end) for start, end in windows if end > start]
    if not rows:
        return {}
    result = {key: sum(row[key] for row in rows) for key in
              ['wall_s', 'cpu_seconds', 'main_thread_cpu_seconds', 'logical_read_mib', 'sampling_coverage_s']}
    coverage = result['sampling_coverage_s']
    result['cpu_equivalents'] = result['cpu_seconds']/coverage if coverage else None
    result['cpu_percent_total_logical'] = result['cpu_equivalents']/hardware['logical_cpus']*100 if coverage else None
    result['main_thread_cpu_equivalents'] = result['main_thread_cpu_seconds']/coverage if coverage else None
    for key in ['rss_peak_gib', 'private_peak_gib', 'dedicated_gpu_peak_gib']:
        result[key] = max(row[key] for row in rows)
    kinds = set().union(*(row['gpu_valid_coverage_s'] for row in rows))
    result['gpu_valid_coverage_s'] = {k: sum(row['gpu_valid_coverage_s'].get(k, 0) for row in rows) for k in kinds}
    result['gpu_engine_busy_percent'] = {
        k: sum(row['gpu_engine_busy_percent'].get(k, 0)*row['gpu_valid_coverage_s'].get(k, 0) for row in rows)
        /result['gpu_valid_coverage_s'][k] for k in kinds if result['gpu_valid_coverage_s'][k]}
    return result


def phase_name(label):
    return re.sub(r'\s+\d+\s*/\s*\d+$', '', label)


def summarize(report, hardware):
    monitor = report['monitor']
    epoch, ticks = monitor['start_epoch_s'], monitor['start_ticks_us']
    load_ms = report.get('entry_ms', report.get('endpoint_to_completion_ms'))
    result = {'load_ms': load_ms, 'failures': report.get('failures'), 'max_load_frame_ms': report.get('max_frame_ms'),
              'load_hardware': hardware_span(hardware, epoch, epoch+load_ms/1000),
              'trace_dropped': monitor['trace']['dropped'], 'frame_percentiles_ms_all_phases': monitor['frame_percentiles_ms'],
              'sampler_mean_ms': sum(s['sampler_ms'] for s in hardware['samples'])/max(1,len(hardware['samples'])),
              'sampler_max_ms': max((s['sampler_ms'] for s in hardware['samples']),default=0),
              'hardware_errors': hardware['errors'], 'gpu_errors': hardware['gpu_errors']}
    if 'sample_cost' in monitor:
        cost = monitor['sample_cost']
        result['godot_sampler_cost_ms'] = {'count': cost['count'], 'total': cost['total_us']/1000,
                                           'mean': cost['total_us']/max(1,cost['count'])/1000,
                                           'max': cost['max_us']/1000}
    result['phase_frame_percentiles_ms'] = monitor.get('phase_frame_percentiles_ms', {})
    totals = defaultdict(lambda: {'count': 0, 'total_ms': 0., 'max_ms': 0.})
    for stat in monitor['trace']['stats']:
        row = totals[stat['label']]
        row['count'] += stat['count']
        row['total_ms'] += stat['total_us']/1000
        row['max_ms'] = max(row['max_ms'], stat['max_us']/1000)
    result['trace_totals_inclusive'] = dict(sorted(totals.items(), key=lambda pair: -pair[1]['total_ms']))
    events = monitor['trace']['events']
    umbrella = {'game.parse','game.asset_preparation','game.build','editor.validate','editor.terrain_prepare','deferred.prepare'}
    major = [e for e in events if e['duration_us']>=500000 and e['label'] not in umbrella and not e['label'].startswith('resource.')]
    result['major_events'] = [{**e, 'hardware': hardware_span(hardware, epoch+(e['start_us']-ticks)/1e6, epoch+(e['end_us']-ticks)/1e6)} for e in sorted(major,key=lambda e:-e['duration_us'])[:30]]
    main_events = [e for e in events if e['thread_id']==monitor['main_thread_id'] and e['label'] not in umbrella and 'wait' not in e['label']]
    result['main_thread_long_calls'] = sorted(main_events,key=lambda e:-e['duration_us'])[:20]
    phases = defaultdict(list)
    windows = defaultdict(list)
    samples_all = monitor['samples']
    for index, s in enumerate(samples_all):
        label = phase_name(s['phase'])
        phases[label].append(s)
        stop = samples_all[index+1]['at_ms'] if index+1 < len(samples_all) else monitor['span_ms']
        windows[label].append((epoch+s['at_ms']/1000, epoch+stop/1000))
    result['phases'] = {}
    for phase, samples in phases.items():
        row = {'samples': len(samples), 'hardware': hardware_windows(hardware,windows[phase]),
               'viewports': {}, 'pipelines_first': samples[0]['pipelines'], 'pipelines_last': samples[-1]['pipelines']}
        views = defaultdict(list)
        for sample in samples:
            for viewport in sample['viewports']:
                views[viewport['path']].append(viewport)
        for name, values in views.items():
            row['viewports'][name] = {'cpu_mean_ms': sum(v['cpu_ms'] for v in values)/len(values),
                                     'gpu_mean_ms': sum(v['gpu_ms'] for v in values)/len(values),
                                     'gpu_max_ms': max(v['gpu_ms'] for v in values),
                                     'update_modes': sorted(set(v['update_mode'] for v in values))}
        result['phases'][phase] = row
    result['limits'] = 'CPU/IO are sampled, short-lived thread CPU can be absent; main-thread OS ID comes from CreateProcess. Godot trace thread IDs are separate internal IDs. Phase intervals use the latest 200 ms sample and sum disjoint windows; transitions are approximate. Inclusive timings cannot be summed. Disabled viewport timings can be stale. GPU utilization uses maximum single engine within each type, not a sum of engine percentages. No native wait stacks/fences are captured.'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('hardware', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = summarize(json.loads(args.report.read_text(encoding='utf-8')),json.loads(args.hardware.read_text(encoding='utf-8')))
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['load_ms','failures','max_load_frame_ms','load_hardware','sampler_mean_ms','trace_dropped']},ensure_ascii=False))


if __name__ == '__main__':
    main()
