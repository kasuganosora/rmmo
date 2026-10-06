"""Blender background: retain approved master near camera, reduced cards beyond 20m."""
import bpy,json,struct,hashlib
from pathlib import Path
from mathutils import Vector
BASE=Path('D:/code/rmmo_runtime/art_sources/street_shrub_mounds');OUT=BASE/'game_lod';OUT.mkdir(exist_ok=True)
manifest=json.loads((BASE/'manifest.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(BASE/'shrub_master.blend'))
with bpy.data.libraries.load(str(BASE/'shrub_optimized.blend'),link=False) as (source,destination):
    destination.objects=[n for n in source.objects if '_foliage' in n]
low=destination.objects
for o in low:bpy.context.scene.collection.objects.link(o)
rows=[]
for spec in manifest['assets']:
    name=spec['id'];near=next(o for o in bpy.context.scene.objects if o not in low and o.name.startswith(name+'_foliage'))
    far=next(o for o in low if o.name.startswith(name+'_foliage'));stem=next(o for o in bpy.context.scene.objects if o.name==name+'_stems')
    far.data.materials.clear();far.data.materials.append(near.data.materials[0])
    lo=Vector(tuple(min(v.co[k] for v in near.data.vertices) for k in range(3)));hi=Vector(tuple(max(v.co[k] for v in near.data.vertices) for k in range(3)))
    bounds=[lo.x-.1,0,-hi.y-.1,hi.x-lo.x+.2,hi.z+.1,hi.y-lo.y+.2]
    near['rmmo_visibility_range']={'begin':0.,'end':20.,'bounds':bounds};far['rmmo_visibility_range']={'begin':20.,'end':0.,'bounds':bounds}
    near.name=name+'_LOD0';far.name=name+'_LOD1'
    bpy.ops.object.select_all(action='DESELECT')
    for o in [near,far,stem]:o.location=(0,0,0);o.select_set(True)
    file=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True)
    b=file.read_bytes();n=struct.unpack_from('<I',b,12)[0];g=json.loads(b[20:20+n]);tail=b[20+n:]
    for m in g['materials']:
        if 'boxwood' in m.get('name','').lower():m['alphaMode']='MASK';m['alphaCutoff']=.45;m['doubleSided']=True
    text=json.dumps(g,separators=(',',':')).encode();text+=b' '*((-len(text))%4);file.write_bytes(struct.pack('<III',0x46546c67,2,20+len(text)+len(tail))+struct.pack('<II',len(text),0x4e4f534a)+text+tail)
    rows.append(dict(id=name,near_triangles=spec['master_triangles'],far_triangles=spec['game_triangles'],switch_metres=20,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),bounds=bounds))
    for o in [near,far,stem]:o.location=spec['preview']
    far.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'street_shrubs_lod.blend'),compress=True)
(OUT/'manifest.json').write_text(json.dumps(dict(status='ready for native review',assets=rows),indent=2))
print('SHRUB_LOD_PACKAGED')
