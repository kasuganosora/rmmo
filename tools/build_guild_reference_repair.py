"""Versioned reference repair; never overwrite repair_v2 or a user content library."""
import bpy,json,hashlib,struct,sys,shutil,math
from pathlib import Path
from mathutils import Matrix,Vector
sys.path.insert(0,str(Path(__file__).parent))
from compact_axel_guild import compact
from axel_guild_reference_exterior import apply as exterior,apply_tower
from axel_guild_reference_props import apply as props
from axel_guild_reference_exterior_materials import apply as exterior_materials
from axel_guild_reference_materials import apply as interior_materials
from axel_guild_reference_masonry import apply as masonry

BASE=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2')
OUT=BASE.parent/'repair_v3'
OUT.mkdir(exist_ok=True);(OUT/'library').mkdir(exist_ok=True)
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    b=p.read_bytes();n,k=struct.unpack_from('<II',b,12);return b,n,k,json.loads(b[20:20+n])
sources={str(p):digest(p) for p in [BASE/'axel_guild_repaired.blend',BASE/'axel_guild_repaired.glb',BASE/'guild_alarm_tower.glb']}
manifest=json.loads((BASE/'repair_manifest.json').read_text(encoding='utf8'))
old=read(BASE/'axel_guild_repaired.glb')[3]
factors={m['name']:m.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]) for m in old['materials']}

def export(path,objects,mat_factors):
    # Blender's operator skips hidden selected objects in a loaded master.
    # Explicitly clear the whole data selection before choosing the delivery set.
    for o in bpy.context.scene.objects:o.select_set(False)
    for o in objects:o.hide_set(False);o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_extras=True,export_apply=True,export_animations=False)
    b,n,k,j=read(path)
    for m in j.get('materials',[]):
        if m['name'] in mat_factors:m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=mat_factors[m['name']]
        source_material=bpy.data.materials.get(m['name'])
        if source_material and source_material.get('reference_material_revision') and source_material.use_nodes:
            p=next(n for n in source_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
            links=p.inputs['Base Color'].links
            if links and links[0].from_node.type=='MIX_RGB':
                multiply=links[0].from_node
                assert multiply.blend_type=='MULTIPLY' and multiply.inputs[0].default_value==1
                assert not multiply.inputs[2].is_linked
                m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=list(multiply.inputs[2].default_value[:3])+[p.inputs['Alpha'].default_value]
    encoded=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);binary=b[20+n:]
    path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(encoded)+len(binary),len(encoded),k)+encoded+binary)

bpy.ops.wm.open_mainfile(filepath=str(BASE/'axel_guild_repaired.blend'))
fixes={'exterior':exterior(),'props':props()}
# The repaired dormer roof solids inherited tile material on their interior faces.
# Match the existing main roof's timber underside; external faces/UVs are unchanged.
oak=bpy.data.materials['Guild PBR | structural oak'];undersides=[]
for o in bpy.data.objects:
    if not(o.type=='MESH' and o.name.startswith('Guild finish roof_join_') and o.name.endswith('_solid')):continue
    o.data=o.data.copy();o.data.materials.append(oak);index=len(o.data.materials)-1;count=0
    normal_matrix=o.matrix_world.to_3x3().inverted().transposed()
    for face in o.data.polygons:
        normal=(normal_matrix@face.normal).normalized()
        if normal.z<-.2:face.material_index=index;count+=1
    if count:undersides.append({'name':o.name,'interior_faces':count});o['reference_revision']='20261013';o['project_design']='Timber inner roof sheathing, matching the established main roof underside'
fixes['dormer_inner_sheathing']=undersides

# Four label plates are visible above the U16 registration windows. Mark shapes
# are authored identifiers rather than an asserted transcription of fantasy text.
from axel_guild_reference_props import _box
parent=bpy.data.objects['40_Reception_L0']
stone=bpy.data.materials['Guild PBR | cut limestone trim']
iron=next(m for m in bpy.data.materials if m.name.startswith('Guild forged dark iron'))
signs=[]
for index,x in enumerate([22.8,24.65,26.5,28.35]):
    for name,y,size,mat in [('frame',10.68,(.97,.065,.34),iron),('insert',10.638,(.85,.028,.24),stone)]:
        o=_box(parent,f'Reception identifier {index+1} {name}',(x,y,3.59),size,mat)
        o['replaceable_group']='registration_identifiers';o['reference_status']='U16 label plate; project-authored identifier marks';signs.append(o.name)
    # Four small raised marks; no font/texture dependency or copied source wording.
    for tick in range(index+1):
        xx=x+(tick-index*.5)*.095
        o=_box(parent,f'Reception identifier {index+1} mark {tick}',(xx,10.617,3.59),(.019,.012,.145),iron)
        o['replaceable_group']='registration_identifiers';o['reference_status']='Project supplemental four-counter identifiers'
fixes['registration_label_plates']=signs

fixes['exterior_materials']=exterior_materials()
fixes['interior_materials']=interior_materials()
fixes['masonry']=masonry()

changed={'guild_quest_board_filled','guild_registration_crystal','guild_guest_chair'}
changed.update(fixes['interior_materials']['changed_asset_ids'])
changed.update(fixes['masonry']['changed_asset_ids'])
changed.update(fixes['exterior_materials'].get('affected_asset_ids',[]))
for obj in bpy.data.objects:
    if obj.type!='MESH' or not any(m and (m.get('reference_material_revision')=='20261013' or m.get('reference_revision')=='20261013') for m in obj.data.materials):continue
    parent=obj
    while parent:
        if parent.get('asset_id'):changed.add(parent['asset_id'])
        parent=parent.parent
roots=[o for o in bpy.data.objects if o.get('asset_id') in changed]
for r in roots:
    for o in [r]+list(r.children_recursive):
        o['delivery_stage']='textured_repair_v2';o['reference_revision']='20261013';o['whitebox_only']=False
        if o.get('collision_review') is False:o['rmmo_collision']='none'
    r['asset_version']=3
bpy.context.view_layer.update()
master=OUT/'axel_guild_repaired.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
objects=[o for o in bpy.data.objects if not o.get('semantic_group','').startswith(('60_','70_','71_','80_','90_')) and o.type not in ('LIGHT','CAMERA','FONT')]
export(OUT/'axel_guild_repaired_raw.glb',objects,factors)
compact(OUT/'axel_guild_repaired_raw.glb',OUT/'axel_guild_repaired.glb')
for row in manifest['library']:
    aid=row['asset_id'];dest=OUT/'library'/(aid+'.glb')
    if aid in changed:
        r=next(o for o in roots if o['asset_id']==aid);parent=r.parent;pose=r.matrix_basis.copy()
        r.parent=None;r.matrix_basis=Matrix.Identity(4)
        if aid=='guild_quest_board_filled':
            r['placement_kind']='wall';r['wall_contact_point_blender']=[0,.34,2.0]
            r['origin_note']='Existing local origin retained; use wall_contact_point_blender for wall attachment'
        bpy.context.view_layer.update();export(dest,[r]+list(r.children_recursive),factors)
        r.parent=parent;r.matrix_basis=pose
    else:shutil.copyfile(BASE/'library'/(aid+'.glb'),dest)
    row.update(path=str(dest),sha256=digest(dest),source_master=str(master),reference_changed=aid in changed)
bpy.ops.wm.open_mainfile(filepath=str(master))
assert len([o for o in bpy.data.objects if o.name.startswith('Reception identifier')])==18
manifest.update(reference_revision='20261013',reference_fixes=fixes,source_rollback=str(BASE),final_sha256=digest(OUT/'axel_guild_repaired.glb'),source_master=str(master),saved_master_reopened=True)
(OUT/'repair_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False,default=str),encoding='utf8')

tower_master=Path('D:/code/rmmo/review_artifacts/alarm_tower_game_20261011/guild_alarm_tower_game.blend')
sources[str(tower_master)]=digest(tower_master)
bpy.ops.wm.open_mainfile(filepath=str(tower_master))
tower_fixes=apply_tower()
for o in list(bpy.data.objects):
    if o.type=='MESH' and 'lod_level' not in o:
        bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guild_alarm_tower.blend'),compress=True)
tower_old=read(BASE/'guild_alarm_tower.glb')[3]
tower_factors={m['name']:m.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]) for m in tower_old['materials']}
tower_objects=[o for o in bpy.context.scene.objects if o.type=='EMPTY' or (o.type=='MESH' and 'lod_level' in o)]
assert sum(o.type=='MESH' for o in tower_objects)==36
export(OUT/'guild_alarm_tower_raw.glb',tower_objects,tower_factors)
compact(OUT/'guild_alarm_tower_raw.glb',OUT/'guild_alarm_tower.glb',False)
tower_document=read(OUT/'guild_alarm_tower.glb')[3]
tower_mesh_nodes=[n for n in tower_document['nodes'] if 'mesh' in n]
assert len(tower_mesh_nodes)==36 and all('lod_level' in n.get('extras',{}) for n in tower_mesh_nodes)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'guild_alarm_tower.blend'))
manifest['tower']={'path':str(OUT/'guild_alarm_tower.glb'),'sha256':digest(OUT/'guild_alarm_tower.glb'),'source_master':str(OUT/'guild_alarm_tower.blend'),'fixes':tower_fixes,'saved_master_reopened':True}
manifest['immutable_sources']=[{'path':p,'sha256':sha,'unchanged':digest(Path(p))==sha} for p,sha in sources.items()]
assert all(r['unchanged'] for r in manifest['immutable_sources'])
(OUT/'repair_manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False,default=str),encoding='utf8')
print('REFERENCE_REPAIR_BUILT',manifest['final_sha256'],manifest['tower']['sha256'],flush=True)
