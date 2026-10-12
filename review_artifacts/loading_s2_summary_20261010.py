"""Measured windows only; A/B are fresh processes, not OS-cold runs."""
import bisect
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPORTS = Path('D:/code/rmmo_runtime/review_artifacts')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def cpu_at(samples, epoch):
    i = bisect.bisect_right([s['epoch_s'] for s in samples], epoch)
    if i == 0:
        return samples[0]['cpu_s']
    if i == len(samples):
        return samples[-1]['cpu_s']
    a, b = samples[i-1:i+1]
    f = (epoch-a['epoch_s'])/(b['epoch_s']-a['epoch_s'])
    return a['cpu_s'] + f*(b['cpu_s']-a['cpu_s'])


def row(prefix, label):
    name = f'{prefix}_{label}_20261010'
    p = read(REPORTS / f'{name}.json')
    h = read(ROOT / f'{name}.hardware.json')
    editor = prefix == 'editor_s5'
    ms = p['endpoint_to_completion_ms'] if editor else p['entry_ms']
    start = p['monitor']['start_epoch_s'] if editor else p['entry_epoch_s']
    end = start + ms/1000 if editor else p['entry_end_epoch_s']
    samples = h['samples']
    window = [s for s in samples if start <= s['epoch_s'] <= end]
    value = dict(label=label, ms=ms, failures=p['failures'],
                 cpu_cores=(cpu_at(samples,end)-cpu_at(samples,start))/(end-start),
                 peak_rss_mib=max(s['rss_bytes'] for s in window)/1048576,
                 map_sha=p['checkpoint']['sha256'] if editor else p['map_sha'],
                 background_frames=p['monitor']['phase_frame_percentiles_ms'].get('loaded_bridge' if editor else 'playable_background'))
    if editor:
        value.update(records=p['records'], workers=p['timings']['preparation']['ledger']['peak_workers'],
                     asset_wait_ms=p['timings']['build']['units']['asset_wait']['total_ms'],
                     resident_bytes_at_end=p['timings']['preparation']['ledger']['reserved_bytes'],
                     max_frame_ms=p['max_frame_ms'])
    else:
        value.update(cooked_meshes=p['map_profile']['cooked_meshes'],
                     records=p['authored_record_count'],
                     navigation_background=p['background_navigation'], wind_background=p['background_wind'])
    return value


result = {'notes': [
    'Two samples per arm are preliminary; no statistical significance claim.',
    'Shared pixels include native prefetch; unchanged complete entry gate.',
    'Editor compares the same new queue with 1 versus 2 workers, not the old implementation.',
    'No OS, driver, compiled asset or image cache flush; no complete cold-start claim.',
]}
for prefix in ['loading_s2', 'editor_s5', 'loading_s3']:
    if not all((REPORTS / f'{prefix}_{label}_20261010.json').exists() for label in ['a1','b1','b2','a2']):
        continue
    arms = {}
    for arm in ['a','b']:
        rows = [row(prefix, arm+str(n)) for n in [1,2]]
        fields = ['ms', 'cpu_cores', 'peak_rss_mib'] + (['asset_wait_ms', 'max_frame_ms'] if prefix == 'editor_s5' else [])
        arms[arm] = {'runs': rows, 'mean': {key:statistics.mean(r[key] for r in rows) for key in fields}}
    arms['improvement_percent'] = (1-arms['b']['mean']['ms']/arms['a']['mean']['ms'])*100
    result[prefix] = arms
destination = ROOT / 'loading_s2_s5_summary_20261010.json'
destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k:{'a':v['a']['mean'],'b':v['b']['mean'],'improvement_percent':v['improvement_percent']} for k,v in result.items() if k!='notes'}, indent=2))
