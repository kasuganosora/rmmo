"""Supplementary lit whitebox review; no geometry/GLB or user map changes."""
from pathlib import Path
import bpy
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v6')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_whitebox.blend'))
sc=bpy.context.scene
bpy.ops.object.light_add(type='AREA',location=(29.6,11.1,7.70));lamp=bpy.context.object
lamp.name='Washroom review fill';lamp.data.energy=200;lamp.data.size=1.5
for c in list(lamp.users_collection):c.objects.unlink(lamp)
bpy.data.collections['90_Studio'].objects.link(lamp)
lamp['review_only']=True
cam=sc.camera;cam.location=(28.0,9.85,6.9)
cam.rotation_euler=(Vector((30,12,5.5))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='PERSP';cam.data.lens=24
sc.render.filepath=str(OUT/'11_washroom.png')
bpy.ops.render.render(write_still=True)
print('WASHROOM_REVIEW_RENDERED_WITH_TEMPORARY_FILL')
