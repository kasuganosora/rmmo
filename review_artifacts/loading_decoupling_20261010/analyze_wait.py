"""Read diagnostic output only; wall spans are not exclusive CPU attribution."""
from bisect import bisect_right
from collections import Counter
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parent
EXTERNAL = Path('D:/code/rmmo_runtime/review_artifacts/loading_decoupling_20261010')

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def at(samples, epoch, x=0, y=1):
    times = [row[x] for row in samples]
    i = bisect_right(times, epoch)-1
    if i < 0 or i+1 >= len(samples):
        return None
    a,b = samples[i:i+2]
    return a[y] + (b[y]-a[y])*(epoch-a[x])/(b[x]-a[x])

reports = []
for tag, filename in [('wait_valid','wait_entry.json'), ('wait_no_wct','wait_no_wct.json'), ('wait_sparse_wct','wait_sparse_wct.json'), ('mesh_parts','mesh_parts.json')]:
    folder = ROOT/tag
    if not (EXTERNAL/filename).exists() or not (folder/'main_cpu.json').exists():
        continue
    report=read(EXTERNAL/filename)
    cpu=read(folder/'main_cpu.json')
    hardware=read(folder/'wait_entry.hardware.json')
    wct=read(folder/'main_wct.json') if (folder/'main_wct.json').exists() else {'samples':[]}
    offset=report['monitor']['start_epoch_s']-report['monitor']['start_ticks_us']/1e6
    process_samples=[[x['epoch_s'],x['cpu_s']] for x in hardware['samples']]
    events=report['monitor']['trace']['events']
    def interval(label,start,end,details=None):
        begin,finish=offset+start/1e6,offset+end/1e6
        wall=(end-start)/1000
        a,b=at(cpu['samples'],begin),at(cpu['samples'],finish)
        pa,pb=at(process_samples,begin),at(process_samples,finish)
        queries=[q for q in wct['samples'] if begin<=q['unix_begin']<finish]
        chains=Counter()
        owners=Counter()
        for q in queries:
            chains[' / '.join(n['type']+':'+n['status'] for n in q['nodes'])]+=1
            for n in q['nodes'][1:]:
                if n['type']=='thread':owners[str(n['tid'])]+=1
        return {'label':label,'start_ticks_us':start,'end_ticks_us':end,'wall_ms':wall,
                'main_cpu_ms':(b-a)*1000 if a is not None and b is not None else None,
                'process_cpu_equivalents':(pb-pa)*1000/wall if pa is not None and pb is not None and wall else None,
                'queries':len(queries),'chains':dict(chains),'owners':dict(owners),'details':details or {}}
    selected=[]
    for label in ['game.parse','game.asset_preparation','game.build','game.cooked_restore','game.index_wait','game.texture_join_wait']:
        for e in events:
            if e['label']==label:
                selected.append(interval(label,e['start_us'],e['end_us']))
    world=report['world_profile']
    end=world['entry_safety_ready_us']
    for label in ['stream','player','environment','navigation','events','hud','batches','radar']:
        next_end=world[label]*1000
        if next_end>=end:
            selected.append(interval('world.'+label,end,next_end))
            end=next_end
    longest=[]
    labels={'game.asset_generate','game.asset_instantiate','game.mesh','deferred.publication','compiled.native_read','compiled.source_sha','compiled.payload_sha'}
    chosen=sorted([e for e in events if e['label'] in labels],key=lambda e:e['duration_us'],reverse=True)[:18]
    for e in sorted([e for e in events if e['label'] in {'game.mesh','deferred.publication','game.asset_instantiate','game.asset_generate'}],key=lambda e:e['duration_us'],reverse=True)[:12]:
        if e not in chosen:chosen.append(e)
    for e in chosen:
        longest.append(interval(e['label'],e['start_us'],e['end_us'],e['details']))
    costs=sorted(q['query_ms'] for q in wct['samples'])
    item={'tag':tag,'entry_ms':report['entry_ms'],'functional_failures':report['failures'],
          'hardware_pid':hardware['pid'],'cpu_pid':cpu['pid'],'hardware_tid':hardware['main_thread_id'],'cpu_tid':cpu['thread_id'],
          'trace_drops':report['monitor']['trace']['dropped'],
          'map_sha':report['map_sha'],'formal_sha':report['formal_sha'],'build_frames':report['map_profile']['frames'],
          'wct_query_cost_ms':{'median':median(costs),'p95':costs[int(len(costs)*.95)],'max':max(costs)} if costs else None,
          'intervals':selected,'long_events':longest}
    reports.append(item)
    print(tag, 'entry',item['entry_ms'],'frames',item['build_frames'],'wct_cost',item['wct_query_cost_ms'])
    for v in selected:
        print(v['label'],round(v['wall_ms'],2),'mainCPU',round(v['main_cpu_ms'],2) if v['main_cpu_ms'] is not None else None,
              'processCores',round(v['process_cpu_equivalents'],2) if v['process_cpu_equivalents'] is not None else None,
              'WCTowners',v['owners'])

output={'runs':reports,'limitations':[
    'High-frequency WCT is intrusive to measurement; diagnostic timings are not comparison benchmark results.',
    'WCT can identify supported wait chains but a single node cannot exclude unsupported waits.',
    'Critical-section owners are Windows thread IDs, not Godot trace IDs; no function, lock or renderer attribution without stacks.',
    'Main CPU interpolation uses 5 ms requested sampling with actual sample timestamps and coarse OS CPU tick resolution.',
    'Process CPU uses about 0.5 s sampling. Nested/overlapping intervals must not be added as exclusive time.',
    'World navigation interval overlaps deferred HUD instantiation; it is not all navigation CPU work.'
]}
(ROOT/'wait_analysis.json').write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
