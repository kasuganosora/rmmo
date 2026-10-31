"""Rank real queue lifetimes and processing spans without equating waits to CPU.

Usage: python tools/summarize_completed_job_latency.py PROFILE --output DIRECTORY
The input map and sources are never modified. CSVs include every captured row.
"""
import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def union_length(spans, low, high):
    end = low
    total = 0
    for start, stop in sorted(spans):
        start, stop = max(low, start), min(high, stop)
        if stop > max(start, end):
            total += stop - max(start, end)
            end = stop
    return total


def summarize(report):
    trace = report['completed_job_trace']
    origin = trace['origin_us']
    grouped = defaultdict(list)
    units = []
    for event in trace['events']:
        grouped[(event['path'], event['generation'])].append(event)
        if event['event'] == 'main_unit':
            info = event['details']
            units.append(dict(path=event['path'], generation=event['generation'],
                              uuid=info.get('uuid', ''), stage=info['stage'],
                              start_ms=(info['start_us']-origin)/1000,
                              end_ms=(info['start_us']+info['duration_us']-origin)/1000,
                              duration_ms=info['duration_us']/1000))
    jobs = []
    for (path, generation), events in grouped.items():
        events.sort(key=lambda x: x['at_us'])
        times = defaultdict(list)
        worker_spans, main_spans = [], []
        for event in events:
            times[event['event']].append(event['at_us'])
            info = event.get('details', {})
            if event['event'] == 'worker_finished':
                worker_spans.append((info['started_us'], event['at_us']))
            if event['event'] == 'main_unit':
                main_spans.append((info['start_us'], info['start_us']+info['duration_us']))
        row = dict(path=path, generation=generation)
        for key in ['dispatch', 'worker_finished', 'joined', 'accepted', 'private_started', 'private_finished', 'committed', 'slot_released', 'lease_released']:
            row[key+'_first_ms'] = (times[key][0]-origin)/1000 if times[key] else None
            row[key+'_last_ms'] = (times[key][-1]-origin)/1000 if times[key] else None
        row.update(worker_invocations=len(worker_spans), joins=len(times['joined']),
                   main_units=len(main_spans), committed_members=len(times['committed']),
                   worker_wall_ms=sum(b-a for a,b in worker_spans)/1000,
                   main_work_wall_ms=sum(b-a for a,b in main_spans)/1000,
                   main_max_unit_ms=max((b-a for a,b in main_spans), default=0)/1000,
                   complete=bool(times['dispatch'] and times['slot_released']))
        if row['complete']:
            low, high = times['dispatch'][0], times['slot_released'][-1]
            row['queue_residence_ms'] = (high-low)/1000
            row['unattributed_residence_ms'] = (high-low-union_length(worker_spans+main_spans, low, high))/1000
        else:
            row['queue_residence_ms'] = row['unattributed_residence_ms'] = None
        jobs.append(row)
    stages = {}
    for unit in units:
        row = stages.setdefault(unit['stage'], dict(stage=unit['stage'], count=0, total_ms=0., max_ms=0.))
        row['count'] += 1
        row['total_ms'] += unit['duration_ms']
        row['max_ms'] = max(row['max_ms'], unit['duration_ms'])
    return dict(dropped=trace['dropped'], unit_clock_available=bool(units),
                note='Durations are wall spans, including locks/GPU waits. Unattributed residence includes scheduling, dependencies and frame gaps; it is not proven idle wait or CPU cost. Nested LoadTrace spans are separate and must not be added. Missing exit marks remain incomplete.',
                jobs=sorted(jobs, key=lambda x: x['queue_residence_ms'] or -1, reverse=True),
                stages=sorted(stages.values(), key=lambda x:x['total_ms'], reverse=True),
                units=sorted(units, key=lambda x: x['duration_ms'], reverse=True))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args=parser.parse_args()
    report=json.loads(args.profile.read_text(encoding='utf-8'))
    result=summarize(report)
    result['source_profile']=str(args.profile.resolve())
    result['map_sha']=report.get('map_sha')
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output/'latency.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    for name in ['jobs','units','stages']:
        rows=result[name]
        if not rows:continue
        with (args.output/(name+'.csv')).open('w', newline='', encoding='utf-8-sig') as file:
            writer=csv.DictWriter(file, fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    inner=report.get('monitor',{}).get('trace',{})
    spans=[e for e in inner.get('events',[]) if e['label'] in ['deferred.instance_specs','instance_spec.project','instance_spec.release_node','deferred.instance_begin','deferred.asset_instance_step','deferred.publish_commit','deferred.accept_complete','deferred.job']]
    spans.sort(key=lambda e:e['duration_us'], reverse=True)
    (args.output/'nested_spans.json').write_text(json.dumps({'dropped':inner.get('dropped'),'note':'Nested diagnostic call spans, not additive CPU work.','events':spans}, ensure_ascii=False, indent=2),encoding='utf-8')
    print(json.dumps({'jobs':len(result['jobs']),'units':len(result['units']),'dropped':result['dropped'],'unit_clock_available':result['unit_clock_available']}))
    print('PROCESSING_STAGES '+json.dumps(result['stages']))
    for row in result['units'][:12]:print(json.dumps(row,ensure_ascii=False))
    if not result['units']:
        for row in result['jobs'][:8]:print(json.dumps(row,ensure_ascii=False))


if __name__=='__main__':main()
