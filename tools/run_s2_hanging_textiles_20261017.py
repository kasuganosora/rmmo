"""One serial private-desktop queue; checks other GPU processes before each job."""
import argparse,json,subprocess
from pathlib import Path
from run_godot_background import run_background
P=argparse.ArgumentParser();P.add_argument('--version',default='v2');P.add_argument('--only',default='all');P.add_argument('--review-name');A=P.parse_args()
ROOT=Path('D:/code/rmmo');SRC=Path('D:/code/rmmo_runtime/art_sources/s2_hanging_textiles_20261017')/A.version
OUT=Path('D:/code/rmmo_runtime/review_artifacts/s2_hanging_textiles_20261017')/(A.review_name or A.version)
for source in sorted(SRC.glob('*.glb')):
    if A.only!='all' and A.only not in source.stem:continue
    folder=OUT/source.stem
    if (folder/'report.json').exists():
        print('Preserved evidence',source.stem,flush=True);continue
    active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip()
    if active:raise RuntimeError('Other GPU job active '+active)
    folder.mkdir(parents=True,exist_ok=True)
    cmd=['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/review_s2_hanging_textiles_20261017.gd','--','--source='+source.as_posix(),'--out='+folder.as_posix()]
    print('Review start',source.stem,flush=True);r=run_background(cmd,cwd=ROOT,timeout=240);(folder/'process.log').write_bytes(r.stdout);print('Review end',source.stem,r.returncode,flush=True)
    if r.returncode:raise SystemExit(r.returncode)
