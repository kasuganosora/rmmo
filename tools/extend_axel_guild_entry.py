"""Narrow revision of saved finish master. The accepted prior export is immutable."""
import bpy,json,struct,hashlib,sys
from pathlib import Path
ROOT=Path('D:/code/rmmo');BASE=Path('D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1')
OUT=BASE/'entry_extension';OUT.mkdir(exist_ok=True)
sys.path.insert(0,str(ROOT/'tools'))
from axel_guild_entry_alignment import align
source=BASE/'axel_guild_finish.blend';source_sha=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
def fingerprint(o):
    return repr(([list(r) for r in o.matrix_world],list(o.items()),[list(v.co) for v in o.data.vertices] if o.type=='MESH' else []))
before={o.name:fingerprint(o) for o in bpy.data.objects}
report=align();changed=[o.name for o in bpy.data.objects if fingerprint(o)!=before[o.name]]
assert set(changed)=={'Entry upper step','Entry lower step'},changed
report['only_two_meshes_changed']=changed
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_entry.blend'),compress=True)
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    if not o.get('semantic_group','').startswith(('60_','70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT'):
        o.hide_set(False);o.select_set(True)
path=OUT/'axel_guild_entry_raw.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
def gltf(path):
    b=path.read_bytes();n,k=struct.unpack_from('<II',b,12);return b,n,k,json.loads(b[20:20+n])
_,_,_,baseline=gltf(BASE/'axel_guild_delivery.glb')
factors={m['name']:m.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]) for m in baseline['materials']}
b,n,k,j=gltf(path)
for m in j['materials']:
    if m['name'] in factors:m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=factors[m['name']]
payload=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4);binary=b[20+n:]
path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),k)+payload+binary)
assert hashlib.sha256(source.read_bytes()).hexdigest()==source_sha
report.update(source=str(source),source_sha=source_sha,source_unchanged=True,raw_sha=hashlib.sha256(path.read_bytes()).hexdigest())
# Actually reopen the revised master, rather than validating only in-memory data.
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_entry.blend'))
from axel_guild_entry_alignment import bounds
for item in report['changes']:assert bounds(bpy.data.objects[item['name']])==item['after']
report['saved_master_reopened']=True
(OUT/'entry_structure_review.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ENTRY_EXTENSION',json.dumps(report),flush=True)
