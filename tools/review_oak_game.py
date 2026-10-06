"""Restore thin-leaf transmission and review under identical master lighting."""
import bpy,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,OUT,render,setval
bpy.ops.wm.open_mainfile(filepath=str(ART/'street_oak_game.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
for image in list(bpy.data.images):
 if '_cluster_' in image.name:
  kind='normal' if '_normal' in image.name else 'color'
  stem=image.name.split('_cluster_')[0]
  file=OUT/(stem+'_cluster_'+kind+'.png')
  if file.exists():
   fresh=bpy.data.images.load(str(file),check_existing=False)
   if kind=='normal':fresh.colorspace_settings.name='Non-Color'
   fresh.pack()
   for mat in bpy.data.materials:
    if mat.use_nodes:
     for n in mat.node_tree.nodes:
      if n.type=='TEX_IMAGE' and n.image==image:n.image=fresh
for scene in bpy.data.scenes:
 if scene.render.engine=='CYCLES':scene.cycles.transparent_max_bounces=128
for mat in bpy.data.materials:
 if 'needle_volume' not in mat.name or not mat.use_nodes:continue
 nt=mat.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
 for normal in nt.nodes:
  if normal.type=='NORMAL_MAP':normal.inputs['Strength'].default_value=.25
 color=p.inputs['Base Color'].links[0].from_socket;alpha=p.inputs['Alpha'].links[0].from_socket
 for link in list(p.inputs['Alpha'].links):nt.links.remove(link)
 p.inputs['Alpha'].default_value=1.;p.inputs['Subsurface Weight'].default_value=.045;p.inputs['Subsurface Radius'].default_value=(.3,.65,.15)
 trans=nt.nodes.new('ShaderNodeBsdfTranslucent');nt.links.new(color,trans.inputs['Color'])
 if p.inputs['Normal'].is_linked:nt.links.new(p.inputs['Normal'].links[0].from_socket,trans.inputs['Normal'])
 mix=nt.nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=.14;nt.links.new(p.outputs[0],mix.inputs[1]);nt.links.new(trans.outputs[0],mix.inputs[2])
 clear=nt.nodes.new('ShaderNodeBsdfTransparent');coverage=nt.nodes.new('ShaderNodeMixShader');nt.links.new(alpha,coverage.inputs[0]);nt.links.new(clear.outputs[0],coverage.inputs[1]);nt.links.new(mix.outputs[0],coverage.inputs[2]);nt.links.new(coverage.outputs[0],out.inputs['Surface'])
tree=bpy.data.objects['STREET OAK | editable parameters'];setval(tree,'Optimized',True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_game_reviewed.blend'),compress=True)
render(sc,sc.camera,bpy.data.objects['REVIEW | fixed sun'],tree)
print('OAK_MATERIAL_REVIEW_COMPLETE',flush=True)
