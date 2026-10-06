"""Same-camera side silhouette check; original and candidate share the studio."""
import bpy,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');ART=ROOT/'art_sources/bridge_street_kit/baltic_pine_procedural';OUT=ROOT/'review_artifacts/pine_dense_v3'
bpy.ops.wm.open_mainfile(filepath=str(ART/'baltic_pine_dense_v3.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;sc.cycles.transparent_max_bounces=128
sc.cycles.samples=24;sc.render.resolution_x=800;sc.render.resolution_y=800
cam=sc.camera;cam.location=(-20,10,10);cam.rotation_euler=(Vector((0,0,5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=12.8
name='master_side'
if '--candidate' in sys.argv:
 bpy.data.objects['BALTIC PINE | editable parameters'].hide_render=True
 bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/baltic_pine_dense_v3_fine/pine_dense_mature.glb'));name='fine_side'
sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('SIDE_REVIEW_READY',name,flush=True)
