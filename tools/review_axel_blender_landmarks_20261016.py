"""Serial candidate GPU reviewer; private desktop and Q90 WebP before model viewing."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
from run_godot_background import run_background

ROOT = Path('D:/code/rmmo')
ART = Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016')
REVIEW = ROOT / 'review_artifacts/axel_landmarks_20261016'
FIXTURES = Path('D:/code/rmmo_runtime/review_fixtures/axel_landmarks_20261016')
ENGINE = Path('D:/tools/godot/Godot_v4.7.2-stable_win64.exe')
STATUS = REVIEW / 'gpu_status.json'
spec = importlib.util.spec_from_file_location('review_image', 'C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py')
image_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image_module)

def sha(path):
    with Path(path).open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()

def put(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def active_gpu():
    script = "Get-CimInstance Win32_Process | Where-Object {$_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    result = subprocess.run(['powershell','-NoProfile','-Command',script],capture_output=True,text=True,check=True)
    return json.loads(result.stdout) if result.stdout.strip() else []

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind',choices=['church','guardhouse','watermill'])
    parser.add_argument('version')
    parser.add_argument('--take',default='gpu')
    parser.add_argument('--timeout',type=int,default=900)
    parser.add_argument('--physics-only',action='store_true')
    parser.add_argument('--reuse-fixture')
    parser.add_argument('--views',help='Comma-separated existing gallery names for a targeted material recheck')
    args=parser.parse_args()
    busy=active_gpu()
    if busy:
        put(STATUS,{'state':'waiting_for_other_gpu','other_processes':busy,'updated':time.time(),'owner':'blender_church'})
        print(json.dumps({'gpu_busy':busy},ensure_ascii=False));return 3
    manifest=json.loads((ART/args.kind/args.version/'manifest.json').read_text(encoding='utf-8'))
    item=manifest['exports'][0] if 'exports' in manifest else manifest.get('export',manifest.get('source',{}))
    source=Path(item.get('path',item.get('glb',item.get('file',''))))
    digest=item.get('sha256','')
    if not source.is_file() or sha(source)!=digest:
        raise ValueError('Manifest source identity mismatch')
    folder=REVIEW/args.kind/args.version/args.take
    folder.mkdir(parents=True,exist_ok=True)
    if (folder/'report.json').exists():
        raise ValueError('Use a new --take name; retain prior evidence')
    isolated=FIXTURES/(args.kind+'_'+args.version+'_'+(args.reuse_fixture or args.take))
    command=[str(ENGINE),'--path',str(ROOT),'--script','res://tools/review_axel_blender_landmarks_20261016.gd','--',
             '--source='+source.as_posix(),'--sha='+digest,'--out='+folder.as_posix(),
             '--kind='+args.kind,'--fixture-root='+isolated.as_posix()]
    if args.physics_only:command.append('--physics-only')
    if args.views:command.append('--views='+args.views)
    state={'state':'starting','owner':'blender_church','asset':args.kind,'version':args.version,'source_sha':digest,'output':folder.as_posix(),'updated':time.time()}
    put(STATUS,state)
    def started(pid,tid):
        state.update(state='running',pid=pid,tid=tid,updated=time.time());put(STATUS,state)
    last=[0.]
    def poll():
        if time.time()-last[0]>15:
            state['updated']=time.time();put(STATUS,state);last[0]=time.time()
    print('GPU_BEGIN',args.kind,args.version,digest,flush=True)
    try:
        result=run_background(command,cwd=ROOT,timeout=args.timeout,on_start=started,on_poll=poll)
        (folder/'engine.log').write_bytes(result.stdout)
        code=result.returncode
        if b'SCRIPT ERROR:' in result.stdout or b'ERROR:' in result.stdout:
            code=code or 1
    except subprocess.TimeoutExpired as error:
        (folder/'engine.log').write_bytes((error.stdout or b'')+b'\nOWNED REVIEW TIMEOUT\n')
        code=124
    finally:
        state.update(state='render_process_ended',updated=time.time());put(STATUS,state)
    receipts=[]
    for path in sorted(folder.glob('*.png')):
        receipts.append(image_module.prepare(path,lossless=False,keep_source=False,quality=90))
    put(folder/'image_upload_receipts.json',receipts)
    report_path=folder/'report.json'
    if report_path.exists():
        report=json.loads(report_path.read_text(encoding='utf-8'))
        lookup={Path(row['source']).name:row for row in receipts}
        for shot in report.get('screenshots',[]):
            receipt=lookup.get(Path(shot['path']).name)
            if receipt:
                shot['original_png_sha256']=shot['sha256']
                shot['path']=receipt['path'];shot['sha256']=receipt['sha256']
                shot['upload_encoding']={'quality':90,'lossless':False,'dimensions':receipt['dimensions'],'source_bytes':receipt['source_bytes'],'bytes':receipt['bytes']}
        report['image_review_status']='awaiting_actual_visual_inspection'
        report['engine_error_free']=code==0
        if code!=0:
            report['passed']=False
            report.setdefault('failures',[]).append('Engine reported error; inspect engine.log')
        put(report_path,report)
    state.update(state='released',exit_code=code,updated=time.time(),images=len(receipts));put(STATUS,state)
    print(json.dumps({'kind':args.kind,'version':args.version,'exit':code,'images':len(receipts),'report':report_path.as_posix()},ensure_ascii=False),flush=True)
    return code

if __name__=='__main__':
    sys.exit(main())
