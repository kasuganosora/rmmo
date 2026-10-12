"""Compare actual entry windows; do not mix cold derived caches with warm runs."""
import bisect
import json
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORTS = Path('D:/code/rmmo_runtime/review_artifacts')


def at(samples, epoch):
    i = bisect.bisect_right([s['epoch_s'] for s in samples], epoch)
    if i == 0:
        return samples[0]['cpu_s']
    if i == len(samples):
        return samples[-1]['cpu_s']
    a, b = samples[i - 1:i + 1]
    f = (epoch - a['epoch_s']) / (b['epoch_s'] - a['epoch_s'])
    return a['cpu_s'] + f * (b['cpu_s'] - a['cpu_s'])


def row(label):
    p = json.loads((REPORTS / f'loading_s1_{label}_20261010.json').read_text(encoding='utf-8-sig'))
    h = json.loads((HERE / f'{label}.hardware.json').read_text(encoding='utf-8-sig'))
    start, end = p['entry_epoch_s'], p['entry_end_epoch_s']
    window = [s for s in h['samples'] if start <= s['epoch_s'] <= end]
    profile = p['map_profile']
    return dict(label=label, entry_ms=p['entry_ms'], core_ms=p.get('entry_core_ready_ms'),
                cpu_cores=(at(h['samples'], end) - at(h['samples'], start)) / (end - start),
                peak_rss_mib=max(s['rss_bytes'] for s in window) / 1048576,
                failures=p['failures'], index_hit=profile['reference_index_hit'],
                index_rebuilt=profile.get('reference_index_rebuilt_before_models', False),
                cooked_meshes=profile['cooked_meshes'],
                initial_asset_paths=profile.get('initial_asset_paths'),
                authored_records=p.get('authored_record_count'),
                formal_sha=p['formal_sha'], map_sha=p['map_sha'],
                prefab_pixels=p['prefab_texture_preparation'], native_prefetch=p['native_entry_prefetch'],
                background_frames=p['monitor']['phase_frame_percentiles_ms'].get('playable_background'))


groups = {
    'warm_old': ['final_a1', 'final_a2'],
    'warm_experimental_combined': ['final_b1', 'final_b2'],
    'warm_final_default': ['water_a1', 'water_a2'],
    'warm_native_only': ['water_native_b1', 'water_native_b2'],
    'cold_derived_old': ['cold_a1', 'cold_a2'],
    'cold_derived_new': ['cold_b1', 'cold_b2'],
}
result = {}
for key, labels in groups.items():
    rows = [row(label) for label in labels]
    means = {}
    for field in ['entry_ms', 'core_ms', 'cpu_cores', 'peak_rss_mib']:
        values = [r[field] for r in rows if r[field] is not None]
        means[field] = statistics.mean(values) if values else None
    result[key] = {'runs': rows, 'mean': means}
result['cold_derived_improvement_percent'] = (1 - result['cold_derived_new']['mean']['entry_ms'] / result['cold_derived_old']['mean']['entry_ms']) * 100
result['notes'] = [
    'Two runs per arm; OS, driver and compiled model/pixel caches are not cold.',
    'Cold arms remove only this temporary map dependency index plus complete/selected geometry caches on each run.',
    'Water-only equals final default. Experimental native prefetch and prefab pixels remain disabled by default.',
    'Warm old versus water-only are different serial series; no statistical significance claim.',
]
(HERE / 'rollout_summary.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({key: value['mean'] for key, value in result.items() if isinstance(value, dict)}, indent=2))
print('cold_derived_improvement_percent', result['cold_derived_improvement_percent'])
