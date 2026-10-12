"""Repair the accepted guild master and publish versioned, matching prop sources.

No accepted master or user map is overwritten. Unseen joinery is project design.
"""
import bpy,json,struct,hashlib,sys,math
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).parent))
from axel_guild_window_repair import repair
from compact_axel_guild import compact
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension')
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2')
OUT.mkdir(exist_ok=True);(OUT/'library').mkdir(exist_ok=True)
source=BASE/'axel_guild_entry.blend';before=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
report={'window_repairs':repair(),'source':str(source),'source_sha256':before,'project_design':['storage cabinet hinges and internal shelf','clear upper-floor glazing']}

def parent_world(obj,parent):
    world=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=world

def cube(name,loc,scale,parent,mat,group='static'):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o=bpy.context.object;o.name=name;o.parent=parent;o.location=loc;o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat);o['semantic_group']=parent.get('semantic_group','')
    o['replaceable_group']=group;o['collision_review']=True
    return o

# Existing paired panels are already separate material groups: preserve their
# accepted shape and place the origin on the real hinge, including the handle.
storage=[o for o in bpy.data.objects if o.get('asset_id')=='guild_storage_cabinet']
for r in storage:
    wood=next(m for o in r.children if o.type=='MESH' for m in o.data.materials if 'timber' in m.name.lower())
    iron=next(m for m in bpy.data.materials if m.name.startswith('Guild forged dark iron'))
    for side,group in [(-1,'left_door'),(1,'right_door')]:
        pivot=Vector((side*.515,-.211,0))
        for o in list(r.children):
            if o.get('replaceable_group')!=group:continue
            o.data=o.data.copy();o.data.transform(Matrix.Translation(-pivot)@o.matrix_basis)
            o.matrix_basis=Matrix.Translation(pivot)
            o['door_group']=group;o['open_angle_degrees']=95*side
            o['hinge_pivot_local']=list(pivot);o['hinge_axis_local']=[0,0,1]
        for z in [.34,1.44]:
            for moving in [False,True]:
                x=side*.49 if not moving else side*.43
                h=cube(r.name+' hinge strap',(x,-.223,z),(.085,.014,.032),r,iron,group if moving else 'static')
                if moving:
                    h.data.transform(Matrix.Translation(-pivot)@h.matrix_basis);h.matrix_basis=Matrix.Translation(pivot)
                    h['door_group']=group;h['open_angle_degrees']=95*side
            bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.012,depth=.074)
            pin=bpy.context.object;pin.name=r.name+' hinge pin';pin.parent=r;pin.location=(side*.515,-.223,z);pin.data.materials.append(iron)
            pin['semantic_group']=r['semantic_group'];pin['collision_review']=False
    cube(r.name+' interior shelf',(0,.005,.89),(.95,.31,.025),r,wood)
    r['project_design']='functional paired hinges and shelf';r['door_opening_degrees']=95
    r['door_animation_implemented']=False # Runtime uses the validated hinge contract, not authored clips.

# One complete reusable facade assembly: cloth, loops, all wall plates and stays.
heraldry=bpy.data.objects['Guild facade heraldry assembly']
for o in list(bpy.data.objects):
    if o.get('finish_component') in ['guild_banner_cloth','guild_banner_brackets','guild_banner_loops']:
        parent_world(o,heraldry)

# Actual thin glazing at the repaired four windows (opaque clay was never glass).
glass=bpy.data.materials.new('Guild clear upper window glass');glass.use_nodes=True
p=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(.70,.83,.85,.20)
p.inputs['Metallic'].default_value=0;p.inputs['Roughness'].default_value=.12
p.inputs['Alpha'].default_value=.20;p.inputs['IOR'].default_value=1.45
glass.surface_render_method='DITHERED'
parent=bpy.data.objects['11_Exterior_Upper']
for y in [3.5,6.5,10.6]:
    o=cube('Clear east upper glazing',(31.76,y,6.38),(.008,1.08,1.78),parent,glass)
    o['rmmo_collision']='none';o['collision_review']=False
o=cube('Clear washroom rear glazing',(29.5,13.76,6.38),(1.08,.008,1.78),parent,glass)
o['rmmo_collision']='none';o['collision_review']=False

roots=[o for o in bpy.data.objects if o.get('asset_id') and not o.get('semantic_group','').startswith(('60_','70_','71_','80_','90_'))]
for r in roots:
    r['asset_version']=2;r['asset_source']='library/'+r['asset_id']+'.glb'
    for o in [r]+list(r.children_recursive):
        o['whitebox_only']=False;o['delivery_stage']='textured_repair_v2'
        if o.get('door_group'):
            o['rmmo_hinge']=dict(id=o['door_group'],angle=float(o['open_angle_degrees']),open=0.0)
        if o.type=='MESH' and o.get('collision_review') is False:o['rmmo_collision']='none'
    # An explicit, axis-converted socket; its effect is runtime derived.
    socket=r.get('light_socket_local',r.get('light_socket_blender'))
    if socket is not None:
        color=[1,.86,.69] if r['asset_id']=='guild_hall_lantern' else [1,.80,.50]
        r['rmmo_light_socket']={'position':[float(socket[0]),float(socket[2]),-float(socket[1])],'color':color,'range':5.5,'energy':.35 if r['asset_id']=='guild_hall_lantern' else .18,'flame':'candle' in r['asset_id'],'indoor':True}
        r['runtime_light_connected']=False # Set by runtime attachment, never claim from asset tags alone.

def gltf(path):
    b=path.read_bytes();n,k=struct.unpack_from('<II',b,12);return b,n,k,json.loads(b[20:20+n])
_,_,_,old=gltf(BASE/'axel_guild_entry.glb')
factors={m['name']:m.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]) for m in old['materials']}
def export(path,objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.hide_set(False);o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True,export_animations=False)
    b,n,k,j=gltf(path)
    for m in j['materials']:
        if m['name'] in factors:m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=factors[m['name']]
    payload=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4);binary=b[20+n:]
    path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),k)+payload+binary)

bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_repaired.blend'),compress=True)
objects=[o for o in bpy.data.objects if not o.get('semantic_group','').startswith(('60_','70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT')]
export(OUT/'axel_guild_repaired_raw.glb',objects)
compact(OUT/'axel_guild_repaired_raw.glb',OUT/'axel_guild_repaired.glb')
seen=set();manifest=[]
for r in roots:
    aid=r['asset_id']
    if aid in seen:continue
    seen.add(aid);original_parent=r.parent;original_matrix=r.matrix_basis.copy()
    r.parent=None;r.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    path=OUT/'library'/(aid+'.glb');export(path,[r]+list(r.children_recursive))
    if aid=='guild_facade_heraldry':
        from normalize_guild_heraldry_export import normalize
        normalize(path)
    manifest.append({'asset_id':aid,'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_master':str(OUT/'axel_guild_repaired.blend'),'hinge_members':sum(bool(c.get('rmmo_hinge')) for c in r.children_recursive)})
    r.parent=original_parent;r.matrix_basis=original_matrix
report.update(storage_cabinets=len(storage),library=manifest,source_unchanged=hashlib.sha256(source.read_bytes()).hexdigest()==before)
assert report['source_unchanged']
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_repaired.blend'))
assert all(bpy.data.objects[row['name']].get('window_lining_repaired') for row in report['window_repairs'])
report['saved_master_reopened']=True
(OUT/'repair_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('GUILD_REPAIR_COMPLETE',len(manifest),flush=True)
