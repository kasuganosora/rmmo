"""Inspect user-provided model files without altering originals (Blender background)."""
import bpy
import json
import math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/character_3d/source_review'
OUT.mkdir(parents=True,exist_ok=True)
WORK=art_path('characters/source_models/inspected')
WORK.mkdir(parents=True,exist_ok=True)
SOURCES={
    'theresa':art_path('characters/source_models/theresa/Free test/Theresa - Free Test.glb'),
    'rose':art_path('characters/source_models/Rose FBX.fbx'),
    'artoria':art_path('characters/source_models/artoria/default.fbx'),
}
report={}
for name,path in SOURCES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix=='.glb':bpy.ops.import_scene.gltf(filepath=str(path))
    else:bpy.ops.import_scene.fbx(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    arms=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
    report[name]={
        'meshes':[{'name':o.name,'vertices':len(o.data.vertices),'faces':len(o.data.polygons),'materials':[m.name if m else None for m in o.data.materials], 'vertex_groups':[g.name for g in o.vertex_groups], 'shape_keys':list(o.data.shape_keys.key_blocks.keys()) if o.data.shape_keys else [], 'bounds':[list(o.matrix_world@Vector(p)) for p in o.bound_box]} for o in meshes],
        'rigs':[{'name':o.name,'bones':[{'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(o.matrix_world@b.head_local),'tail':list(o.matrix_world@b.tail_local)} for b in o.data.bones]} for o in arms],
        'images':[{'name':i.name,'size':list(i.size),'packed':bool(i.packed_file),'path':i.filepath} for i in bpy.data.images],
        'actions':[a.name for a in bpy.data.actions],
    }
    # Pack sources into a self-contained editable working copy.
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/(name+'.blend')))
    pts=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
    low=Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    center=(low+high)/2;size=max(high.z-low.z,high.x-low.x)
    scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Review background');scene.world.use_nodes=True
    background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
    background.inputs[0].default_value=(.17,.21,.24,1)
    background.inputs[1].default_value=.6
    scene.view_settings.view_transform='Standard'
    camera_data=bpy.data.cameras.new('Review camera');camera=bpy.data.objects.new('Review camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
    camera.location=center+Vector((0,-size*2.8,size*.08));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera_data.type='ORTHO';camera_data.ortho_scale=size*1.16
    for pos,power in [((-1,-2,3),1000),((2,-1,1),650)]:
        data=bpy.data.lights.new('Softbox','AREA');obj=bpy.data.objects.new('Softbox',data);scene.collection.objects.link(obj)
        obj.location=center+Vector(pos)*size;data.energy=power*size*size;data.shape='DISK';data.size=size*2
        obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    (OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('REVIEWED',name,flush=True)
