"""Incremental source-master/GLB repair, preserving all other binary bytes."""
import sys,json,hashlib,struct,shutil
from pathlib import Path
import bpy,numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from axel_guild_reference_exterior import repair_window_reveals
def parse(path):
    raw=path.read_bytes();magic,version,length=struct.unpack_from('<III',raw)
    assert magic==0x46546c67 and version==2 and length==len(raw)
    size,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
    doc=json.loads(raw[20:20+size]);count,kind=struct.unpack_from('<II',raw,20+size);assert kind==0x004e4942
    return doc,raw[28+size:28+size+count],hashlib.sha256(raw).hexdigest(),len(raw)
def values(doc,binary,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
    assert a['componentType']==5126 and a['type']=='VEC3'
    return np.ndarray((a['count'],3),dtype='<f4',buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',12),4))

ROOT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
ROLLBACK=ROOT/'rollback_before_window_reveal_20261013'
REPORT=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/window_reveal_repair')
EXPECTED='ff905eb6f9f47ec19b64b8b85ae200d28cbbc0bef5ae40bc77f28899dbdd1f8b'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
master=ROOT/'axel_guild_repaired.blend';source=ROOT/'axel_guild_repaired.glb'
assert sha(source)==EXPECTED,'Run only once against the diagnosed immutable source'
others={str(p):sha(p) for p in list((ROOT/'library').glob('*.glb'))+[ROOT/'guild_alarm_tower.glb',ROOT/'guild_alarm_tower.blend']}
ROLLBACK.mkdir(exist_ok=True);REPORT.mkdir(exist_ok=True)
for p in [master,source,ROOT/'repair_manifest.json']:
    dest=ROLLBACK/p.name
    if dest.exists():assert sha(dest)==sha(p),'Do not overwrite rollback'
    else:shutil.copyfile(p,dest)
bpy.ops.wm.open_mainfile(filepath=str(master))
change=repair_window_reveals();assert change['part_count']>0
candidate_master=ROOT/'axel_guild_repaired_reveal_candidate.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(candidate_master),compress=True)
doc,binary,original_sha,_=parse(source);patched=bytearray(binary)
by_name={n.get('name'):n for n in doc['nodes']}
positions={}
for row in change['parts']:
    n=by_name[row['name']]
    assert not any(k in n for k in ['matrix','translation','rotation','scale']),row['name']
    axis,sign={0:(0,1),1:(2,-1),2:(1,1)}[row['blender_axis']]
    center=sign*row['world_center']
    for prim in doc['meshes'][n['mesh']]['primitives']:
        ai=prim['attributes']['POSITION'];assert ai not in positions,'Unexpected shared position accessor'
        before=values(doc,binary,ai);after=values(doc,patched,ai)
        assert np.all(np.abs(before[:,axis]-center)>.04),row['name']
        after[:,axis]+=np.where(before[:,axis]>center,row['offset_m'],-row['offset_m']).astype(np.float32)
        a=doc['accessors'][ai];a['min']=after.min(axis=0).tolist();a['max']=after.max(axis=0).tolist()
        positions[ai]={'name':row['name'],'axis':axis,'offset_m':row['offset_m']}
    n.setdefault('extras',{})['window_reveal_revision']='20261013_lip12mm'
    n['extras']['project_design']='Stone opening surrounds overlap wall reveals by 12mm; prevents coplanar material conflict.'
# No non-target geometry may share modified accessors.
for n in doc['nodes']:
    if 'mesh' not in n:continue
    for p in doc['meshes'][n['mesh']]['primitives']:
        ai=p['attributes']['POSITION']
        if ai in positions:assert n.get('name')==positions[ai]['name']
# Prove every changed binary byte lies inside a target POSITION's selected axis.
allowed=np.zeros(len(binary),dtype=bool)
for ai,row in positions.items():
    a=doc['accessors'][ai];bv=doc['bufferViews'][a['bufferView']]
    start=bv.get('byteOffset',0)+a.get('byteOffset',0)+row['axis']*4;stride=bv.get('byteStride',12)
    for i in range(a['count']):allowed[start+i*stride:start+i*stride+4]=True
diff=np.frombuffer(binary,dtype=np.uint8)!=np.frombuffer(patched,dtype=np.uint8)
assert not np.any(diff&~allowed),'Unexpected binary edit'
encoded=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
candidate_glb=ROOT/'axel_guild_repaired_reveal_candidate.glb'
candidate_glb.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(patched))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(patched),0x004e4942)+patched)
newdoc,newbin,newsha,_=parse(candidate_glb);assert newbin==patched
bpy.ops.wm.open_mainfile(filepath=str(candidate_master))
assert all(bpy.data.objects[r['name']].get('window_reveal_revision')=='20261013_lip12mm' for r in change['parts'])
assert all(sha(Path(p))==h for p,h in others.items()),'Unrelated library/tower changed'
# All writes validated before replacing the working candidate. Rollback remains.
candidate_master.replace(master);candidate_glb.replace(source)
manifest=json.loads((ROOT/'repair_manifest.json').read_text(encoding='utf8'))
manifest['final_sha256']=newsha
manifest.setdefault('reference_fixes',{})['window_reveals']=change
manifest['window_reveal_rollback']=str(ROLLBACK)
manifest['window_reveal_repair']='Source-frame lips 12mm; main model only, furniture/tower byte-identical'
(ROOT/'repair_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
report={'source_sha256_before':original_sha,'source_sha256_after':newsha,'source':str(source),'source_master':str(master),'rollback':str(ROLLBACK),'parts':change['parts'],'part_count':change['part_count'],'binary_changed_bytes':int(diff.sum()),'only_target_position_bytes_changed':True,'unrelated_library_and_tower_unchanged':others,'native_and_gpu_status':'pending new-source validation'}
(REPORT/'build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('WINDOW_REVEAL_REPAIRED',newsha,change['part_count'],flush=True)
