"""Review views from exported v7 source; does not modify game geometry."""
import bpy
from pathlib import Path
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v7')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'axel_guild_whitebox.blend'))
SC=bpy.context.scene;cam=SC.camera
for col in bpy.data.collections:
 if col.name.startswith(('70_','71_','80_')):col.hide_render=True
bpy.ops.object.light_add(type='AREA',location=(23.6,2.6,7.75));bpy.context.object.data.energy=150;bpy.context.object.data.size=2
cam.data.type='PERSP';cam.data.lens=21;cam.location=(24.63,1.53,6.55)
cam.rotation_euler=(Vector((23.25,3.1,5.25))-cam.location).to_track_quat('-Z','Y').to_euler()
SC.render.filepath=str(OUT/'12_guestroom.png');bpy.ops.render.render(write_still=True)
for col in bpy.data.collections:
 if col.name.startswith(('50_','51_','33_','11_','12_','44_')):col.hide_render=True
cam.data.type='ORTHO';cam.data.ortho_scale=16;cam.location=(26.6,6.4,42)
cam.rotation_euler=(Vector((26.6,6.4,4.48))-cam.location).to_track_quat('-Z','Y').to_euler()
SC.render.filepath=str(OUT/'13_guestrooms_top.png');bpy.ops.render.render(write_still=True)
