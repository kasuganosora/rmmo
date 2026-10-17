"""Unobstructed close-up of the actual scene lamp, with review lighting."""
import sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from axel_guild_magic_lantern import add_preview_light
OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_materials_20261011')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_materials_v4.blend'))
sc=bpy.context.scene
roots=sorted([o for o in bpy.data.objects if o.get('asset_source','').endswith('/guild_hall_lantern.glb')],key=lambda o:o.name)
for root in roots:add_preview_light(root,sc.collection)
for c in bpy.data.collections:c.hide_render=c.name.startswith(('60_','70_','71_','80_'))
for o in bpy.data.objects:
    if o.type=='LIGHT' and o.data.type=='AREA' and o.location.y>0:o.hide_render=False
cam=sc.camera;root=roots[0]
cam.location=root.matrix_world@Vector((.25,-.9,3.05))
target=root.matrix_world@Vector((0,0,2.9))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO';cam.data.ortho_scale=1.12
sc.render.engine='CYCLES';sc.cycles.samples=48;sc.cycles.use_denoising=True
sc.render.resolution_x=1100;sc.render.resolution_y=1100;sc.render.resolution_percentage=100
sc.view_settings.view_transform='AgX';sc.render.image_settings.file_format='PNG'
sc.render.filepath=str(OUT/'magic_lantern_detail.png');bpy.ops.render.render(write_still=True)
