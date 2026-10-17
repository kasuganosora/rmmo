"""Reference-specific mature crown, using the reviewed owned tree mother.
CPU Blender only; preserves source, leaf/fruit dimensions, PBR, and LOD roles.
"""
import bpy, bmesh, math, json, hashlib, struct, argparse, sys
from mathutils import Vector
import numpy as np
from pathlib import Path
P=argparse.ArgumentParser();P.add_argument('--version',default='v1');A=P.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
BASE=Path('D:/code/rmmo_runtime/art_sources/s10_court_variants_20261017');OUT=BASE/A.version;OUT.mkdir(parents=True,exist_ok=True)
SRC=Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/redfruit_master_reviewed.blend')
ID='s10_mature_redfruit_courtyard';path=OUT/(ID+'.glb');assert not path.exists()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
source_sha=sha(SRC);bpy.ops.wm.open_mainfile(filepath=str(SRC))
def height(z):
    # Monotone cubic stretches the clear stem, then compresses crown height.
    xs=[0.,.2,.92,6.62];ys=[0.,.40,2.30,6.85];ds=[2.,2.25,1.0,.72]
    if z<0:return z
    if z>=xs[-1]:return ys[-1]+(z-xs[-1])*ds[-1]
    i=next(i for i in range(3) if xs[i]<=z<xs[i+1]);h=xs[i+1]-xs[i];t=(z-xs[i])/h
    return (2*t**3-3*t**2+1)*ys[i]+(t**3-2*t*t+t)*h*ds[i]+(-2*t**3+3*t*t)*ys[i+1]+(t**3-t*t)*h*ds[i+1]
def field(p):
    x,y,z=p;h=height(z)
    thick=1.17+.40*max(0,1-z/1.35)**2
    lean=.28*math.sin(min(1,max(0,h/6.85))*math.pi)
    return np.array([x*thick+lean,y*thick+.09*math.sin(h*.7),h])
manifest=json.loads(Path('D:/code/rmmo_runtime/art_sources/required_street_assets_20261013/review_v2/manifest.json').read_text(encoding='utf-8'))
original=next(r for r in manifest['assets'] if r['id']=='s10_redfruit_broadleaf')
specs=original['fruit_anchors'];anchors=[]
for f in specs:
    a=np.array(f['anchor']);c=np.array(f['centre']);anchors.append({**f,'anchor':field(a).tolist(),'centre':(field(a)+c-a).tolist()})
rows=[]
for ob in [o for o in bpy.data.objects if o.type=='MESH']:
    me=ob.data;old=np.array([v.co[:] for v in me.vertices]);new=np.array([field(p) for p in old])
    # Connected leaf cards retain their own size and shape, rather than being
    # stretched with the crown. Fruit and stems translate together at anchors.
    parent=list(range(len(old)))
    def find(x):
        while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
        return x
    roles={};movable=set()
    for poly in me.polygons:
        name=me.materials[poly.material_index].name.lower()
        role='leaf' if 'leaf' in name else 'fruit' if 'fruit' in name else 'bark'
        if role=='bark':continue
        vs=list(poly.vertices);head=find(vs[0])
        for v in vs:parent[find(v)]=head;movable.add(v);roles[v]=role
    islands={}
    for i in movable:islands.setdefault(find(i),[]).append(i)
    for indexes in islands.values():
        centre=old[indexes].mean(axis=0);role=roles[indexes[0]]
        if role=='leaf':delta=field(centre)-centre
        else:
            spec=min(specs,key=lambda f:np.linalg.norm(centre-np.array(f['anchor'])))
            a=np.array(spec['anchor']);delta=field(a)-a
        new[indexes]=old[indexes]+delta
    for v,p in zip(me.vertices,new):v.co=p
    me.update()
    # The old canopy bark had a constant UV (all corners at zero); do not
    # carry that defect into a newly authored tree. Give each radial branch
    # a stable local planar projection; original leaf/fruit UVs stay untouched.
    if 'Canopy' in ob.name:
        uv=me.uv_layers.active
        for face in me.polygons:
            if 'bark' not in me.materials[face.material_index].name.lower():continue
            n=face.normal.normalized();p=face.center
            grain=Vector((p.x,p.y,max(.3,p.z-2.2)))
            v=grain-n*grain.dot(n)
            if v.length<.001:v=Vector((0,0,1))-n*n.z
            if v.length<.001:v=Vector((1,0,0))-n*n.x
            v.normalize();u=v.cross(n).normalized()
            for li in face.loop_indices:
                co=me.vertices[me.loops[li].vertex_index].co
                uv.data[li].uv=(co.dot(u)/.8,co.dot(v)/1.8)
    if 'Trunk' in ob.name:
        uv=me.uv_layers.active
        for face in me.polygons:
            if face.center.z>2.5:continue
            axis=0 if abs(face.normal.y)>abs(face.normal.x) else 1
            for li in face.loop_indices:
                p=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(p[axis],p.z/2.)
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.triangulate(bm,faces=list(bm.faces))
    zero=[f for f in bm.faces if f.calc_area()<5e-11]
    bmesh.ops.delete(bm,geom=zero,context='FACES_ONLY');bm.to_mesh(me);bm.free();me.update()
    ob['asset_id']=ID;ob['reference_revision']='S10 courtyard 20261017'
    if 'rmmo_visibility_range' in ob:
        d=ob['rmmo_visibility_range'].to_dict();d['bounds']=[-4.25,-.15,-4.25,8.5,7.4,8.5];ob['rmmo_visibility_range']=d
        d=ob['rmmo_editor_picking'].to_dict();d['group']='s10_mature_canopy';ob['rmmo_editor_picking']=d
    rows.append({'name':ob.name,'triangles':sum(len(p.vertices)-2 for p in me.polygons),'rigid_leaf_fruit_islands':len(islands)})
master=OUT/(ID+'_master.blend');bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_extras=True,export_animations=False,export_tangents=True,export_cameras=False,export_lights=False)
raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);binary=raw[28+n:]
leaf=[]
for i,m in enumerate(doc['materials']):
    if 'leaf' in m.get('name','').lower():m.update(alphaMode='MASK',alphaCutoff=.4,doubleSided=True);leaf.append(i)
    if 'bark' in m.get('name','').lower():m['pbrMetallicRoughness']['baseColorFactor']=[.30,.36,.36,1.]
for node in doc['nodes']:
    if 'mesh' in node:node.setdefault('extras',{})['rmmo_leaf_backlight']=[.14 if p.get('material') in leaf else 0. for p in doc['meshes'][node['mesh']]['primitives']]
js=json.dumps(doc,separators=(',',':')).encode();js+=b' '*((-len(js))%4)
path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary)
row={'id':ID,'path':path.as_posix(),'sha256':sha(path),'source_bytes':path.stat().st_size,'master':master.as_posix(),'master_sha256':sha(master),'source_master':SRC.as_posix(),'source_master_sha256':source_sha,'baseline_glb':'D:/code/rmmo_runtime/packs/default/assets/28f99fef1a9a78bf8ae4fa68127eeabb8687b35b8a84e1d1d8fc6d5bfcc15c67.glb','source_fab':original.get('source_fab'),'fruit_anchors':anchors,'objects':rows,'anchors':{'ground_origin':[0,0,0],'stem_at_1_3m':[.15,1.3,-.08],'crown_center':[.1,4.6,0],'front_axis':'+Z'},'scope':'New silhouette is project design matching S10; species unconfirmed. Leaf cards and fruit keep original physical sizes. Existing LOD 0/45/100 and wind retained; no new performance claims.'}
(OUT/(ID+'_authoring.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2),encoding='utf-8');assert sha(SRC)==source_sha
print('S10_TREE_BUILT',row['sha256'],flush=True)
