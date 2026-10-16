"""Serial private-desktop publication of final accepted landmark candidates."""
from pathlib import Path
import argparse, hashlib, json, subprocess
from run_godot_background import run_background

ROOT = Path('D:/code/rmmo')
REVIEW = ROOT/'review_artifacts/axel_landmarks_20261016'
ENGINE = 'D:/tools/godot/Godot_v4.7.2-stable_win64.exe'
MODELS = {'guardhouse': ('v6', '阿克塞尔警卫处'), 'church': ('v8', '厄里斯教团教会'), 'watermill': ('v11', '阿克塞尔水磨坊')}

def sha(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--publish', action='store_true');p.add_argument('--asset', choices=list(MODELS)+['all'], default='all')
    p.add_argument('--take', required=True)
    args=p.parse_args()
    if not args.take.replace('_','').isalnum():raise ValueError('Simple take name required')
    cmd="Get-CimInstance Win32_Process | Where-Object {$_.Name -like '*godot*' -and $_.CommandLine -notmatch '--headless'} | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
    active=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',cmd],capture_output=True,text=True,check=True)
    if active.stdout.strip():raise RuntimeError('GPU is occupied; coordinate queue first')
    chosen=MODELS if args.asset=='all' else {args.asset:MODELS[args.asset]}
    for name,(version,label) in chosen.items():
        proof=REVIEW/name/version/'acceptance.json';data=json.loads(proof.read_text(encoding='utf-8'))
        assert data['passed'] and sha(data['source_path'])==data['source_sha256']
        out=REVIEW/'publication'/f'{name}_{args.take}.json'
        if out.exists():raise FileExistsError(out)
        out.parent.mkdir(parents=True,exist_ok=True)
        command=[ENGINE,'--path',str(ROOT),'--script','res://tools/import_axel_landmark_20261016.gd','--',
                 '--publish',f'--source={data["source_path"]}',f'--sha256={data["source_sha256"]}',
                 f'--review={proof.as_posix()}',f'--review-sha256={sha(proof)}',f'--out={out.as_posix()}',
                 f'--id=axel_{name}_20261016',f'--label={label}','--category=城镇地标建筑']
        if not args.publish:
            print(json.dumps({'asset':name,'status':'ready_not_published','proof_sha256':sha(proof)},ensure_ascii=False));continue
        run=run_background(command,cwd=ROOT,timeout=600)
        out.with_suffix('.log').write_bytes(run.stdout)
        report=json.loads(out.read_text(encoding='utf-8')) if out.exists() else {}
        print(json.dumps({'asset':name,'exit':run.returncode,'ok':report.get('ok',False),'receipt':out.as_posix()},ensure_ascii=False),flush=True)
        if run.returncode or not report.get('ok'):raise RuntimeError('Publication incomplete; inspect exact receipt without overwriting it')

if __name__=='__main__':main()
