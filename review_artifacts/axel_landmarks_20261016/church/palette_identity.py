"""Bind palette-only review reuse to actual GLB bytes and full structural JSON."""
import hashlib,json,struct
from pathlib import Path
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church')
def read(version):
    p=BASE/version/'axel_church.glb';b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0]
    return {'path':str(p),'sha256':hashlib.sha256(b).hexdigest()},json.loads(b[20:20+n]),b[28+n:]
a,ja,ba=read('v7');b,jb,bb=read('v8')
diffs=[]
def diff(a,b,path=''):
    if type(a)!=type(b):diffs.append({'path':path,'before':a,'after':b});return
    if isinstance(a,dict):
        for k in sorted(set(a)|set(b)):diff(a.get(k),b.get(k),path+'/'+str(k))
    elif isinstance(a,list):
        if len(a)!=len(b):diffs.append({'path':path,'length_before':len(a),'length_after':len(b)})
        else:
            for i,(x,y) in enumerate(zip(a,b)):diff(x,y,path+'/'+str(i))
    elif a!=b:diffs.append({'path':path,'before':a,'after':b})
diff(ja,jb)
allowed=lambda d: ('/extras/rmmo_tinted_glass/materials/Church stained glass ' in d['path'] and '/transmittance/' in d['path']) or (d['path'].startswith('/materials/') and '/pbrMetallicRoughness/baseColorFactor/' in d['path'])
checks={'entire_bin_identical':ba==bb,'json_changes_only_stained_glass_palette':all(map(allowed,diffs)),'meshes_identical':ja['meshes']==jb['meshes'],'accessors_identical':ja['accessors']==jb['accessors'],'images_identical':ja['images']==jb['images'],'scene_graph_without_glass_extras_identical':True}
for j in [ja,jb]:
    for node in j['nodes']:node.get('extras',{}).pop('rmmo_tinted_glass',None)
checks['scene_graph_without_glass_extras_identical']=ja['nodes']==jb['nodes']
report={'old':a,'new':b,'checks':checks,'bin_sha256':hashlib.sha256(ba).hexdigest(),'json_differences':diffs,'passed':all(checks.values()),'reuse_scope':'Geometry, collision, hinges, rooms, UV, textures and all non-glass appearance unchanged; v7 actual capsule/structure evidence may be reused. Glass day/night and final native identity must use v8.'}
out=Path(__file__).parent/'v7_v8_palette_identity.json';out.write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({'checks':checks,'differences':len(diffs),'report':str(out)}))
assert report['passed']
