"""Reversibly relocate one obsolete isolated-review native payload, not assets.

No recursive deletion. Every index/footprint is checked, including atomic-save
previous files and checksum-wrapped JSON bodies. Current products are excluded.
"""
import argparse, hashlib, json, os, subprocess
from pathlib import Path

P=argparse.ArgumentParser();P.add_argument('phase',choices=['plan','apply']);A=P.parse_args()
ROOT=Path('D:/code/rmmo_runtime').resolve()
CACHE=(ROOT/'cache/world3d/compiled_assets_v1').resolve()
OUT=ROOT/'review_artifacts/s1_bridge_left_residence_20261017/v5_delivery'
PLAN=OUT/'cache_recovery_plan.json';RECEIPT=OUT/'cache_recovery_receipt.json'
PAYLOAD='00e6d9c1b01c48111db134133d4832d58578c9477d748e6529b6ede976e19728'
CURRENT='8738e0d9de9508c01fb51ec79b16d9e1733d873321a9a59b129d95fa0f9e5135'

def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def identity(p):return {'path':p.as_posix(),'sha256':sha(p),'bytes':p.stat().st_size}

def audit():
    metadata=[];references=[]
    for p in sorted(CACHE.rglob('*')):
        if not p.is_file() or p.suffix=='.scn':continue
        assert p.resolve().is_relative_to(CACHE) and not p.is_symlink()
        d=json.loads(p.read_text(encoding='utf-8-sig'));metadata.append(identity(p))
        if 'body' in d:
            assert hashlib.sha256(d['body'].encode()).hexdigest()==d['sha256']
            d=json.loads(d['body'])
        assert 'payload_sha' in d and 'generator' in d, 'Unknown metadata; stop'
        if d['payload_sha']==PAYLOAD:references.append({'metadata':p.as_posix(),**d})
    assert references and all(r['generator']!=CURRENT for r in references)
    source_rows=[r for r in references if r.get('source_path')]
    assert source_rows
    for r in source_rows:
        source=Path(r['source_path']).resolve()
        assert source.is_relative_to(ROOT/'cache/world3d') and 'guild_reference_import_' in source.as_posix()
        assert source.exists() and sha(source)==r['source_sha']
    return metadata,references

def no_gpu():
    active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip()
    assert not active, 'Another GPU process active: '+active

no_gpu();metadata,references=audit()
src=(CACHE/(PAYLOAD+'.scn')).resolve()
dst=(OUT/'stale_native_quarantine'/(PAYLOAD+'.scn')).resolve()
assert src.parent==CACHE and dst.parent==(OUT/'stale_native_quarantine').resolve()
assert not src.is_symlink() and not dst.exists() and sha(src)==PAYLOAD
if A.phase=='plan':
    assert not PLAN.exists()
    plan={'mode':'reversible stale isolated-review native quarantine; no source or map edits','current_generator':CURRENT,'payload':identity(src),'destination':dst.as_posix(),'metadata_guard':metadata,'references':references,'reason':'Every referring index/footprint uses an obsolete generator. Their original isolated-test GLB is present and SHA verified; current readers already reject these manifests before native loading.','recovery':'Move the preserved payload back to its exact original path after checking destination absence; metadata is left unchanged.'}
    PLAN.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('PLAN',src,src.stat().st_size)
else:
    assert not RECEIPT.exists();plan=json.loads(PLAN.read_text(encoding='utf-8'))
    assert plan['metadata_guard']==metadata and plan['payload']==identity(src)
    assert plan['destination']==dst.as_posix()
    dst.parent.mkdir(parents=True,exist_ok=True)
    receipt={'completed':False,'plan':identity(PLAN),'source':identity(src),'destination':dst.as_posix(),'deleted_bytes':0}
    RECEIPT.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    src.rename(dst)
    assert sha(dst)==PAYLOAD and not src.exists() and audit()[0]==metadata
    receipt.update(completed=True,cache_bytes_released=dst.stat().st_size,remaining_cache_bytes=sum(p.stat().st_size for p in CACHE.glob('*.scn')))
    temp=RECEIPT.with_suffix('.tmp');temp.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8');os.replace(temp,RECEIPT)
    print('QUARANTINED',receipt['cache_bytes_released'],'bytes; source retained, no deletion')
