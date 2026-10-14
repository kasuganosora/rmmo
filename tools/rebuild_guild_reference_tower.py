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

manifest=json.loads((OUT/'repair_manifest.json').read_text(encoding='utf8'))
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
