"""Compare only measured entry windows; no OS-cold or full-visual claim."""
import bisect
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPORTS = Path('D:/code/rmmo_runtime/review_artifacts')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def cpu_at(samples, epoch):
    i = bisect.bisect_right([s['epoch_s'] for s in samples], epoch)
    if i == 0:
        return samples[0]['cpu_s']
    if i == len(samples):
        return samples[-1]['cpu_s']
    a, b = samples[i - 1:i + 1]
    fraction = (epoch - a['epoch_s']) / (b['epoch_s'] - a['epoch_s'])
    return a['cpu_s'] + fraction * (b['cpu_s'] - a['cpu_s'])

rows = []
for label in sys.argv[1:]:
    name = 'loading_collision_' + label + '_20261011'
    p = read(REPORTS / (name + '.json'))
    h = read(HERE / (name + '.hardware.json'))
    if 'entry_ms' not in p:
        rows.append({'label': label, 'failed_before_entry': True, 'failures': p['failures']})
        continue
    start, end = p['entry_epoch_s'], p['entry_end_epoch_s']
    samples = h['samples']
    window = [s for s in samples if start <= s['epoch_s'] <= end]
    mp = p['map_profile']
    collision = p.get('entry_collision_profile', {})
    rows.append(dict(
        label=label, mode=p.get('collision_first', False), ms=p['entry_ms'],
        failures=p['failures'], cache_hit=p['cache_candidate'],
        cpu_cores=(cpu_at(samples, end) - cpu_at(samples, start)) / (end - start),
        peak_rss_mib=max(s['rss_bytes'] for s in window) / 1048576,
        initial_models=mp['initial_asset_paths'], core_deferred=mp.get('collision_first_core_deferred', 0),
        initial_pending=p['initial_pending'], records=p.get('authored_record_count'),
        parse_ms=mp.get('parser_total_us', 0) / 1000,
        core_ready_ms=p.get('entry_core_ready_ms'),
        safety_ms=(p['world_profile']['entry_safety_ready_us'] - p['world_profile']['entry_core_resources_ready_us']) / 1000,
        collision_accepted=collision.get('accepted', 0),
        collision_fallbacks=collision.get('fallback_reason_totals', {}),
        background_frames=p.get('monitor', {}).get('phase_frame_percentiles_ms', {}).get('playable_background'),
        formal_sha=p['formal_sha'],
    ))
result = {'notes': ['Fresh process per run; no OS/driver/image cache flush.',
                    'B enables collision-first and effective background navigation; not an isolated worker-count comparison.',
                    'Failed and prewarm samples are not included in means automatically.'], 'runs': rows}
for mode in [False, True]:
    valid = [r for r in rows if r.get('mode') == mode and r.get('failures') == 0 and r.get('cache_hit') and not r['label'].endswith('0')]
    if valid:
        result['b' if mode else 'a'] = {'count': len(valid), 'mean': {key: statistics.mean(r[key] for r in valid) for key in ['ms', 'cpu_cores', 'peak_rss_mib', 'safety_ms']}}
if 'a' in result and 'b' in result:
    result['improvement_percent'] = 100 * (1 - result['b']['mean']['ms'] / result['a']['mean']['ms'])
destination = HERE / 'loading_collision_summary_20261011.json'
destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
