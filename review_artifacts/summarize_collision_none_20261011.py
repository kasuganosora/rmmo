"""Same-code ABBA of verified per-instance no-collision proofs only."""
import bisect
import json
import statistics
from pathlib import Path

here = Path(__file__).resolve().parent
reports = Path('D:/code/rmmo_runtime/review_artifacts')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def cpu_at(samples, epoch):
    i = bisect.bisect_right([s['epoch_s'] for s in samples], epoch)
    if i == 0:
        return samples[0]['cpu_s']
    if i == len(samples):
        return samples[-1]['cpu_s']
    a, b = samples[i-1:i+1]
    t = (epoch-a['epoch_s'])/(b['epoch_s']-a['epoch_s'])
    return a['cpu_s']+t*(b['cpu_s']-a['cpu_s'])


rows = []
for label in ['none_a1', 'none_b1', 'none_b2', 'none_a2']:
    name = f'loading_collision_{label}_20261011'
    if not (reports / (name+'.json')).exists() or not (here / (name+'.hardware.json')).exists():
        continue
    p = read(reports / (name+'.json'))
    h = read(here / (name+'.hardware.json'))
    start, end = p['entry_epoch_s'], p['entry_end_epoch_s']
    row = {k:p.get(k) for k in ['failures', 'entry_ms', 'entry_core_ready_ms', 'cache_candidate',
                               'collision_first', 'no_collision_proof', 'collision_query_cache',
                               'texture_stage_profile', 'formal_sha']}
    row['label'] = label
    row['entry_core_to_ready_ms'] = p['entry_ms'] - p['entry_core_ready_ms']
    row['cpu_cores'] = (cpu_at(h['samples'],end)-cpu_at(h['samples'],start))/(end-start)
    row['peak_rss_mib'] = max(s['rss_bytes'] for s in h['samples'] if start <= s['epoch_s'] <= end)/1048576
    row['playable_first_10s_frame_ms'] = p['monitor']['phase_frame_percentiles_ms'].get('playable_background')
    row['entry_collision_profile'] = p.get('entry_collision_profile')
    row['final_collision_profile'] = p.get('final_collision_profile')
    events = p['monitor']['trace']['events']
    core_us = p['world_profile']['entry_core_resources_ready_us']
    row['gates_after_core_ms'] = {}
    for field in ['landing_visual_ready','collision_dependencies_ready','scope_ready','nearby_collision_ready']:
        yes = [e for e in events if e['label']=='entry.geometry_gate' and e['details'].get(field) is True]
        row['gates_after_core_ms'][field] = (yes[0]['start_us']-core_us)/1000 if yes else None
    rows.append(row)

result = {'notes': ['Only no-collision proof flag differs; collision-first and query caches on in all scored runs.',
                    'Separate fresh processes; warm derived caches; OS/driver caches not flushed.',
                    'Two excluded warmups rebuilt code-identity-dependent map/geometry caches.',
                    'No avatar render change until all timed measurement completed.'], 'runs':rows}
for enabled in [False, True]:
    valid = [r for r in rows if r['no_collision_proof'] == enabled and r['failures'] == 0]
    if valid:
        result['on' if enabled else 'off'] = {'count':len(valid), 'mean':{
            k:statistics.mean(r[k] for r in valid) for k in ['entry_ms','entry_core_ready_ms','entry_core_to_ready_ms','cpu_cores','peak_rss_mib']},
            'mean_first_10s_p99_ms':statistics.mean(r['playable_first_10s_frame_ms']['99'] for r in valid)}
if 'on' in result and 'off' in result:
    result['entry_reduction_percent'] = 100*(1-result['on']['mean']['entry_ms']/result['off']['mean']['entry_ms'])
(here/'loading_collision_none_summary_20261011.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='runs'},ensure_ascii=False,indent=2))
for row in rows:
    print(json.dumps({k:row[k] for k in ['label','entry_ms','entry_core_ready_ms','cache_candidate','cpu_cores','gates_after_core_ms']},ensure_ascii=False))
