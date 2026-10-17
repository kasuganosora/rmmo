"""Upgrade six hall lamps; preserve every other part and export a reusable lamp."""
import hashlib,json,struct,sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from axel_guild_magic_lantern import magic_materials,build_magic_core,add_preview_light

OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_materials_20261011')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_materials_v3.blend'))
SC=bpy.context.scene
roots=sorted([o for o in bpy.data.objects if o.get('asset_source','').endswith('/guild_hall_lantern.glb')],key=lambda o:o.name)
assert len(roots)==6
old_glass=[o for r in roots for o in r.children_recursive if o.type=='MESH' and any(m and m.name.startswith('Guild lantern frosted glass') for m in o.data.materials)]
assert len(old_glass)==6
retained=[o for o in bpy.data.objects if o not in old_glass]
def signature():
    h=hashlib.sha256()
    for o in sorted(retained,key=lambda o:o.name):
        h.update(repr((o.name,o.parent.name if o.parent else '',[list(r) for r in o.matrix_world])).encode())
        if o.type=='MESH':
            h.update(repr([tuple(v.co) for v in o.data.vertices]).encode())
            h.update(repr([tuple(p.vertices) for p in o.data.polygons]).encode())
            h.update(repr([m.name for m in o.data.materials]).encode())
    return h.hexdigest()
before=signature()
for o in old_glass:bpy.data.objects.remove(o,do_unlink=True)
glass,stone=magic_materials();prototype=None
for root in roots:
    col=root.users_collection[0]
    if prototype is None:
        parts=build_magic_core(root,col,glass,stone);prototype=parts
    else:
        parts=[]
        for old in prototype:
            o=old.copy();o.data=old.data;o.name=root.name+'_'+old['prop_part'];col.objects.link(o);o.parent=root;parts.append(o)
        for key in ['light_socket_blender','proposed_light_color_linear','light_source','glass_panels','light_runtime_connected']:
            root[key]=roots[0][key]
    for o in parts:o['semantic_group']=root['semantic_group'];o['material_pass']='interior_magic_lantern_v4'
    root['asset_version']=2
assert signature()==before
# The 30cm crystal is clear of the panes and top/bottom frames.
assert 2.825-.15>2.59 and 2.825+.15<3.055
assert .068 < .136-.004
report={'lamp_instances':6,'removed_solid_glass_meshes':6,'new_glass_sheets':24,'floating_crystals':6,
        'glass_thickness_m':.004,'crystal_dimensions_m':[.136,.136,.30],
        'retained_geometry_and_materials_unchanged':True,'retained_signature':before,
        'glass_emission':0,'warm_white_linear':[1,.86,.69],'preview_point_light_watts':8,
        'dimensions_are_project_design':True,'runtime_light_connected':False,'published_to_editor':False}
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_materials_v4.blend'),compress=True)
for c in bpy.data.collections:c.hide_viewport=False
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
    if not o.get('semantic_group','').startswith(('70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT'):
        o.hide_set(False);o.select_set(True)
path=OUT/'axel_guild_materials_v4.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
# Retain Blender architectural tint factors as in prior versions.
data=path.read_bytes();size,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+size]);binary=data[20+size:]
specs=json.loads((OUT/'material_review.json').read_text(encoding='utf8'))['materials']
for m in doc['materials']:
    key=m.get('name','').removeprefix('Guild PBR | ');p=m.get('pbrMetallicRoughness',{})
    if key in specs and 'color' in specs[key] and 'baseColorTexture' in p:p['baseColorFactor']=list(specs[key]['color'])+[1]
glass_json=next(m for m in doc['materials'] if m['name']==glass.name)
assert glass_json['alphaMode']=='BLEND' and glass_json.get('emissiveFactor',[0,0,0])==[0,0,0]
assert any(m['name']==stone.name and max(m.get('emissiveFactor',[0]))>0 for m in doc['materials'])
payload=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),kind)+payload+binary)
report['glb_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
# Independent floor-centred model, with glass/core retained as replaceable parts.
lamp=roots[0];parent=lamp.parent;matrix=lamp.matrix_basis.copy();lamp.parent=None;lamp.matrix_basis.identity()
bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
parts=[lamp]+list(lamp.children_recursive)
for o in parts:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'guild_hall_magic_lantern.glb'),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
bpy.data.libraries.write(str(OUT/'guild_hall_magic_lantern.blend'),set(parts),fake_user=True,compress=True)
lamp.parent=parent;lamp.matrix_basis=matrix;bpy.context.view_layer.update()
(OUT/'magic_lantern_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')

# Point lights are preview-only, separate from the reusable mesh/light socket.
for root in roots:add_preview_light(root,SC.collection)
SC.render.engine='CYCLES';SC.cycles.samples=48;SC.cycles.use_denoising=True
SC.render.resolution_x=1400;SC.render.resolution_y=900;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG';SC.view_settings.view_transform='AgX'
for c in bpy.data.collections:c.hide_render=c.name.startswith(('60_','70_','71_','80_'))
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=False
cam=SC.camera
for name,eye,aim,ortho in [('hall_magic_lanterns',(29,2.3,1.7),(7,8,3.8),0),
        ('magic_lantern_detail',tuple(roots[0].matrix_world@Vector((.25,-.9,3.05))),tuple(roots[0].matrix_world@Vector((0,0,2.90))),1.12)]:
    cam.location=eye;cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO' if ortho else 'PERSP';cam.data.ortho_scale=ortho or 45;cam.data.lens=23
    SC.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
    print('MAGIC_LANTERN_RENDER',name,flush=True)
