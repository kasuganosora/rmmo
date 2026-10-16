"""Summarize identical-route publication probes without conflating their clocks."""
import hashlib
import json
import pathlib
import struct
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(folder):
    result = folder / 'result.json'
    trace = folder / 'publication_trace.json'
    report = json.loads(result.read_text(encoding='utf-8'))
    events = json.loads(trace.read_text(encoding='utf-8'))
    publications = [e for e in events['events'] if e['label'] == 'deferred.publication']
    ready = []
    for job in events['events']:
        if job['label'] != 'deferred.job' or job['details'].get('failed'):
            continue
        matching = [e for e in publications if e['details']['path'] == job['details']['path']
                    and e['start_us'] >= job['end_us']]
        if matching:
            ready.append({'path': job['details']['path'],
                          'first_publication_ms': (min(e['start_us'] for e in matching) - job['end_us']) / 1000,
                          'last_traced_publication_ms': (max(e['end_us'] for e in matching) - job['end_us']) / 1000})
    images = []
    for shot in report['screenshots']:
        path = pathlib.Path(shot['path'])
        raw = path.read_bytes()
        receipt = shot['receipt']
        assert sha(path) == shot['sha256'] == receipt['sha256']
        assert receipt['quality'] == shot['quality'] == 90
        assert not receipt['lossless'] and not shot['lossless']
        assert raw[:4] == b'RIFF' and raw[8:12] == b'WEBP'
        chunks, cursor = [], 12
        while cursor + 8 <= len(raw):
            chunks.append(raw[cursor:cursor + 4])
            size = struct.unpack_from('<I', raw, cursor + 4)[0]
            cursor += 8 + size + (size % 2)
        assert b'VP8 ' in chunks and b'VP8L' not in chunks
        images.append({'path': str(path), 'sha256': sha(path), 'quality': 90,
                       'lossy_vp8_verified': True, 'dimensions': shot['dimensions']})
    profile = report['region_samples'][-1]['queue_profile']
    view = report['views'][0]
    observed_retirement = []
    samples = report['region_samples']
    paths = {job['path'] for sample in samples for job in sample.get('jobs', [])}
    for path in sorted(paths):
        present = [(i, sample['at_ms'], job) for i, sample in enumerate(samples)
                   for job in sample.get('jobs', []) if job['path'] == path]
        prepared = [row for row in present if row[2]['ready_result']]
        if prepared and present[-1][0] + 1 < len(samples):
            first, last = prepared[0], present[-1]
            absent = samples[last[0] + 1]['at_ms']
            observed_retirement.append({'path': path, 'first_ready_observed_ms': first[1],
                                        'last_present_ms': last[1], 'first_absent_ms': absent,
                                        'observed_ready_to_absence_ms': absent - first[1]})
    return {'run': folder.name, 'result_sha256': sha(result), 'trace_sha256': sha(trace),
            'failures': report['failures'], 'phase': report['phase'],
            'fair_publication': report.get('fair_publication', False),
            'shared_prefab_pixels': report.get('shared_prefab_pixels', False),
            'map_sha256': report['map_sha256'], 'camera_recipe': report['camera_recipe'],
            'publication_sources': report['publication_sources'],
            'region_wait_ms': view['wait_ms'], 'region_ready': view['ready'],
            'process_probe_elapsed_ms': report['elapsed_ms'],
            'trace_dropped': events['dropped'], 'trace_minimum_event_us': events['minimum_event_us'],
            'max_traced_publication_ms': max(e['duration_us'] for e in publications) / 1000,
            'ready_to_publication': ready, 'observed_retirement': observed_retirement, 'images': images,
            'counts': {k: profile.get(k, 0) for k in ['models', 'instances', 'specs',
                         'failed_instances', 'failed_paths', 'fair_publication_units', 'total_jobs',
                         'reserved_bytes', 'peak_reserved_bytes']},
            'render_inventory': {k: view['settled']['batches'][k] for k in ['groups',
                         'render_surfaces', 'render_vertices', 'source_objects', 'source_surfaces']},
            'water': {k: view['settled'][k] for k in ['water_indexed', 'water_resident']},
            'subject_ids': sorted(s['id'] for s in view['settled']['subjects'])}


if __name__ == '__main__':
    root = pathlib.Path(sys.argv[1])
    rows = [summarize(root / name) for name in sys.argv[2:]]
    (root / 'publication_measurements.json').write_text(json.dumps({
        'limits': 'Fresh processes with existing OS/derived caches; same bounded trace overhead. '
                  'Region readiness is not game startup. Ready-to-last intervals include other work '
                  'and lower-priority instances; events below the trace threshold may be absent. '
                  'Observed retirement uses half-second samples, may include cancelled/restarted jobs, '
                  'and is not an exact per-instance ready-to-screen latency. '
                  'Reservation bytes are accounting estimates, not RSS or VRAM.',
        'runs': rows}, ensure_ascii=False, indent=2), encoding='utf-8')
    for row in rows:
        print(json.dumps({k: row[k] for k in ['run', 'region_wait_ms', 'failures',
                                             'max_traced_publication_ms']}))
