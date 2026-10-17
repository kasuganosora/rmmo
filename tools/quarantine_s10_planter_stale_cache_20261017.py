"""Recover bounded cache space by preserving two obsolete isolated-test payloads."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path('D:/code/rmmo_runtime').resolve();CACHE=(ROOT/'cache/world3d/compiled_assets_v1').resolve();OUT=ROOT/'review_artifacts/s10_warm_brick_planter_20261017'
CURRENT='8738e0d9de9508c01fb51ec79b16d9e1733d873321a9a59b129d95fa0f9e5135'
PAYLOADS=['e8e06e0aa3bc4dfd58213ae376ef767c7bbbb0cf64ff3c286b0decd3fda7bc42','2259b28bdc8517f7b5b8899415ab6ce8fc326c98dd97d0d54399c9fba03c3e7f']
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ident(p):return {'path':p.as_posix(),'sha256':sha(p),'bytes':p.stat().st_size}
def audit():
    refs={k:[] for k in PAYLOADS};guards=[]
    for p in sorted(CACHE.rglob('*')):
        if not p.is_file() or p.suffix=='.scn':continue
        assert p.resolve().is_relative_to(CACHE) and not p.is_symlink()
        d=json.loads(p.read_text(encoding='utf-8-sig'));guards.append(ident(p))
        if 'body' in d:
            assert hashlib.sha256(d['body'].encode()).hexdigest()==d['sha256'];d=json.loads(d['body'])
        assert 'payload_sha' in d and 'generator' in d,'Unknown metadata blocks operation'
        if d['payload_sha'] in refs:refs[d['payload_sha']].append({'metadata':p.as_posix(),**d})
    for payload,rr in refs.items():
        assert rr and all(r['generator']!=CURRENT for r in rr)
        sources=[r for r in rr if r.get('source_path')];assert sources
        for r in sources:
            p=Path(r['source_path']).resolve();assert p.is_relative_to(ROOT/'cache/world3d')
            assert any(s in p.as_posix() for s in ['imported_buildings_http_11766896','guild_reference_import_11782615'])
            assert p.exists() and sha(p)==r['source_sha']
    return refs,guards
active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip();assert not active,'GPU busy'
receipt=OUT/'cache_capacity_recovery.json';assert not receipt.exists()
refs,guards=audit();rows=[]
for payload in PAYLOADS:
    src=(CACHE/(payload+'.scn')).resolve();dst=(OUT/'stale_native_quarantine'/(payload+'.scn')).resolve()
    assert src.parent==CACHE and dst.parent==(OUT/'stale_native_quarantine').resolve()
    assert not src.is_symlink() and sha(src)==payload and not dst.exists()
    rows.append({'source':ident(src),'destination':dst.as_posix(),'references':refs[payload]})
record={'completed':False,'mode':'reversible move of obsolete isolated-test derived native; no source/map edits','current_generator':CURRENT,'rows':rows,'all_metadata_guards':guards,'deleted_bytes':0,'reason':'Both payloads refer only to old-generator isolated tests. Current readers reject those indices already; original GLBs and every metadata file remain intact.','recovery':'After verifying destination absence, move each preserved payload back to its original source path and verify SHA.'}
receipt.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
for row in rows:
    dst=Path(row['destination']);dst.parent.mkdir(parents=True,exist_ok=True);Path(row['source']['path']).rename(dst);assert sha(dst)==row['source']['sha256']
assert audit()[1]==guards
record.update(completed=True,cache_bytes_released=sum(r['source']['bytes'] for r in rows));receipt.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print('PRESERVED_STALE_NATIVE',record['cache_bytes_released'],'bytes; no deletion')
