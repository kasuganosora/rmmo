"""Finish the new repair master: conservative LOD tags and missing exterior sockets."""
import bpy,sys,json,struct,hashlib
from mathutils import Vector
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from compact_axel_guild import compact
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_repaired.blend'))
manifest=json.loads((OUT/'repair_manifest.json').read_text(encoding='utf8'))
redundant=['203 TWIN side.001','204 TWIN side.001','05 WASHROOM side.001','05 WASHROOM end.001']
for name in redundant:
    old=bpy.data.objects.get(name)
    if old is None or old.type!='MESH':continue
    empty=bpy.data.objects.new(name+' repaired lining marker',None)
    for col in old.users_collection:col.objects.link(empty)
    empty.parent=old.parent;empty.matrix_world=old.matrix_world
    for k,v in old.items():empty[k]=v
    empty['redundant_lining_removed']=True
    bpy.data.objects.remove(old,do_unlink=True);empty.name=name
manifest['overlapping_lining_removed']=redundant
sockets={}
for root in bpy.data.objects:
    if root.get('asset_id')!='guild_facade_wall_lantern':continue
    glass=[o for o in root.children_recursive if o.type=='MESH' and any('glass' in m.name.lower() for m in o.data.materials)]
    if not glass:continue
    points=[root.matrix_world.inverted()@o.matrix_world@Vector(c) for o in glass for c in o.bound_box]
    p=sum(points,Vector())/len(points)
    socket={'position':[p.x,p.z,-p.y],'color':[1,.86,.69],'range':4.0,'energy':.35,'flame':False,'indoor':False}
    root['rmmo_light_socket']=socket;sockets[root.name]=socket
def read(p):
    b=p.read_bytes();n,k=struct.unpack_from('<II',b,12);return b,n,k,json.loads(b[20:20+n])
def patch(p):
    b,n,k,j=read(p)
    marked=[]
    for node in j['nodes']:
        if node.get('name') in redundant:
            node.pop('mesh',None);node.setdefault('extras',{})['redundant_lining_removed']=True
        if node.get('name') in sockets:node.setdefault('extras',{})['rmmo_light_socket']=sockets[node['name']]
        if 'mesh' not in node:continue
        e=node.setdefault('extras',{});e['whitebox_only']=False
        if e.get('rmmo_wind') or e.get('rmmo_hinge'):continue
        m=j['meshes'][node['mesh']]
        tris=sum(j['accessors'][v['indices']]['count']//3 for v in m['primitives'] if 'indices' in v)
        if tris>=2000 and e.get('independent_prop') and e.get('semantic_group') not in ['12_Facade_Detail']:
            # Exclude textiles/transparent geometry; retain the exact base mesh.
            materials=[j['materials'][v['material']] for v in m['primitives'] if 'material' in v]
            if any(v.get('alphaMode','OPAQUE')!='OPAQUE' for v in materials):continue
            if any(any(w in v.get('name','').lower() for w in ['cloth','banner','tapestry','linen','bed linen']) for v in materials):continue
            e['rmmo_auto_lod']=True;marked.append(node['name'])
    # Map authored metadata back to the native editable mother before saving.
    for name in marked:
        if name in bpy.data.objects:bpy.data.objects[name]['rmmo_auto_lod']=True
    payload=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4)
    binary=b[20+n:];p.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),k)+payload+binary)
    return marked
manifest['lod_tagged_meshes']=patch(OUT/'axel_guild_repaired.glb')
for row in manifest['library']:
    p=Path(row['path']);row['lod_meshes']=patch(p);row['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
for o in bpy.data.objects:
    if 'whitebox_only' in o:o['whitebox_only']=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_repaired.blend'),compress=True)
manifest['final_sha256']=hashlib.sha256((OUT/'axel_guild_repaired.glb').read_bytes()).hexdigest()
(OUT/'repair_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('FINALIZED_LOD',len(manifest['lod_tagged_meshes']),flush=True)
