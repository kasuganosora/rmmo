"""Prepare the user-supplied complete Artoria model for modular Godot equipment.

Preserves source geometry, UVs, weights and face shape keys; splits disconnected
outfit pieces into slots and fixes FBX materials. Does not modify the source FBX.
"""
import bpy,bmesh,json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=art_path('characters/imported/artoria')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(art_path('characters/source_models/artoria/default.fbx')))
for obj in bpy.context.scene.objects:
    obj.animation_data_clear()
    if obj.type=='ARMATURE':
        for pb in obj.pose.bones:pb.matrix_basis.identity()
    if obj.type=='MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:key.value=0

# Material conversion: preserve texture colours without the FBX's blown-out lights.
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    tree=mat.node_tree
    bsdf=next(n for n in tree.nodes if n.type=='BSDF_PRINCIPLED')
    link=next((l for l in tree.links if l.to_node==bsdf and l.to_socket.name=='Base Color'),None)
    image=link.from_node.image if link and link.from_node.type=='TEX_IMAGE' else None
    tree.nodes.clear()
    output=tree.nodes.new('ShaderNodeOutputMaterial')
    emission=tree.nodes.new('ShaderNodeEmission')
    tree.links.new(emission.outputs[0],output.inputs['Surface'])
    if image:
        tex=tree.nodes.new('ShaderNodeTexImage');tex.image=image
        tree.links.new(tex.outputs['Color'],emission.inputs['Color'])
    else:emission.inputs['Color'].default_value=(.8,.8,.8,1)
    mat.use_backface_culling=False

outfit=bpy.data.objects['outfits']
adj=[[] for v in outfit.data.vertices]
for e in outfit.data.edges:
    a,b=e.vertices;adj[a].append(b);adj[b].append(a)
unseen=set(range(len(adj)));groups={'Clothing1':set(),'Clothing2':set(),'HairAccessory':set()}
while unseen:
    todo=[unseen.pop()];component=set()
    while todo:
        v=todo.pop();component.add(v)
        for n in adj[v]:
            if n in unseen:unseen.remove(n);todo.append(n)
    pts=[outfit.matrix_world@outfit.data.vertices[v].co for v in component]
    category='Clothing2' if min(p.z for p in pts)<1 else ('HairAccessory' if min(p.y for p in pts)>.15 else 'Clothing1')
    groups[category].update(component)
for category,indices in groups.items():
    obj=outfit.copy();obj.data=outfit.data.copy();obj.name=category
    bpy.context.collection.objects.link(obj)
    bm=bmesh.new();bm.from_mesh(obj.data);bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in indices],context='VERTS')
    bm.to_mesh(obj.data);bm.free()
bpy.data.objects.remove(outfit,do_unlink=True)
bpy.data.objects['shoe'].name='Boots'

# The original stockings were painted on the skin. Give them a weighted overlay
# so removing footwear can expose bare legs without modifying the source bitmap.
body=bpy.data.objects['Body']
skin_image=next(n.image for n in body.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE')
pixels=list(skin_image.pixels);w,h=skin_image.size
uvs=body.data.uv_layers.active.data
stocking_faces=set()
for polygon in body.data.polygons:
    center=body.matrix_world@polygon.center
    if center.z>1.4:continue
    uv=sum((uvs[i].uv for i in polygon.loop_indices),Vector((0,0)))/len(polygon.loop_indices)
    x=min(w-1,max(0,int(uv.x*w)));y=min(h-1,max(0,int(uv.y*h)))
    rgb=pixels[(y*w+x)*4:(y*w+x)*4+3]
    if max(rgb)<.23:stocking_faces.add(polygon.index)
stockings=body.copy();stockings.data=body.data.copy();stockings.name='Stockings';bpy.context.collection.objects.link(stockings)
bm=bmesh.new();bm.from_mesh(stockings.data);bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in stocking_faces],context='FACES')
for v in bm.verts:v.co+=v.normal*.0008
bm.to_mesh(stockings.data);bm.free()

# Keep the complete skin; no deletion beneath gear.
# Store origin/author terms alongside this local derivative.
(OUT/'SOURCE.txt').write_text((art_path('characters/source_models/artoria/readme.txt')).read_text()+
    '\nLocal changes: material conversion, independent top/skirt/boots/stockings/hair accessory; '
    'all source skin faces, weights, UVs and expressions preserved. Source: user-provided artoria.zip/default.fbx.\n',encoding='utf-8')
bpy.ops.file.pack_all()
(OUT/'editable').mkdir(exist_ok=True)
(OUT/'editable'/'.gdignore').touch()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable/character.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'character.glb'),export_format='GLB',export_animations=False,export_yup=True)
print('MODULAR_ARTORIA_READY',flush=True)
