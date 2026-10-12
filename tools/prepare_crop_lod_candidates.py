"""Add opt-in native screen-error LOD metadata without changing GLB BIN data."""
import hashlib,json,struct
from pathlib import Path
src=Path('D:/code/rmmo_runtime/art_sources/editor_extensions_20261012/wheat_v1')
out=src.parent/'wheat_lod_v2';out.mkdir(exist_ok=True)
report=[]
for variant in ('ripe','green'):
    path=src/f'wheat_{variant}.glb';raw=path.read_bytes();size,kind=struct.unpack_from('<II',raw,12)
    data=json.loads(raw[20:20+size]);tail=raw[20+size:]
    for node in data['nodes']:
        if 'mesh' in node:node.setdefault('extras',{})['rmmo_auto_lod']=True
    encoded=json.dumps(data,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    candidate=struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),kind)+encoded+tail
    target=out/path.name
    if target.exists():assert target.read_bytes()==candidate
    else:target.write_bytes(candidate)
    report.append(dict(variant=variant,source=str(path),candidate=str(target),source_sha=hashlib.sha256(raw).hexdigest(),candidate_sha=hashlib.sha256(candidate).hexdigest(),bin_sha=hashlib.sha256(tail).hexdigest(),bin_unchanged=True))
(out/'candidates.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
