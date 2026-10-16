"""Normalize the stable source UUID contract without re-exporting model bytes."""
from pathlib import Path
import copy,hashlib,json,re,struct
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill')
OUT=Path(__file__).resolve().parent
DEST=BASE/'v9';DEST.mkdir(exist_ok=True)
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,j):Path(p).write_text(json.dumps(j,ensure_ascii=False,indent=2),encoding='utf-8')
def normal(value):return re.sub(r'[^A-Za-z0-9_-]','_',value)
def normalize(j,changes):
    if isinstance(j,dict):
        for k,v in list(j.items()):
            if k=='uuid' and isinstance(v,str):
                new=normal(v)
                if new!=v:changes.append({'old':v,'new':new});j[k]=new
            else:normalize(v,changes)
    elif isinstance(j,list):
        for v in j:normalize(v,changes)
manifest=json.loads((BASE/'v8/manifest.json').read_text(encoding='utf-8'));reports=[]
for entry in manifest['exports']:
    source=Path(entry['file']);assert digest(source)==entry['sha256'];raw=source.read_bytes();n,t=struct.unpack_from('<II',raw,12);assert t==0x4e4f534a
    j=json.loads(raw[20:20+n]);before=copy.deepcopy(j);changes=[];normalize(j,changes)
    expected=copy.deepcopy(before);ignore=[];normalize(expected,ignore);assert expected==j
    encoded=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    bin_chunk=raw[20+n:];payload=struct.pack('<III',0x46546c67,2,20+len(encoded)+len(bin_chunk))+struct.pack('<II',len(encoded),t)+encoded+bin_chunk
    target=DEST/source.name
    if target.exists():assert target.read_bytes()==payload
    else:target.write_bytes(payload)
    names=[n.get('extras',{}).get('uuid') for n in j.get('nodes',[]) if n.get('extras',{}).get('uuid')]
    assert len(names)==len(set(names)) and all(re.fullmatch(r'[A-Za-z0-9_-]+',v) for v in names)
    reports.append({'source':str(source),'source_sha256':entry['sha256'],'candidate':str(target),'candidate_sha256':digest(target),'bin_chunk_sha256':hashlib.sha256(bin_chunk).hexdigest(),'bin_chunk_byte_equal':True,'all_json_except_uuid_equal':True,'uuid_changes':changes})
    entry.update(file=str(target),sha256=digest(target),bytes=target.stat().st_size)
normalize(manifest,[]);manifest['version']='v9';manifest['builder']={'file':'D:/code/rmmo/tools/build_blender_axel_watermill_20261016.py','sha256':digest('D:/code/rmmo/tools/build_blender_axel_watermill_20261016.py')}
manifest['uuid_migration']={'script':str(Path(__file__).resolve()),'sha256':digest(__file__),'source_version':'v8','scope':'Only UUID JSON fields changed; exact existing BIN chunk retained for all five GLBs. Blender master migration is metadata-only.'}
manifest['master']={'file':str(DEST/'axel_watermill_master.blend'),'sha256':'PENDING_MASTER_METADATA_SAVE'}
write(DEST/'manifest.json',manifest);write(OUT/'v8_v9_uuid_identity.json',reports)
# Blender runs this separate bounded metadata-only save, no GLB exports/rendering.
blender="""import bpy,re
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=r'D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill/v8/axel_watermill_master.blend')
for o in bpy.data.objects:
    if 'uuid' in o:o['uuid']=re.sub(r'[^A-Za-z0-9_-]','_',str(o['uuid']))
bpy.ops.wm.save_as_mainfile(filepath=r'D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill/v9/axel_watermill_master.blend')
"""
(OUT/'save_v9_master.py').write_text(blender,encoding='utf-8')
print(json.dumps({'exports':manifest['exports'],'proof':str(OUT/'v8_v9_uuid_identity.json')}))
