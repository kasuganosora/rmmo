"""Material-only revision of the reviewed interior, retaining v2 for comparison."""
import copy
import hashlib
import json
import struct
import sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from axel_guild_lantern_finish import FINISHES, apply_lantern_finish

OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_materials_20261011')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_materials_v2.blend'))
roots=[o for o in bpy.data.objects if o.get('asset_source','').endswith('/guild_hall_lantern.glb')]
assert len(roots)==6
def fingerprint():
    h=hashlib.sha256()
    for o in sorted(bpy.data.objects,key=lambda o:o.name):
        h.update(repr((o.name,o.parent.name if o.parent else '',[list(r) for r in o.matrix_world])).encode())
        if o.type=='MESH':
            h.update(repr([tuple(v.co) for v in o.data.vertices]).encode())
            h.update(repr([tuple(p.vertices) for p in o.data.polygons]).encode())
    return h.hexdigest()
before=fingerprint()
changed=[]
for root in roots:changed.extend(apply_lantern_finish(root.children_recursive))
assert len(changed)==2,changed  # Two material slots on meshes shared by all six lamps.
assert fingerprint()==before
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'axel_guild_materials_v3.blend'),compress=True)

# Change glTF material bindings only; preserve ALL vertex/UV/image buffers exactly.
data=(OUT/'axel_guild_materials_v2.glb').read_bytes()
size,kind=struct.unpack_from('<II',data,12)
doc=json.loads(data[20:20+size]);original=copy.deepcopy(doc);binary=data[20+size:]
material_ids={}
for old,(name,color,roughness) in FINISHES.items():
    material_ids[old]=len(doc['materials'])
    doc['materials'].append({'name':name,'pbrMetallicRoughness':{'baseColorFactor':[*color,1],
                           'metallicFactor':.15,'roughnessFactor':roughness},
                           'extensions':{'KHR_materials_clearcoat':{'clearcoatFactor':.18,'clearcoatRoughnessFactor':.30}}})
if 'KHR_materials_clearcoat' not in doc.setdefault('extensionsUsed',[]):doc['extensionsUsed'].append('KHR_materials_clearcoat')
root_ids=[i for i,n in enumerate(doc['nodes']) if n.get('extras',{}).get('asset_source','').endswith('/guild_hall_lantern.glb')]
assert len(root_ids)==6
meshes=set()
def collect(i):
    n=doc['nodes'][i]
    if 'mesh' in n:meshes.add(n['mesh'])
    for child in n.get('children',[]):collect(child)
for i in root_ids:collect(i)
bindings=[]
for i in meshes:
    for j,p in enumerate(doc['meshes'][i]['primitives']):
        matname=doc['materials'][p['material']]['name']
        match=next((k for k in FINISHES if matname==k or matname.startswith(k+'.')),None)
        if match:
            bindings.append([i,j,p['material'],material_ids[match]])
            p['material']=material_ids[match]
assert len(bindings)==2,bindings
comparison=copy.deepcopy(doc)
comparison['materials']=original['materials']
if 'extensionsUsed' in original:comparison['extensionsUsed']=original['extensionsUsed']
else:comparison.pop('extensionsUsed',None)
for i,j,old,new in bindings:comparison['meshes'][i]['primitives'][j]['material']=old
assert comparison==original,'Unexpected non-material GLB change'
payload=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
path=OUT/'axel_guild_materials_v3.glb'
path.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),kind)+payload+binary)
assert path.read_bytes()[20+len(payload):]==binary
report={'instances':6,'blender_changed_slots':changed,'glb_bindings':bindings,
        'geometry_unchanged':True,'other_materials_unchanged':True,'binary_unchanged':True,
        'finish':FINISHES,'metallic':.15,'coat':.18,'coat_roughness':.30,
        'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'published_to_editor':False,'user_map_modified':False}
(OUT/'lantern_black_finish_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')

SC=bpy.context.scene
SC.render.engine='CYCLES';SC.cycles.samples=24;SC.cycles.use_denoising=True
SC.render.resolution_x=1400;SC.render.resolution_y=900;SC.render.resolution_percentage=100
SC.render.image_settings.file_format='PNG';SC.view_settings.view_transform='AgX'
for c in bpy.data.collections:c.hide_render=c.name.startswith(('60_','70_','71_','80_'))
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=False
cam=SC.camera;cam.location=(29,2.3,1.7)
cam.rotation_euler=(Vector((7,8,3.8))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='PERSP';cam.data.lens=23
SC.render.filepath=str(OUT/'interior_hall_black_lanterns.png')
bpy.ops.render.render(write_still=True)
print('LANTERN_BLACK_FINISH_DONE',flush=True)
