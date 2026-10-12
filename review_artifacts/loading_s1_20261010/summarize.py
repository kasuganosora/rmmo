"""Summarize fixed-input entry probes without including post-entry CPU/RAM."""
import bisect
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORTS = Path('D:/code/rmmo_runtime/review_artifacts')
prefix = sys.argv[1] if len(sys.argv) > 1 else 'final'


def interpolate(samples, epoch, field):
    times = [s['epoch_s'] for s in samples]
    at = bisect.bisect_right(times, epoch)
    if at == 0:
        return samples[0][field]
    if at == len(samples):
        return samples[-1][field]
    left, right = samples[at - 1:at + 1]
    fraction = (epoch - left['epoch_s']) / (right['epoch_s'] - left['epoch_s'])
    return left[field] + fraction * (right[field] - left[field])


rows = []
for suffix in ['a1', 'b1', 'b2', 'a2']:
    name = prefix + '_' + suffix
    report = json.loads((REPORTS / f'loading_s1_{name}_20261010.json').read_text(encoding='utf-8-sig'))
    hardware = json.loads((HERE / f'{name}.hardware.json').read_text(encoding='utf-8-sig'))
    samples = hardware['samples']
    start, end = report['entry_epoch_s'], report['entry_end_epoch_s']
    in_entry = [s for s in samples if start <= s['epoch_s'] <= end]
    cpu_seconds = interpolate(samples, end, 'cpu_s') - interpolate(samples, start, 'cpu_s')
    trace = report['monitor']['trace']
    bridge = [e['details'] for e in trace['events'] if e['label'] == 'deferred.publication' and e['details'].get('uuid', '').startswith('stone_e_')]
    row = dict(label=name, entry_ms=report['entry_ms'], core_ready_ms=report.get('entry_core_ready_ms'),
               cooked_meshes=report['map_profile'].get('cooked_meshes'),
               index_hit=report['map_profile'].get('reference_index_hit'), failures=report['failures'],
               cpu_core_equivalents=cpu_seconds / (end - start),
               peak_rss_mib=max(s['rss_bytes'] for s in in_entry) / 1048576,
               bridge_publication_ms=bridge[0]['elapsed_us'] / 1000 if bridge else None,
               bridge_material_ms=bridge[0].get('prefab_parts_ms', {}).get('materials_ms') if bridge else None,
               water_cpu=report.get('cpu_river_index', {}),
               background_frames=report['monitor']['phase_frame_percentiles_ms'].get('playable_background'),
               trace_dropped=trace['dropped'], formal_sha=report['formal_sha'])
    rows.append(row)
summary = {}
for group, indices in [('old', [0, 3]), ('new', [1, 2])]:
    summary[group] = {key: statistics.mean(rows[i][key] for i in indices)
                      for key in ['entry_ms', 'core_ready_ms', 'cpu_core_equivalents', 'peak_rss_mib']}
summary['entry_improvement_percent'] = (1 - summary['new']['entry_ms'] / summary['old']['entry_ms']) * 100
result = {'rows': rows, 'summary': summary,
          'note': 'Two samples per arm; derived caches warm, no OS/driver cold-cache claim. CPU and RSS use the reported entry window.'}
(HERE / f'{prefix}_summary.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps(result, indent=2, ensure_ascii=False))
