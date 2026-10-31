"""Decode native memory captures after execution; export a global timeline.

Every captured event is retained in events.csv; dependencies.csv connects waits
to native task execution without needing a viewer.
spans.csv separates wall duration from optional coarse OS thread CPU. Rankings
subtract nested same-thread spans for exclusive wall time, never for CPU time.
Unmatched scopes remain incomplete, including scopes crossing capture stop.
"""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path
import struct


def read_capture(path):
    with Path(path).open('rb') as file:
        if file.read(8) != b'RMMOTRC1':
            raise ValueError('Not a native debug trace')
        length_data = file.read(8)
        if len(length_data) != 8:
            raise ValueError('Truncated header length')
        length = struct.unpack('<Q', length_data)[0]
        raw = file.read(length)
        if len(raw) != length:
            raise ValueError('Truncated metadata')
        header = json.loads(raw)
        if header.get('version') != 1 or header.get('format') != 'QQQqqIIQ':
            raise ValueError('Unsupported native trace schema')
        record = struct.Struct(('<' if header['byte_order'] == 'little' else '>') + header['format'])
        if record.size != header['event_bytes']:
            raise ValueError('Event layout disagrees with metadata')
        data = file.read()
        if len(data) % record.size:
            raise ValueError('Truncated event payload')
        events = list(record.iter_unpack(data))
        if len(events) != header['events']:
            raise ValueError('Captured count disagrees with exported payload')
    # Equal timestamps retain each writer's original order. They do not prove
    # causal ordering between different threads.
    events.sort(key=lambda row: row[0])
    return header, events


def analyze(header, events):
    active = {}
    spans = []
    orphan_ends = []
    counts = defaultdict(int)
    queued = {}
    task_names = defaultdict(set)
    labels = header['labels']
    def name(label):
        return labels[label] if 0 <= label < len(labels) else f'unknown:{label}'
    for order, (wall, cpu, token, task, value, label, kind, thread) in enumerate(events):
        counts[thread] += 1
        if kind == 1:
            key = (thread, token)
            if key in active:
                raise ValueError(f'Duplicate begin: {key}')
            active[key] = dict(thread=thread, span=token, task=task, label=name(label),
                               context=value, start_us=wall, start_cpu_us=cpu, start_order=order, complete=False)
        elif kind == 2:
            row = active.pop((thread, token), None)
            if row is None:
                orphan_ends.append(dict(thread=thread, span=token, at_us=wall))
                continue
            if wall < row['start_us'] or (header['cpu_clock'] and cpu < row['start_cpu_us']):
                raise ValueError('Thread clock moved backwards')
            row.update(end_us=wall, wall_us=wall-row['start_us'], complete=True,
                       cpu_us=cpu-row['start_cpu_us'] if header['cpu_clock'] else None)
            spans.append(row)
        elif kind == 0 and name(label) == 'worker.enqueue':
            key=(value,task)
            if key in queued:raise ValueError(f'Duplicate native task enqueue {key}')
            queued[key]=dict(task=task,context=value,queued_us=wall,queued_thread=thread)
        elif kind == 0 and name(label) == 'worker.name':
            resolved=header.get('task_names',{}).get(str(token))
            if resolved is None:raise ValueError(f'Missing task name metadata {token}')
            task_names[value,task].add(resolved)
        elif kind != 0:
            raise ValueError(f'Unknown event kind {kind}')
    for row in active.values():
        row.update(end_us=None, wall_us=None, cpu_us=None)
        spans.append(row)
    for row in spans:
        row['task_name']=' | '.join(sorted(task_names.get((row['context'],row['task']),[])))
    # Parentage uses completed same-thread spans. Cross-thread work must be
    # linked by task ID and cannot be subtracted from another thread's time.
    by_thread = defaultdict(list)
    for row in spans:
        row['parent_span'] = None
        row['exclusive_wall_us'] = row['wall_us']
        if row['complete']:
            by_thread[row['thread']].append(row)
    crossing = 0
    for rows in by_thread.values():
        stack = []
        thread_crossings = 0
        for row in sorted(rows, key=lambda r: (r['start_us'], -r['end_us'], r['start_order'])):
            while stack and row['start_us'] >= stack[-1]['end_us']:
                stack.pop()
            if stack:
                parent = stack[-1]
                if row['end_us'] <= parent['end_us']:
                    row['parent_span'] = parent['span']
                    parent['exclusive_wall_us'] -= row['wall_us']
                else:
                    crossing += 1
                    thread_crossings += 1
            stack.append(row)
        if thread_crossings:
            for row in rows:row['exclusive_wall_us'] = None
    rankings = {}
    task_rankings = {}
    for row in spans:
        for table,task_name in [(rankings,''),*([(task_rankings,row['task_name'])] if row['task_name'] else [])]:
            key = (row['thread'], row['label'],task_name)
            total = table.setdefault(key, dict(thread=row['thread'], label=row['label'],task_name=task_name,count=0,
                incomplete=0, inclusive_wall_us=0, exclusive_wall_us=0, max_wall_us=0, coarse_cpu_us=0 if header['cpu_clock'] else None))
            if not row['complete']:
                total['incomplete'] += 1
                continue
            total['count'] += 1
            total['inclusive_wall_us'] += row['wall_us']
            if row['exclusive_wall_us'] is None:total['exclusive_wall_us'] = None
            elif total['exclusive_wall_us'] is not None:total['exclusive_wall_us'] += row['exclusive_wall_us']
            total['max_wall_us'] = max(total['max_wall_us'], row['wall_us'])
            if header['cpu_clock']:
                total['coarse_cpu_us'] += row['cpu_us']
    jobs=dict(queued)
    waits=[]
    for row in spans:
        if row['label'] not in ['worker.execute','worker.wait']:continue
        key=(row['context'],row['task'])
        job=jobs.setdefault(key,dict(task=row['task'],context=row['context'],queued_us=None,queued_thread=None))
        if row['label']=='worker.execute':job.setdefault('executions',[]).append(row)
        else:waits.append(row)
    task_rows=[]
    executions={key:job.get('executions',[]) for key,job in jobs.items()}
    for job in jobs.values():
        execution=job.pop('executions',[])
        first=min((row['start_us'] for row in execution),default=None)
        last=max((row['end_us'] for row in execution if row['complete']),default=None)
        if job['queued_us'] is not None and first is not None and first<job['queued_us']:
            raise ValueError('Native task execution precedes its enqueue')
        task_rows.append(dict(job,task_name=' | '.join(sorted(task_names.get((job['context'],job['task']),[]))),executions=len(execution),first_start_us=first,last_end_us=last,
            enqueue_to_first_start_us=first-job['queued_us'] if first is not None and job['queued_us'] is not None else None,
            complete_executions=sum(row['complete'] for row in execution),
            execution_wall_sum_us=sum(row['wall_us'] for row in execution if row['complete'])))
    dependencies=[]
    task_index={(job['context'],job['task']):job for job in task_rows}
    for wait in waits:
        key=(wait['context'],wait['task']);job=task_index[key]
        dependencies.append(dict(waiter_thread=wait['thread'],wait_span=wait['span'],
            context=key[0],task=key[1],task_name=wait['task_name'],
            queued_us=job['queued_us'],enqueue_to_first_start_us=job['enqueue_to_first_start_us'],
            wait_start_us=wait['start_us'],wait_end_us=wait['end_us'],wait_wall_us=wait['wall_us'],
            executions=[dict(thread=s['thread'],span=s['span'],start_us=s['start_us'],end_us=s['end_us'],
                             wall_us=s['wall_us'],cpu_us=s['cpu_us']) for s in executions.get(key,[])]))
    return dict(metadata=header, events_per_thread=dict(counts), orphan_ends=orphan_ends,
                incomplete_spans=sum(not r['complete'] for r in spans), crossing_spans=crossing,
                spans=sorted(spans, key=lambda r: r['start_us']),
                jobs=sorted(task_rows,key=lambda r:r['enqueue_to_first_start_us'] if r['enqueue_to_first_start_us'] is not None else -1,reverse=True),
                waits=waits,
                dependencies=dependencies,
                task_name_conflicts=[dict(context=k[0],task=k[1],names=sorted(v)) for k,v in task_names.items() if len(v)>1],
                task_rankings=sorted(task_rankings.values(),key=lambda r:r['exclusive_wall_us'] if r['exclusive_wall_us'] is not None else -1,reverse=True),
                rankings=sorted(rankings.values(), key=lambda r: r['exclusive_wall_us'] if r['exclusive_wall_us'] is not None else -1, reverse=True),
                note='Wall spans include waits. Nested inclusive totals are not additive. CPU uses optional coarse GetThreadTimes; short-span CPU deltas may be zero or exceed wall duration due to quantization. Cross-thread ties do not establish order. Uninstrumented gaps are not proof of idle.')


def export(path, output):
    header, events = read_capture(path)
    result = analyze(header, events)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=False)
    (output/'summary.json').write_text(json.dumps({k:v for k,v in result.items() if k not in ['spans','jobs','waits','dependencies']}, ensure_ascii=False, indent=2), encoding='utf8')
    (output/'dependencies.json').write_text(json.dumps(result['dependencies'],ensure_ascii=False,indent=2),encoding='utf8')
    with (output/'events.csv').open('w', newline='', encoding='utf-8-sig') as file:
        writer=csv.writer(file); writer.writerow(header['columns'].split(',')); writer.writerows(events)
    for key in ['spans', 'rankings','task_rankings','jobs','waits']:
        rows = result[key]
        if rows:
            with (output/(key+'.csv')).open('w', newline='', encoding='utf-8-sig') as file:
                writer=csv.DictWriter(file, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    dependency_rows=[]
    for dependency in result['dependencies']:
        common={k:v for k,v in dependency.items() if k!='executions'}
        common['execution_segments']=len(dependency['executions'])
        # A group can have multiple executors. Keep one row per wait/segment;
        # the repeated wait duration must not be summed across these rows.
        for execution in dependency['executions'] or [None]:
            dependency_rows.append(dict(common,execution_observed=execution is not None,
                **{'executor_'+key:execution.get(key) if execution else None
                   for key in ['thread','span','start_us','end_us','wall_us','cpu_us']}))
    if dependency_rows:
        with (output/'dependencies.csv').open('w',newline='',encoding='utf-8-sig') as file:
            writer=csv.DictWriter(file,fieldnames=list(dependency_rows[0]));writer.writeheader();writer.writerows(dependency_rows)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=export(args.capture,args.output)
    print(json.dumps({k:result[k] for k in ['events_per_thread','incomplete_spans','crossing_spans','orphan_ends']}))
    print(json.dumps(result['rankings'][:15],ensure_ascii=False))


if __name__=='__main__':main()
