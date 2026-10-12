"""Private-desktop FIFO/private-residency ABBA with identical full native footprint estimates."""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT=Path('D:/code/rmmo')
OUT=Path('D:/code/rmmo_runtime/review_artifacts')
MAP=Path('D:/code/rmmo_runtime/cache/world3d/bridge_lod_checkpoint_20261011_1791699698203797000/map.gltf')
FORMAL=Path('D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf')
SHA='779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fingerprint():
    files=sorted((ROOT/'scripts').rglob('*.gd'))+[ROOT/'project.godot',ROOT/'tools/test_house_town_editor_incremental.gd']
    return hashlib.sha256(''.join(str(p.relative_to(ROOT))+sha(p) for p in files).encode()).hexdigest()

def descriptors():
    previous=json.loads((OUT/'editor_native_complete_b1_20261011.json').read_text(encoding='utf-8'))
    paths=sorted({e['details']['path'] for e in previous['load_trace']['events'] if e['label']=='editor.model_parse'})
    assert len(paths)==32
    folder=Path('D:/code/rmmo_runtime/cache/world3d/compiled_assets_v1')
    result={}
    for path in paths:
        key=hashlib.sha256(path.encode()).hexdigest()+'.json'
        for file in [folder/key,folder/'footprints_v1'/key]:
            result[str(file)]=sha(file)
    return result

def main():
    if '--run' not in sys.argv:
        print('Use --run after residency CPU and GPU regressions.');return
    tag=next((s.split('=',1)[1] for s in sys.argv if s.startswith('--tag=')),'editor_residency')
    assert tag in ['editor_residency','editor_residency_v2']
    code=fingerprint(); products=descriptors(); rows=[]
    for label,mode in [('warm','off'),('a1','off'),('b1','on'),('b2','on'),('a2','off')]:
        assert sha(MAP)==sha(FORMAL)==SHA and fingerprint()==code and descriptors()==products
        output=OUT/f'{tag}_{label}_20261011.json'; log=output.with_suffix('.log'); hardware=output.with_suffix('.hardware.json')
        cmd=[sys.executable,str(ROOT/'tools/profile_load_hardware.py'),'--timeout','300','--log',str(log),'--hardware',str(hardware),'--',
             'D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/test_house_town_editor_incremental.gd','--',
             '--output='+str(output),'--map='+str(MAP),'--expected-sha='+SHA,'--native-model-budget=compiled','--preparation-lanes=fifo','--model-residency='+mode,'--load-trace']
        result=subprocess.run(cmd,cwd=ROOT,timeout=330)
        lines=log.read_text(encoding='utf-8',errors='replace')
        assert result.returncode==0 and 'SCRIPT ERROR:' not in lines and '\nERROR:' not in lines, lines[-5000:]
        data=json.loads(output.read_text(encoding='utf-8')); timings=data['load_result']['timings']
        row={k:data.get(k) for k in ['load_ms','failures','full_rebuilds','baseline_full_rebuilds','final_house_count','final_record_count','preparation_lanes','model_residency']}
        row.update(label=label,mode=mode,report=str(output),log=str(log),hardware=str(hardware),passes=lines.count('PASS:'),
                   units=timings['build']['units'],preparation=timings['preparation'],lookahead=timings['asset_lookahead'],published_models=timings.get('published_models',{}),
                   warnings=[s for s in lines.splitlines() if s.startswith('WARNING:')])
        assert not row['failures'] and row['passes']>=113 and row['full_rebuilds']==row['baseline_full_rebuilds']
        assert row['final_house_count']==61 and row['final_record_count']==4437
        assert row['preparation_lanes'] is False and row['model_residency']==(mode=='on')
        assert row['lookahead']['native_candidates']==32 and row['lookahead']['compiled_hits']==32
        queue=row['preparation']; ledger=queue['ledger']
        assert queue['lanes_enabled']==(mode=='on') and queue['resident_enabled']==(mode=='on') and queue['queued']==queue['consumed']==40
        assert ledger['jobs']==ledger['reserved_bytes']==ledger['active_workers']==0
        assert queue['peak_inflight']<=4 and queue['peak_resident']<=8 and ledger['peak_workers']<=2
        assert queue['peak_private_bytes']<=4*1024**3 and not row['lookahead']['ownership_rejections']
        if mode=='on':
            assert queue['resident_entered']>0 and row['published_models']['published_envelope_bytes']>0
        assert queue['diagnostics']['enabled'] and queue['diagnostics']['tasks_dropped']==0 and data['load_trace']['dropped']==0
        assert sha(MAP)==sha(FORMAL)==SHA and fingerprint()==code and descriptors()==products
        rows.append(row)
        summary={'rows':rows,'source_fingerprint':code,'map_sha':SHA,'descriptor_sha256':products,
                 'scope':'Fresh-process excluded warm + off/on/on/off. Same current town, native footprint route for 32 models, worker2 and full transient envelope4GiB. Candidate changes 4 result slots to 4 inflight plus 8 private resident slots; published native envelopes tracked separately, not a total process cap. Same trace/hardware sampling. No OS/cache reset. HTTP editing follows load timing; author content unchanged.'}
        if len(rows)==5:
            summary['means']={mode:{'load_ms':statistics.mean(r['load_ms'] for r in rows if r['mode']==mode and r['label']!='warm'),
                                    'asset_wait_ms':statistics.mean(r['units']['asset_wait']['total_ms'] for r in rows if r['mode']==mode and r['label']!='warm')}
                              for mode in ['off','on']}
        (OUT/f'{tag}_abba_20261011.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({k:v for k,v in row.items() if k not in ['units','preparation','lookahead']}),flush=True)

if __name__=='__main__':main()
