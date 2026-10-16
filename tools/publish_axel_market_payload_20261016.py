"""Private-desktop runner for reviewed immutable market publication.

No publishing by default. Parent coordinates the GPU queue before --publish.
No map is opened or changed. A fresh take preserves any earlier failure receipt.
"""
from pathlib import Path
import argparse,json,re,subprocess
from run_godot_background import run_background

ROOT=Path('D:/code/rmmo')
REVIEW=Path('D:/code/rmmo_runtime/review_artifacts/axel_market_optimization_20261016')
ENGINE=Path('D:/tools/godot/Godot_v4.7.2-stable_win64.exe')
SCRIPT='res://tools/publish_axel_market_payload_20261016.gd'

def active_gpu():
    command="Get-CimInstance Win32_Process | Where-Object {$_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    result=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',command],capture_output=True,text=True,check=True)
    return json.loads(result.stdout) if result.stdout.strip() else []

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish',action='store_true');parser.add_argument('--take',required=True);parser.add_argument('--review-take',required=True);parser.add_argument('--timeout',type=int,default=1800)
    args=parser.parse_args()
    for key in ['take','review_take']:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',getattr(args,key)):raise ValueError('Take identifiers must be simple names')
    out=REVIEW/'publication'/args.take
    if out.exists():raise ValueError('Retain prior evidence; choose a fresh publication take')
    if args.publish and active_gpu():raise RuntimeError('GPU queue is occupied; do not publish concurrently')
    cmd=[str(ENGINE),*([] if args.publish else ['--headless']),'--path',str(ROOT),'--script',SCRIPT,'--',f'--take={args.take}',f'--review-take={args.review_take}',*(['--publish'] if args.publish else [])]
    try:
        result=run_background(cmd,cwd=ROOT,timeout=args.timeout) if args.publish else subprocess.run(cmd,cwd=ROOT,capture_output=True,timeout=args.timeout)
    except Exception as exc:
        out.mkdir(parents=True,exist_ok=True)
        (out/'runner_failure.json').write_text(json.dumps({'error':str(exc),'publish_requested':args.publish,'catalog_commit_status':'Inspect publication.json and actual current catalog; a process interruption is not success. No rollback of concurrent work attempted.'},indent=2),encoding='utf-8')
        raise
    out.mkdir(parents=True,exist_ok=True);(out/'engine.log').write_bytes((result.stdout or b'')+(getattr(result,'stderr',None) or b''))
    receipt=out/'publication.json';report=json.loads(receipt.read_text(encoding='utf-8')) if receipt.exists() else {}
    accepted=report.get('ok') and (report.get('catalog_committed') if args.publish else not report.get('catalog_committed'))
    print(json.dumps({'returncode':result.returncode,'receipt':str(receipt),'status':report.get('status'),'catalog_committed':report.get('catalog_committed',False),'mapping':report.get('mapping',[]),'map_modified':False},ensure_ascii=False))
    raise SystemExit(0 if result.returncode==0 and accepted else 1)

if __name__=='__main__':main()
