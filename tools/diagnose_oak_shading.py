import bpy,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,REVIEW,setval
bpy.ops.wm.open_mainfile(filepath=str(ART/'street_oak_game_reviewed.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;setval(bpy.data.objects['STREET OAK | editable parameters'],'Optimized',True)
sc.cycles.samples=8;sc.cycles.transparent_max_bounces=256;sc.render.resolution_x=sc.render.resolution_y=650;sc.view_settings.exposure=.5
cam=sc.camera;cam.location=(6,-10,7);cam.rotation_euler=(Vector((1.8,-.2,6.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.5
for mode in ['flat','flip']:
 for mat in bpy.data.materials:
  if 'needle_volume' not in mat.name or not mat.use_nodes:continue
  nt=mat.node_tree;norm=next(n for n in nt.nodes if n.type=='NORMAL_MAP')
  norm.inputs['Strength'].default_value=0. if mode=='flat' else 1.
  if mode=='flip':
   consumers=[l.to_socket for l in list(norm.outputs[0].links)]
   geo=nt.nodes.new('ShaderNodeNewGeometry');scale=nt.nodes.new('ShaderNodeVectorMath');scale.operation='SCALE'
   math=nt.nodes.new('ShaderNodeMath');math.operation='MULTIPLY_ADD';math.inputs[1].default_value=-2.;math.inputs[2].default_value=1.;nt.links.new(geo.outputs['Backfacing'],math.inputs[0]);nt.links.new(math.outputs[0],scale.inputs['Scale']);nt.links.new(norm.outputs[0],scale.inputs[0])
   for socket in consumers:nt.links.new(scale.outputs[0],socket)
 sc.render.filepath=str(REVIEW/('diagnose_'+mode+'.png'));bpy.ops.render.render(write_still=True)
