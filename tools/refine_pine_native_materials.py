"""Restore authored thin-leaf shading and continuous coverage in native Blender."""
import bpy,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');ART=ROOT/'art_sources/bridge_street_kit/baltic_pine_procedural';OUT=ROOT/'review_artifacts/pine_dense_v3'
fine='--fine-clusters' in sys.argv
if fine:OUT=ROOT/'review_artifacts/pine_dense_v3_fine';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ART/('baltic_pine_fine_clusters_runtime.blend' if fine else 'baltic_pine_small_clusters_runtime.blend')))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;sc.cycles.transparent_max_bounces=128
for mat in bpy.data.materials:
 if 'needle_volume' not in mat.name or not mat.use_nodes:continue
 nt=mat.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
 color=p.inputs['Base Color'].links[0].from_socket;alpha=p.inputs['Alpha'].links[0].from_socket
 for link in list(p.inputs['Alpha'].links):nt.links.remove(link)
 p.inputs['Alpha'].default_value=1.;p.inputs['Subsurface Weight'].default_value=.045;p.inputs['Subsurface Radius'].default_value=(.3,.65,.15)
 trans=nt.nodes.new('ShaderNodeBsdfTranslucent');nt.links.new(color,trans.inputs['Color'])
 if p.inputs['Normal'].is_linked:nt.links.new(p.inputs['Normal'].links[0].from_socket,trans.inputs['Normal'])
 mix=nt.nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=.14;nt.links.new(p.outputs[0],mix.inputs[1]);nt.links.new(trans.outputs[0],mix.inputs[2])
 clear=nt.nodes.new('ShaderNodeBsdfTransparent');coverage=nt.nodes.new('ShaderNodeMixShader');nt.links.new(alpha,coverage.inputs[0]);nt.links.new(clear.outputs[0],coverage.inputs[1]);nt.links.new(mix.outputs[0],coverage.inputs[2]);nt.links.new(coverage.outputs[0],out.inputs['Surface'])
matcount=sum('needle_volume' in m.name for m in bpy.data.materials)
assert matcount>=5
bpy.ops.wm.save_as_mainfile(filepath=str(ART/('baltic_pine_dense_cards_v5.blend' if fine else 'baltic_pine_dense_cards_v4.blend')),compress=True)
prefix='native_v5' if fine else 'native_v4'
sc.render.filepath=str(OUT/(prefix+'_full.png'));bpy.ops.render.render(write_still=True)
cam=sc.camera;cam.location=(6,-10,8);cam.rotation_euler=(Vector((.6,-.2,8.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.5
sc.render.filepath=str(OUT/(prefix+'_close.png'));bpy.ops.render.render(write_still=True)
print('NATIVE_V4_MATERIAL_RESTORED',flush=True)
