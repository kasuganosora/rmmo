"""Same-map/current-source ABBA; only compiled model admission changes."""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path('D:/code/rmmo')
OUT = Path('D:/code/rmmo_runtime/review_artifacts')
MAP = Path('D:/code/rmmo_runtime/cache/world3d/bridge_lod_checkpoint_20261011_1791699698203797000/map.gltf')
FORMAL = Path('D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf')
SHA = '779c513dc5433ddbe66d018471a8a505260e161d1656c690a00cde2675fb7a7f'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def fingerprint():
    files = sorted((ROOT / 'scripts').rglob('*.gd')) + [ROOT/'project.godot', ROOT/'tools/test_house_town_editor_incremental.gd']
    return hashlib.sha256(''.join(str(p.relative_to(ROOT))+sha(p) for p in files).encode()).hexdigest()

def main():
    if '--run' not in sys.argv:
        print('Use --run after CPU/GPU lifecycle tests; warm excluded then full/compiled/compiled/full.')
        return
    source = fingerprint()
    tag=next((arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--tag=')),'editor_native')
    assert tag in ['editor_native','editor_native_complete']
    rows = []
    output_summary = OUT/f'{tag}_abba_20261011.json'
    for label, mode in [('warm','full'),('a1','full'),('b1','compiled'),('b2','compiled'),('a2','full')]:
        assert sha(MAP)==sha(FORMAL)==SHA and fingerprint()==source
        output = OUT/f'{tag}_{label}_20261011.json'
        log = output.with_suffix('.log')
        hardware = output.with_suffix('.hardware.json')
        command = [sys.executable, str(ROOT/'tools/profile_load_hardware.py'), '--timeout','300','--log',str(log),'--hardware',str(hardware),'--',
                   'D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/test_house_town_editor_incremental.gd','--',
                   '--output='+str(output),'--map='+str(MAP),'--expected-sha='+SHA,'--native-model-budget='+mode,'--load-trace']
        result = subprocess.run(command,cwd=ROOT,timeout=330)
        logs = log.read_text(encoding='utf-8',errors='replace')
        if result.returncode or 'SCRIPT ERROR:' in logs or '\nERROR:' in logs:
            print(label,'FAILED',logs[-5000:],flush=True)
            raise SystemExit(1)
        data = json.loads(output.read_text(encoding='utf-8'))
        times = data['load_result']['timings']
        row = {k:data.get(k) for k in ['load_ms','failures','full_rebuilds','baseline_full_rebuilds','final_house_count','final_record_count','native_model_footprints']}
        row.update(label=label,mode=mode,report=str(output),log=str(log),hardware=str(hardware),passes=logs.count('PASS:'),
                   units=times['build']['units'],preparation=times.get('preparation',{}),
                   lookahead=times.get('asset_lookahead',{}),warnings=[s for s in logs.splitlines() if s.startswith('WARNING:')])
        assert not row['failures'] and row['passes']>=113 and row['full_rebuilds']==row['baseline_full_rebuilds']
        if tag=='editor_native_complete' and mode=='compiled':
            assert row['lookahead']['native_candidates']==32 and row['lookahead']['compiled_hits']==32
        assert row['final_house_count']==61 and row['final_record_count']==4437
        assert sha(MAP)==sha(FORMAL)==SHA and fingerprint()==source
        rows.append(row)
        summary={'rows':rows,'source_fingerprint':source,'map_sha':SHA,
                 'scope':'Fresh processes, excluded warm, same new LOD map/current code and two workers; no OS/asset-cache reset. HTTP operations after loading. Budget is conservative accounting, not OS RSS.'}
        if len(rows)==5:
            summary['means']={}
            for group in ['full','compiled']:
                measured=[r for r in rows if r['mode']==group and r['label']!='warm']
                summary['means'][group]={'load_ms':statistics.mean(r['load_ms'] for r in measured),
                    'asset_wait_ms':statistics.mean(r['units']['asset_wait']['total_ms'] for r in measured),
                    'asset_worker_ms':statistics.mean(r['units']['asset_parse_worker']['total_ms'] for r in measured)}
        output_summary.write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({k:v for k,v in row.items() if k not in ['units','preparation','lookahead']}),flush=True)

if __name__=='__main__':main()
