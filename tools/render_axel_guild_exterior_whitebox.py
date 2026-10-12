"""Render exterior views from the delivered v10 blend without changing assets."""
from pathlib import Path
import bpy
from mathutils import Vector

out = Path(__file__).resolve().parents[2] / 'rmmo_runtime/art_sources/axel_guild/whitebox_v10'
bpy.ops.wm.open_mainfile(filepath=str(out / 'axel_guild_whitebox.blend'))
scene = bpy.context.scene
for col in bpy.data.collections:
    col.hide_render = col.name.startswith(('70_', '71_', '80_'))
    col.hide_viewport = col.hide_render
for obj in bpy.data.objects:
    if obj.name.startswith('Main door hinge') and obj.type=='EMPTY':obj.rotation_euler.z=0
    if obj.type=='LIGHT' and obj.data.type=='AREA' and obj.location.y>0:obj.hide_render=True
cam = scene.camera
for name, eye, target, scale in [
    ('01_exterior', (48, -43, 30), (16, 6, 6), 45),
    ('16_front_elevation', (16, -50, 7), (16, 6, 7), 38),
    ('17_rear_exterior',(-26,48,26),(16,7,6),45),
    ('18_entry_detail',(23,-15,8),(16,0,5),14),
    ('19_balcony_door',(20,-12,8),(16,0,5.8),9),
]:
    for obj in bpy.data.objects:
        if obj.get('banner_assembly',False):obj.hide_render=name=='19_balcony_door'
    cam.location = eye
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = scale
    scene.render.filepath = str(out / (name + '.png'))
    bpy.ops.render.render(write_still=True)
