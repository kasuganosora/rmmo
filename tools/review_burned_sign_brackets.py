"""Close views of corrected independent sign brackets, offline review only."""
import bpy,json
from pathlib import Path
from mathutils import Vector
p=Path('D:/code/rmmo_runtime/art_sources/mmorpg_shop_signs/burned_brackets_v3_20261007')
bpy.ops.wm.open_mainfile(filepath=str(p/'shop_signs_optimized.blend'))
s=bpy.context.scene
for o in s.objects:
 if o.type in {'MESH','CURVE'}:
  o.hide_render=not (-.01<=o.location.x<=3.71 and abs(o.location.z)<.01)
s.render.resolution_x=1500;s.render.resolution_y=700
s.cycles.samples=48
cam=s.camera;cam.data.ortho_scale=5.8
for name,pos in [('brackets_front',(1.6,-12,.5)),('brackets_oblique',(-1.0,-11,2.8))]:
 cam.location=pos;cam.rotation_euler=(Vector((1.6,0,.45))-cam.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(p/(name+'.png'));bpy.ops.render.render(write_still=True)
