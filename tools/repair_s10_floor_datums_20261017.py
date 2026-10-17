"""Fix two authored floor metadata values; preserve every geometry/image byte."""
import json,struct,hashlib,copy
from pathlib import Path
root=Path('D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017');p=root/'v3/s10_court_shutter_house.glb';dst=root/'v4'/p.name
raw=p.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+jl]);original=copy.deepcopy(d);changes=[]
for i,n in enumerate(d['nodes']):
    e=n.get('extras',{});part=e.get('rmmo_part',{})
    if e.get('uuid') in ['s10part_972','s10part_973']:
        assert part['floor']==0 and abs(part['floor_y']-.3)<.000001
        changes.append({'node_index':i,'uuid':e['uuid'],'old':part['floor_y'],'new':.3});part['floor_y']=.3
assert len(changes)==2
check=copy.deepcopy(d)
for c in changes:check['nodes'][c['node_index']]['extras']['rmmo_part']['floor_y']=c['old']
assert check==original
j=json.dumps(d,ensure_ascii=False,separators=(',',':')).encode();j+=b' '*((-len(j))%4);binary=raw[20+jl:]
out=struct.pack('<III',0x46546c67,2,20+len(j)+len(binary))+struct.pack('<II',len(j),0x4e4f534a)+j+binary
assert not dst.exists();dst.parent.mkdir(parents=True);dst.write_bytes(out)
a=json.loads(p.with_name(p.stem+'_authoring.json').read_text(encoding='utf-8'));a.update(path=dst.as_posix(),sha256=hashlib.sha256(out).hexdigest(),source_bytes=len(out),floor_datum_revision={'source_path':p.as_posix(),'source_sha256':hashlib.sha256(raw).hexdigest(),'changes':changes,'all_other_json_equal':True,'bin_chunk_sha256':hashlib.sha256(binary).hexdigest(),'reason':'Designed 0.3m ground-floor datum; remove float32 promotion tail from two inherited candle-sconce semantic parts. Geometry, transforms, pixels, hinges unchanged.'})
dst.with_name(dst.stem+'_authoring.json').write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(a['sha256'])
