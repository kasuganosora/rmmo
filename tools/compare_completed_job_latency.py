"""Compare exactly three fixed-map queue timing samples; preserve every outlier."""
import argparse
import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path
from summarize_completed_job_latency import summarize


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profiles',nargs=3,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    assert len({p.resolve() for p in args.profiles})==3, 'Three distinct runs are required'
    reports=[json.loads(p.read_text(encoding='utf-8')) for p in args.profiles]
    launches=[json.loads((p.parent/'launch.json').read_text(encoding='utf-8')) for p in args.profiles]
    summaries=[json.loads((p.parent/'summary.json').read_text(encoding='utf-8')) for p in args.profiles]
    for launch,summary in zip(launches,summaries):
        assert launch['engine_sha']==launches[0]['engine_sha']
        assert launch['probe_sha']==launches[0]['probe_sha'] and launch['hud']==launches[0]['hud']
        # Only the private output location may differ between the three runs.
        assert [x for x in launch['command'] if not x.startswith('--output=')]==[x for x in launches[0]['command'] if not x.startswith('--output=')]
        assert summary['exit']==0 and not summary['failures'] and not summary['diagnostics']
        assert not summary['other_engine_or_compiler_pids']
    reference=reports[0]
    for report in reports:
        assert report['map_sha']==reference['map_sha']==report['map_sha_after']
        assert report['sources']==reference['sources']==report['sources_after']
        assert not report['failures'] and not report['completed_owner_drain']
        assert report['completed_job_trace']['dropped']==0 and report['monitor']['trace']['dropped']==0
    measurements=[summarize(r) for r in reports]
    grouped=defaultdict(lambda:[dict(count=0,total_ms=0.,max_ms=0.,slowest_uuid='') for _ in range(3)])
    sources=defaultdict(lambda:[dict(count=0,total_ms=0.,max_ms=0.,slowest_uuid='') for _ in range(3)])
    spikes=[]
    for sample,result in enumerate(measurements):
        main_threads={e['thread_id'] for e in reports[sample]['monitor']['trace']['events']
                      if e['label'] in ['deferred.instance_specs','deferred.accept_template','deferred.instance_begin']}
        assert len(main_threads)==1, 'Cannot attribute nested spans to the main thread unambiguously'
        for unit in result['units']:
            for row in [grouped[(unit['path'],unit['stage'])][sample],sources[(unit['path'],'all')][sample]]:
                row['count']+=1;row['total_ms']+=unit['duration_ms']
                if unit['duration_ms']>row['max_ms']:
                    row['max_ms']=unit['duration_ms'];row['slowest_uuid']=unit['uuid']
            if unit['duration_ms']>50:
                origin=reports[sample]['completed_job_trace']['origin_us']
                start=round(origin+unit['start_ms']*1000);end=round(origin+unit['end_ms']*1000)
                nested=[e for e in reports[sample]['monitor']['trace']['events'] if e['thread_id'] in main_threads and start<=e['start_us'] and e['end_us']<=end]
                spikes.append(dict(run=sample+1,**unit,nested_spans=sorted(nested,key=lambda e:e['duration_us'],reverse=True)[:12]))
    rows=[]
    for (path,stage),samples in list(grouped.items())+list(sources.items()):
        rows.append(dict(path=path,stage=stage,present_runs=sum(r['count']>0 for r in samples),
                         median_total_ms=statistics.median(r['total_ms'] for r in samples),
                         median_max_unit_ms=statistics.median(r['max_ms'] for r in samples),
                         max_unit_ms=max(r['max_ms'] for r in samples),samples=samples))
    source_rows=sorted([r for r in rows if r['stage']=='all'],key=lambda r:r['median_total_ms'],reverse=True)
    rows=sorted([r for r in rows if r['stage']!='all'],key=lambda r:r['median_total_ms'],reverse=True)
    args.output.mkdir(parents=True,exist_ok=False)
    result=dict(profiles=[str(p.resolve()) for p in args.profiles],map_sha=reference['map_sha'],
                engine_sha=launches[0]['engine_sha'],
                note='Three diagnostic runs, fixed map/source and switches. Wall time includes native/GPU waits; these are not load p95 or exclusive CPU measurements. Initial and return phases are both included. All spikes retained.',
                by_total=rows,by_single=sorted(rows,key=lambda r:r['median_max_unit_ms'],reverse=True),
                by_source=source_rows,spikes=sorted(spikes,key=lambda r:r['duration_ms'],reverse=True),
                stages=[r['stages'] for r in measurements])
    (args.output/'comparison.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    for kind in ['by_total','by_single','by_source']:
        with (args.output/(kind+'.csv')).open('w',newline='',encoding='utf-8-sig') as file:
            fields=['path','stage','present_runs','median_total_ms','median_max_unit_ms','max_unit_ms']
            writer=csv.DictWriter(file,fields);writer.writeheader()
            writer.writerows({k:row[k] for k in fields} for row in result[kind])
        print(kind.upper())
        for row in result[kind][:8]:print(json.dumps(row,ensure_ascii=False))


if __name__=='__main__':main()
