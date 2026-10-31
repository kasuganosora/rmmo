"""Run native trace contracts and equal-work probes in an external fixture.

The default runs three independent CPU processes and one private-desktop GPU
probe. The results measure the diagnostic component, not map loading or FPS.
Existing output directories are never overwritten. Run when no other Godot or
compiler workload is active; the monitor only reads matching processes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from godot_process_monitor import workload_snapshot
from run_godot_background import run_background
from summarize_debug_timeline import analyze, export, read_capture


def run_suite(engine, output, repeats=3, gpu=True):
    repo=Path(__file__).resolve().parents[1]
    output=Path(output).resolve()
    if output==repo or repo in output.parents:
        raise ValueError('Use an external review_artifacts directory, outside the Godot project')
    if 'review_artifacts' not in output.parts:
        raise ValueError('Output must be inside review_artifacts')
    output.mkdir(parents=True,exist_ok=False)
    project=output/'project';project.mkdir()
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="NativeTimelineContract"\n[rendering]\nrenderer/rendering_method="forward_plus"\n',encoding='utf8')
    files=['scripts/util/debug_timeline.gd','tools/test_debug_timeline.gd',
           'tools/test_debug_timeline_gpu.gd','tools/benchmark_debug_timeline.gd']
    sources={}
    for rel in files:
        dest=project/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(repo/rel,dest)
        sources[rel]=hashlib.sha256(dest.read_bytes()).hexdigest()
    engine=Path(engine).resolve()
    engine_sha=hashlib.sha256(engine.read_bytes()).hexdigest()
    index=[]

    def run(name,script,use_gpu=False):
        other=workload_snapshot()
        if other:raise RuntimeError(f'Another workload is active: {other}')
        out=output/name;out.mkdir();env=os.environ.copy()
        for key in ['APPDATA','LOCALAPPDATA','TEMP','TMP']:
            directory=out/key;directory.mkdir();env[key]=str(directory)
        arguments=['--output='+str(out/'result.json')] if 'benchmark' in script else ['--output-dir='+str(out)]
        command=[str(engine),*([] if use_gpu else ['--headless']),'--path',str(project),
                 '--script','res://tools/'+script,'--',*arguments]
        started=time.monotonic();print('START',name,flush=True)
        if use_gpu:
            old=os.environ.copy();os.environ.update(env)
            try:result=run_background(command,cwd=project,timeout=180)
            finally:os.environ.clear();os.environ.update(old)
        else:
            result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                  timeout=180,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        (out/'engine.log').write_bytes(result.stdout)
        receipt=dict(name=name,exit=result.returncode,seconds=time.monotonic()-started,
                     command=command,engine_sha256=engine_sha,sources=sources)
        index.append(receipt)
        def save():
            (output/'validation_index.json').write_text(json.dumps(index,indent=2),encoding='utf8')
        save()
        if result.returncode or b'ERROR:' in result.stdout:
            raise RuntimeError(f'{name} failed; inspect {out / "engine.log"}')
        report=json.loads((out/'result.json').read_text(encoding='utf8'))
        assert not report.get('failed') and not report.get('failures'),report
        if 'benchmark' in script:
            assert len(report['rows'])==21 and all(r['ok'] for r in report['rows'])
        captures=[]
        for path in out.glob('*.rmtrace'):
            header,events=read_capture(path);analysis=analyze(header,events)
            assert not analysis['orphan_ends'] and not analysis['crossing_spans'],path
            assert not analysis['task_name_conflicts'],path
            captures.append(dict(file=path.name,events=header['events'],dropped=header['dropped'],
                                 threads=header['threads'],incomplete=analysis['incomplete_spans']))
            if path.stem=='parallel':
                work=[s for s in analysis['spans'] if s['label']=='test.work']
                assert len(work)==49152 and all(s['complete'] for s in work) and header['dropped']==0
            if path.stem=='restart':
                assert all(s['task']==9002 for s in analysis['spans'] if s['label']=='test.work')
            if path.stem=='names':
                assert header['events']==4608 and header['dropped']==0 and len(header['task_names'])==6
                assert len(analysis['spans'])==1536
                assert all(s['task_name']==('prepare/石材' if s['task']%2==0 else 'release/木材') for s in analysis['spans'])
            if path.stem=='names_overflow':
                assert header['events']==256 and header['dropped']==44 and len(header['task_names'])==256
            if use_gpu:
                assert header['dropped']==0
                labels={s['label'] for s in analysis['spans']}
                assert {'resource.load','render.draw','render.sync','mesh.surface_material',
                        'worker.execute','worker.wait','vulkan.submit_present','test.gpu.worker'}<=labels
                assert any(j['task_name']=='Trace contract task' and j['executions']==1 for j in analysis['jobs'])
                assert any(j['task_name']=='Trace group contract' and j['executions']>=2 for j in analysis['jobs'])
                export(path,out/'decoded')
        receipt.update(checks=report.get('checks'),captures=captures);save()
        print('PASS',name,flush=True)

    for i in range(1,repeats+1):
        run(f'contract{i:02d}','test_debug_timeline.gd')
        run(f'benchmark{i:02d}','benchmark_debug_timeline.gd')
    if gpu:run('gpu01','test_debug_timeline_gpu.gd',True)
    return index


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,default=Path('D:/tools/godot/debug-trace-4.8/godot.windows.editor.x86_64.exe'))
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--repeats',type=int,default=3)
    parser.add_argument('--no-gpu',action='store_true',help='CPU contracts only; not full integration acceptance')
    args=parser.parse_args()
    if args.repeats<1:parser.error('--repeats must be positive')
    run_suite(args.godot,args.output,args.repeats,not args.no_gpu)
