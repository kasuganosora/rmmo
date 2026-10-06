"""Blender GLB round-trip check and fixed-camera preview, offline only."""
import bpy,json,struct,hashlib
from pathlib import Path
from mathutils import Vector
out=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/street_edge_stones'
data=json.loads((out/'manifest.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(out/'street_edge_stones_optimized.blend'))
for o in list(bpy.context.scene.objects):
    if o.type=='MESH' and o.name!='Review ground':bpy.data.objects.remove(o,do_unlink=True)
checks=[]
for i,asset in enumerate(data['assets']):
    path=out/'models'/(asset['id']+'.glb');raw=path.read_bytes();length,kind=struct.unpack_from('<II',raw,12);gltf=json.loads(raw[20:20+length])
    assert len(gltf['meshes'])==1
    primitives=gltf['meshes'][0]['primitives'];assert all('NORMAL' in v['attributes'] and 'TEXCOORD_0' in v['attributes'] for v in primitives)
    mat=gltf['materials'][0];assert 'normalTexture' in mat and 'baseColorTexture' in mat['pbrMetallicRoughness'] and 'metallicRoughnessTexture' in mat['pbrMetallicRoughness']
    bpy.ops.import_scene.gltf(filepath=str(path));objs=[o for o in bpy.context.selected_objects if o.type=='MESH'];assert len(objs)==1
    ob=objs[0];ob.data.calc_loop_triangles();assert len(ob.data.loop_triangles)==asset['game_triangles']
    if i<3:offset=(-3,i*.65,0)
    elif i<5:offset=(-3,2.15 if i==3 else 3.1,0)
    elif i<10:offset=(1.15+((i-5)%2)*1.3,((i-5)//2)*1.1,0)
    else:offset=(4,0,0)
    # Import axis converted by Blender; transforms remain intact.
    ob.location+=Vector(offset)
    assert all(v.co.length<40 for v in ob.data.vertices)
    checks.append(dict(id=asset['id'],triangles=asset['game_triangles'],pbr_channels=True,sha256=hashlib.sha256(raw).hexdigest()))
sc=bpy.context.scene;sc.render.filepath=str(out/'glb_roundtrip.png');bpy.ops.render.render(write_still=True)
(out/'validation.json').write_text(json.dumps(dict(failures=0,scope='Blender GLB roundtrip; not editor or collision acceptance',assets=checks),indent=2))
print('STREET_STONES_VALIDATED',len(checks))
