"""Serial private-desktop S12 captures; no foreground windows or formal writes."""
import argparse,json,subprocess,sys
from pathlib import Path
from run_godot_background import run_background
P=argparse.ArgumentParser();P.add_argument('--version',default='v1');P.add_argument('--only',default='all');A=P.parse_args()
ROOT=Path('D:/code/rmmo');SRC=Path('D:/code/rmmo_runtime/art_sources/s12_residential_details_20261017')/A.version
OUT=Path('D:/code/rmmo_runtime/review_artifacts/s12_residential_details_20261017')/A.version
jobs=[('s12_red_gold_pennant_a','banner'),('s12_red_gold_pennant_b','banner'),('s12_doorstep_jar','jar'),('s12_freestanding_courtyard_gate','gate'),('s12_riverside_residence','house')]
for name,kind in jobs:
    if A.only not in ['all',kind,name]:continue
    folder=OUT/name
    if (folder/'report.json').exists():
        old=json.loads((folder/'report.json').read_text(encoding='utf-8'))
        if not old.get('passed'):raise RuntimeError('Existing failed evidence; choose new output version')
        print('Preserved existing successful report',name,flush=True);continue
    active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip()
    if active:raise RuntimeError('Other GPU test active: '+active)
    folder.mkdir(parents=True,exist_ok=True)
    command=['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/review_s12_residential_details_20261017.gd','--','--source='+str(SRC/(name+'.glb')).replace('\\','/'),'--out='+str(folder).replace('\\','/'),'--kind='+kind]
    print('Review starting',name,flush=True)
    result=run_background(command,cwd=ROOT,timeout=240)
    (folder/'process.log').write_bytes(result.stdout)
    print('Review finished',name,result.returncode,flush=True)
    if result.returncode:raise SystemExit(result.returncode)
print('S12_SERIAL_REVIEW_FINISHED',flush=True)
