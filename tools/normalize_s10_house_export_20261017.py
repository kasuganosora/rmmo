"""Remove one empty optional exporter declaration; preserve all GLB content."""
import copy,hashlib,json,struct
from pathlib import Path
root=Path('D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017')
src=root/'v2/s10_court_shutter_house.glb';dst=root/'v3/s10_court_shutter_house.glb'
raw=src.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jl]);original=copy.deepcopy(doc)
assert doc.get('extensionsUsed')==['GODOT_single_root'] and not doc.get('extensionsRequired')
def no_payload(x):
    if isinstance(x,dict):
        assert 'GODOT_single_root' not in x.get('extensions',{})
        for v in x.values():no_payload(v)
    elif isinstance(x,list):
        for v in x:no_payload(v)
no_payload(doc);del doc['extensionsUsed']
assert {k:v for k,v in original.items() if k!='extensionsUsed'}==doc
j=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
bin_chunk=raw[20+jl:];out=struct.pack('<III',0x46546c67,2,20+len(j)+len(bin_chunk))+struct.pack('<II',len(j),0x4e4f534a)+j+bin_chunk
assert not dst.exists();dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(out)
sha=lambda b:hashlib.sha256(b).hexdigest()
a=json.loads(src.with_name(src.stem+'_authoring.json').read_text(encoding='utf-8'))
a.update(path=dst.as_posix(),sha256=sha(out),source_bytes=len(out),export_compatibility={'baseline_path':src.as_posix(),'baseline_sha256':sha(raw),'change':'Remove unused optional extensionsUsed GODOT_single_root declaration only; no extension payload exists. All nodes, scenes, extras, accessors, materials and BIN bytes exactly retained. New runtime import/native/visual verification mandatory.','bin_chunk_sha256':sha(bin_chunk),'all_other_json_equal':True})
dst.with_name(dst.stem+'_authoring.json').write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('S10_NORMALIZED',sha(out),len(out))
