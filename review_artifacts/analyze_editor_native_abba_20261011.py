"""Summarize like-for-like editor loads; don't sum nested wall spans."""
import json
from pathlib import Path
import statistics
import sys

ROOT = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/review_artifacts')


def main():
    tag=next((arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--tag=')),'editor_native')
    assert tag in ['editor_native','editor_native_complete']
    source = json.loads((OUT/f'{tag}_abba_20261011.json').read_text(encoding='utf-8'))
    rows = []
    for run in source['rows']:
        data = json.loads(Path(run['report']).read_text(encoding='utf-8'))
        hw = json.loads(Path(run['hardware']).read_text(encoding='utf-8'))
        samples = [s for s in hw['samples'] if data['load_start_epoch_s'] <= s['epoch_s'] <= data['load_end_epoch_s']]
        assert len(samples) >= 2
        first, last = samples[0], samples[-1]
        wall = last['monotonic_s']-first['monotonic_s']
        cpu = (last['cpu_s']-first['cpu_s'])/wall
        trace = {}
        for stat in data['load_trace']['stats']:
            name = stat['label']
            row = trace.setdefault(name, {'count':0,'wall_sum_ms':0,'max_ms':0,'threads':[]})
            row['count'] += stat['count']
            row['wall_sum_ms'] += stat['total_us']/1000
            row['max_ms'] = max(row['max_ms'], stat['max_us']/1000)
            row['threads'].append(stat['thread_id'])
        timings = data['load_result']['timings']
        model_events=[e for e in data['load_trace']['events'] if e['label']=='editor.model_parse']
        boundaries=sorted([(e['start_us'],1) for e in model_events]+[(e['end_us'],-1) for e in model_events])
        active=0
        intervals={}
        previous=boundaries[0][0] if boundaries else 0
        for stamp,delta in boundaries:
            intervals[active]=intervals.get(active,0)+(stamp-previous)
            active+=delta
            previous=stamp
        activity={'task_spans':len(model_events),'wall_ms_by_active_count':{str(k):v/1000 for k,v in intervals.items()},
                  'scope':'From first model start to last model return; active wall spans include I/O, renderer and synchronization waits. Does not include texture tasks, time before first dispatch or after last model, or resource held-ready intervals. Not CPU concurrency.'}
        rows.append({
            'label':run['label'],'mode':run['mode'],'load_ms':data['load_ms'],
            'asset_wait_ms':run['units']['asset_wait']['total_ms'],
            'validation_ms':timings.get('validate_ms'),
            'passes':run['passes'],'warnings':run['warnings'],
            'lookahead':run['lookahead'],'queue':run['preparation'],
            'hardware':{
                'samples':len(samples),'sampled_wall_s':wall,'cpu_equivalents':cpu,
                'logical_cpus':hw['logical_cpus'],'cpu_percent_total_logical':100*cpu/hw['logical_cpus'],
                'peak_rss_bytes':max(s['rss_bytes'] for s in samples),
                'peak_private_bytes':max(s.get('private_bytes') or 0 for s in samples),
                'logical_read_bytes':last['read_bytes']-first['read_bytes'],
                'sampler_mean_ms':statistics.mean(s['sampler_ms'] for s in samples),
                'errors':hw['errors'],'gpu_errors':hw['gpu_errors'],
            },
            'trace_dropped':data['load_trace']['dropped'],'trace':trace,'model_activity':activity,
            'report':run['report'],'hardware_report':run['hardware'],
        })
    result = {'rows':rows,'map_sha':source['map_sha'],'source_fingerprint':source['source_fingerprint'],
              'scope':'Excluded warm then full/compiled/compiled/full. CPU/RSS samples inside measured loading epoch only, about 0.5-0.7s resolution. CPU equivalents are process CPU seconds/wall seconds, not worker occupancy. Logical I/O includes cache. RSS includes editor, caches, geometry and renderer, not just admitted tasks. No summed GPU engines or cold-disk claim. Trace wall sums overlap and include waits.'}
    if len(rows)==5:
        result['means']={}
        for mode in ['full','compiled']:
            group=[r for r in rows if r['mode']==mode and r['label']!='warm']
            result['means'][mode]={key:statistics.mean(r[key] for r in group) for key in ['load_ms','asset_wait_ms']}
            result['means'][mode].update({key:statistics.mean(r['hardware'][key] for r in group) for key in ['cpu_equivalents','peak_rss_bytes','peak_private_bytes']})
        result['load_change_percent']=100*(result['means']['compiled']['load_ms']/result['means']['full']['load_ms']-1)
    output=ROOT/f'review_artifacts/{tag}_analysis_20261011.json'
    output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result.get('means',{}),indent=2))
    for row in rows:
        print(json.dumps({k:row[k] for k in ['label','load_ms','asset_wait_ms','passes','warnings','hardware']}))


if __name__=='__main__':
    main()
