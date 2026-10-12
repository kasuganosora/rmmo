import json
import re
from pathlib import Path

REPORT = Path('D:/code/rmmo_runtime/review_artifacts/loading_path_20261010')

def interpolate(samples, when, key):
    for a, b in zip(samples, samples[1:]):
        if a['epoch_s'] <= when <= b['epoch_s']:
            fraction = (when - a['epoch_s']) / (b['epoch_s'] - a['epoch_s'])
            return a[key] + fraction * (b[key] - a[key])
    raise ValueError('Entry interval not enclosed by hardware samples')

rows = []
for path in sorted(REPORT.glob('*.json')):
    if '.hardware.' in path.name or not path.stem.startswith(('warm_', 'rebuild_')):
        continue
    data = json.loads(path.read_text(encoding='utf-8'))
    if not data.get('screenshot') or not path.with_suffix('.hardware.json').exists() or not path.with_suffix('.log').exists():
        continue  # report is not complete yet
    h = json.loads(path.with_suffix('.hardware.json').read_text(encoding='utf-8'))
    log = path.with_suffix('.log').read_text(encoding='utf-8')
    profile = data['map_profile']
    start = data['entry_epoch_s']; end = start + data['entry_ms'] / 1000
    samples = h['samples']; within = [x for x in samples if start <= x['epoch_s'] <= end]
    row = dict(name=path.stem, entry_ms=data['entry_ms'], core_ms=data['entry_core_ready_ms'],
               post_core_ms=data['entry_ms'] - data['entry_core_ready_ms'],
               safety_ms=(data['world_profile']['entry_safety_ready_us'] - data['world_profile']['entry_core_resources_ready_us']) / 1000,
               cpu_cores=(interpolate(samples, end, 'cpu_s') - interpolate(samples, start, 'cpu_s')) / (end - start),
               peak_rss_bytes=max(x['rss_bytes'] for x in within),
               errors=len(re.findall(r'^(?:SCRIPT )?ERROR:', log, re.M)),
               warnings=len(re.findall(r'^WARNING:', log, re.M)),
               failures=data['failures'], authored_records=data['authored_record_count'],
               map_sha=data['map_sha'], formal_sha=data['formal_sha'],
               cpu_river_index=data['cpu_river_index'])
    for key in ['reference_index_read_us', 'reference_index_hit', 'reference_selected_count',
                'initial_asset_paths', 'mesh_cache_candidate', 'cooked_meshes', 'build_total_us',
                'mesh_us', 'spec_us', 'cooked_restore_us', 'asset_parse_wall_us']:
        row[key] = profile.get(key)
    row['native_hits'] = profile['asset_admission']['native_cache_hits']
    row['native_misses'] = profile['asset_admission']['native_cache_misses']
    row['mesh_categories'] = profile['mesh_categories']
    rows.append(row)

summary = dict(runs=rows)
for category in ['warm', 'rebuild']:
    pairs = {mode: [x for x in rows if x['name'].startswith(category + '_' + mode + '_')] for mode in ['old', 'new']}
    if all(len(group) == 2 for group in pairs.values()):
        keys = ['entry_ms', 'core_ms', 'safety_ms', 'post_core_ms', 'reference_index_read_us', 'build_total_us', 'cpu_cores', 'peak_rss_bytes']
        summary[category] = {mode: {key: sum(x[key] for x in group)/len(group) for key in keys} for mode, group in pairs.items()}
print(json.dumps([{k:v for k,v in r.items() if k not in ['mesh_categories','map_sha','formal_sha']} for r in rows], indent=2))
print(json.dumps({k:v for k,v in summary.items() if k != 'runs'}, indent=2))
(Path(__file__).parent / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
