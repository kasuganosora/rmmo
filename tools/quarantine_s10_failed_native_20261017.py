"""Retain, outside the bounded cache, only our withdrawn failed v3 payload."""
import json,hashlib,subprocess,sys
from pathlib import Path
root=Path('D:/code/rmmo_runtime').resolve();out=root/'review_artifacts/s10_court_variants_20261017';cache=(root/'cache/world3d/compiled_assets_v1').resolve()
version='v4' if '--v4' in sys.argv else 'v3'
publication=json.loads((out/('publication/s10_court_shutter_house_'+version+'.json')).read_text(encoding='utf-8'))
native=publication['items'][0]['native_identity'];source_sha=native['source_sha'];payload=native['payload_sha']
assert source_sha in ['cf85469f586104ab4c51b009f349befe1d846f94c16e042f4f58f7b56a71d33b','522e58d7080bc010d0a512343ff8b7d9837818ebce454373f4b3ec0f28748d78']
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
assert not subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip(),'GPU in use'
withdraw=json.loads((out/('publication/withdrawn_house_'+version+'.json')).read_text(encoding='utf-8'));assert withdraw['completed'] and withdraw['source_sha256']==source_sha
entries=json.loads((root/'packs/default/assets/library.json').read_text(encoding='utf-8'));assert not any(source_sha in e.get('asset_path','') for e in entries)
source=root/'packs/default/assets'/(source_sha+'.glb');assert sha(source)==source_sha
refs=[]
for p in sorted(cache.rglob('*')):
    if not p.is_file() or p.suffix=='.scn':continue
    d=json.loads(p.read_text(encoding='utf-8-sig'))
    if 'body' in d:
        assert hashlib.sha256(d['body'].encode()).hexdigest()==d['sha256'];d=json.loads(d['body'])
    assert 'payload_sha' in d and 'generator' in d,'Unknown metadata'
    if d['payload_sha']==payload:
        assert d['source_sha']==source_sha;refs.append({'path':p.as_posix(),'sha256':sha(p)})
assert refs
src=(cache/(payload+'.scn')).resolve();dst=(out/('withdrawn_native_'+version)/(payload+'.scn')).resolve();receipt=out/('withdrawn_native_'+version+'_receipt.json')
assert src.parent==cache and dst.parent==(out/('withdrawn_native_'+version)).resolve()
assert not src.is_symlink() and not dst.exists() and not receipt.exists() and sha(src)==payload
dst.parent.mkdir(parents=True,exist_ok=True);src.rename(dst)
assert sha(dst)==payload and all(sha(r['path'])==r['sha256'] for r in refs)
receipt.write_text(json.dumps({'completed':True,'source':src.as_posix(),'destination':dst.as_posix(),'sha256':payload,'bytes':dst.stat().st_size,'references':refs,'deleted_bytes':0,'reason':'Our own failed '+version+' is withdrawn from catalog; retain recoverable native outside bounded cache. Original GLB and metadata retained.'},indent=2)+'\n',encoding='utf-8');print('S10_WITHDRAWN_NATIVE_RETAINED',dst.stat().st_size)
