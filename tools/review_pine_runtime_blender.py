"""Compare exported layered foliage with approved authoring under the same studio."""
import bpy,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');ART=ROOT/'art_sources/bridge_street_kit/baltic_pine_procedural';OUT=ROOT/'review_artifacts/pine_dense_v3';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ART/'baltic_pine_dense_v3.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
sc.cycles.transparent_max_bounces=128
bpy.data.objects['BALTIC PINE | editable parameters'].hide_render=True
before=set(bpy.data.objects)
folder='baltic_pine_dense_v3_fine' if '--fine-clusters' in sys.argv else 'baltic_pine_dense_v3'
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets'/folder/'pine_dense_mature.glb'))
imported=set(bpy.data.objects)-before
suffix='_translucent' if '--translucency' in sys.argv else ''
if '--fine-clusters' in sys.argv:suffix+='_fine'
for arg in sys.argv:
 if arg.startswith('--cutoff='):
  cutoff=float(arg.split('=')[1]);suffix+='_cut'+str(cutoff).replace('.','')
  for mat in bpy.data.materials:
   if 'needle_volume' in mat.name and mat.use_nodes:
    for node in mat.node_tree.nodes:
     if node.type=='MATH' and node.operation=='LESS_THAN':node.inputs[1].default_value=cutoff
if '--translucency' in sys.argv:
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
sc.render.filepath=str(OUT/('runtime_same_camera'+suffix+'.png'));bpy.ops.render.render(write_still=True)
cam=sc.camera;cam.location=(6,-10,8);cam.rotation_euler=(Vector((.6,-.2,8.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.5
sc.render.filepath=str(OUT/('runtime_needle_compare'+suffix+'.png'));bpy.ops.render.render(write_still=True)
for obj in imported:obj.hide_render=True
bpy.data.objects['BALTIC PINE | editable parameters'].hide_render=False
if not (OUT/'master_needle_compare.png').exists():
 sc.render.filepath=str(OUT/'master_needle_compare.png');bpy.ops.render.render(write_still=True)
print('RUNTIME_COMPARE_RENDERED',flush=True)
