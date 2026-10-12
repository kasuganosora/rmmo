"""Same collision-first contract; compare query caches only, fresh processes."""
import bisect
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORTS = Path('D:/code/rmmo_runtime/review_artifacts')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    at = (len(values) - 1) * p
    lo = int(at)
    hi = min(lo + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (at - lo)


def cpu_at(samples, epoch):
    i = bisect.bisect_right([s['epoch_s'] for s in samples], epoch)
    if i == 0:
        return samples[0]['cpu_s']
    if i == len(samples):
        return samples[-1]['cpu_s']
    a, b = samples[i - 1:i + 1]
    t = (epoch - a['epoch_s']) / (b['epoch_s'] - a['epoch_s'])
    return a['cpu_s'] + t * (b['cpu_s'] - a['cpu_s'])


rows = []
for label in sys.argv[1:]:
    name = 'loading_collision_' + label + '_20261011'
    p = read(REPORTS / (name + '.json'))
    h = read(HERE / (name + '.hardware.json'))
    row = {'label': label, 'failures': p['failures'],
           'collision_first': p.get('collision_first'),
           'query_cache': p.get('collision_query_cache'),
           'candidate_cache': p.get('collision_candidate_cache'),
           'detailed_query_profile': p.get('collision_query_profile')}
    if 'entry_ms' not in p:
        row['failed_before_entry'] = True
        rows.append(row)
        continue
    start, end = p['entry_epoch_s'], p['entry_end_epoch_s']
    window = [s for s in h['samples'] if start <= s['epoch_s'] <= end]
    row.update(entry_ms=p['entry_ms'], core_ms=p['entry_core_ready_ms'],
               cpu_cores=(cpu_at(h['samples'], end) - cpu_at(h['samples'], start)) / (end - start),
               peak_rss_mib=max(s['rss_bytes'] for s in window) / 1048576,
               formal_sha=p['formal_sha'], cache_candidate=p['cache_candidate'],
               background=p['monitor']['phase_frame_percentiles_ms'].get('playable_background'),
               collision_query=p.get('final_collision_query'))
    frames = p.get('playable_runtime_frames', [])
    for field in ['ms', 'geometry_ms', 'collision_ms']:
        values = [r['traversal'][field] for r in frames if field in r.get('traversal', {})]
        row['traversal_' + field] = {'n': len(values), 'p50': percentile(values, .5),
                                    'p95': percentile(values, .95)}
    for field in ['guard_ms', 'move_ms']:
        values = [r['player_motion'][field] for r in frames if field in r.get('player_motion', {})]
        row[field] = {'n': len(values), 'p50': percentile(values, .5), 'p95': percentile(values, .95)}
    begin = p.get('playable_player_physics_start', {})
    finish = p.get('playable_player_physics_end', {})
    row['player_cpu_ms'] = (finish.get('total_us', 0) - begin.get('total_us', 0)) / 1000
    row['player_physics_ticks'] = finish.get('ticks', 0) - begin.get('ticks', 0)
    gates = [e for e in p['monitor']['trace']['events'] if e.get('label') == 'entry.geometry_gate']
    core_us = p['world_profile']['entry_core_resources_ready_us']
    row['gates'] = {'samples': len(gates)}
    for field in ['landing_visual_ready', 'collision_dependencies_ready', 'scope_ready', 'nearby_collision_ready']:
        yes = [e for e in gates if e['details'].get(field) is True]
        no = [e for e in gates if e['details'].get(field) is False]
        row['gates'][field] = {'first_true_after_core_ms': (yes[0]['start_us'] - core_us) / 1000 if yes else None,
                               'last_false_after_core_ms': (no[-1]['start_us'] - core_us) / 1000 if no else None}
    row['deferred_query_counters'] = {k: v for k, v in p.get('final_deferred_profile', {}).items()
                                       if k.startswith(('collision_guard', 'collision_query', 'collision_candidate', 'collision_request', 'collision_coverage'))}
    rows.append(row)

result = {'notes': ['Both modes use collision-first, same spawn/map and navigation contract.',
                    'Fresh process; warm derived cache; OS/driver caches not flushed.',
                    'Traversal quantiles observe the latest physics tick per render frame, not every tick.',
                    'Readiness first-true samples include polling cadence; not isolated CPU durations.'],
          'runs': rows}
for enabled in [False, True]:
    valid = [r for r in rows if r.get('query_cache') == enabled and r.get('candidate_cache') == enabled
             and not r.get('detailed_query_profile') and r.get('failures') == 0 and 'entry_ms' in r
             and not r['label'].endswith('0')]
    if valid:
        result['on' if enabled else 'off'] = {'count': len(valid), 'mean': {
            k: statistics.mean(r[k] for r in valid) for k in ['entry_ms', 'cpu_cores', 'peak_rss_mib', 'player_cpu_ms']},
            'traversal_p50_ms': statistics.mean(r['traversal_ms']['p50'] for r in valid)}
if 'on' in result and 'off' in result:
    result['guard_reduction_percent'] = 100 * (1 - result['on']['traversal_p50_ms'] / result['off']['traversal_p50_ms'])
(HERE / 'loading_collision_query_summary_20261011.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
