"""Supplementary v8 hall view; reloads the delivered blend without re-exporting."""
from pathlib import Path
import bpy
from mathutils import Vector

out=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild/whitebox_v8'
bpy.ops.wm.open_mainfile(filepath=str(out/'axel_guild_whitebox.blend'))
scene=bpy.context.scene
for col in bpy.data.collections:
    if col.name.startswith(('70_','71_','80_')):col.hide_render=True
cam=scene.camera
cam.location=(16,1.8,4.5)
cam.rotation_euler=(Vector((16,7.5,7.5))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='PERSP';cam.data.lens=18
scene.render.filepath=str(out/'15_hall_geometry.png')
bpy.ops.render.render(write_still=True)
