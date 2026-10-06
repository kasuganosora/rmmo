"""Thicken the approved oak continuously into its rooted main branches."""
import bpy,sys,json
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,REVIEW,setval
bpy.ops.wm.open_mainfile(filepath=str(ART/'street_oak_game_reviewed.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
tree=bpy.data.objects['STREET OAK | editable parameters'];mod=tree.modifiers[0]
socket=next(s for s in mod.node_group.interface.items_tree if s.item_type=='SOCKET' and s.in_out=='INPUT' and s.name=='Trunk width')
socket.max_value=8.
old=float(mod.get(socket.identifier,socket.default_value))
def add_girth():
 ng=bpy.data.node_groups.new('Oak | local trunk girth','GeometryNodeTree')
 ng.interface.new_socket(name='Geometry',in_out='INPUT',socket_type='NodeSocketGeometry')
 s=ng.interface.new_socket(name='Girth multiplier',in_out='INPUT',socket_type='NodeSocketFloat');s.default_value=2.3;s.min_value=1.;s.max_value=3.5
 ng.interface.new_socket(name='Geometry',in_out='OUTPUT',socket_type='NodeSocketGeometry')
 ns=ng.nodes;ls=ng.links;gi=ns.new('NodeGroupInput');go=ns.new('NodeGroupOutput');pos=ns.new('GeometryNodeInputPosition');sep=ns.new('ShaderNodeSeparateXYZ');ls.new(pos.outputs[0],sep.inputs[0])
 def math(op,a,b):
  n=ns.new('ShaderNodeMath');n.operation=op
  for i,v in enumerate([a,b]):
   if isinstance(v,(int,float)):n.inputs[i].default_value=v
   else:ls.new(v,n.inputs[i])
  return n.outputs[0]
 def fade(value,lo,hi):
  n=ns.new('ShaderNodeMapRange');n.interpolation_type='SMOOTHSTEP';ls.new(value,n.inputs['Value']);n.inputs['From Min'].default_value=lo;n.inputs['From Max'].default_value=hi;n.inputs['To Min'].default_value=1.;n.inputs['To Max'].default_value=0.;return n.outputs[0]
 radius=math('SQRT',math('ADD',math('MULTIPLY',sep.outputs['X'],sep.outputs['X']),math('MULTIPLY',sep.outputs['Y'],sep.outputs['Y'])),0.)
 amount=math('MULTIPLY',math('SUBTRACT',gi.outputs['Girth multiplier'],1.),math('MULTIPLY',fade(sep.outputs['Z'],1.6,4.8),fade(radius,.6,1.8)))
 offset=ns.new('ShaderNodeCombineXYZ');ls.new(math('MULTIPLY',sep.outputs['X'],amount),offset.inputs['X']);ls.new(math('MULTIPLY',sep.outputs['Y'],amount),offset.inputs['Y'])
 split=ns.new('GeometryNodeSeparateComponents');ls.new(gi.outputs['Geometry'],split.inputs['Geometry'])
 deform=ns.new('GeometryNodeSetPosition');ls.new(split.outputs['Mesh'],deform.inputs['Geometry']);ls.new(offset.outputs[0],deform.inputs['Offset'])
 move=ns.new('GeometryNodeTranslateInstances');move.inputs['Local Space'].default_value=False;ls.new(split.outputs['Instances'],move.inputs['Instances']);ls.new(offset.outputs[0],move.inputs['Translation'])
 join=ns.new('GeometryNodeJoinGeometry');ls.new(deform.outputs[0],join.inputs[0]);ls.new(move.outputs[0],join.inputs[0]);ls.new(join.outputs[0],go.inputs['Geometry'])
 m=tree.modifiers.new('Local trunk girth | preserve crown','NODES');m.node_group=ng
setval(tree,'Optimized',True);setval(tree,'Wind (m)',0.)
sc.cycles.samples=20;sc.render.resolution_x=sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.view_settings.exposure=.5
sun=bpy.data.objects['REVIEW | fixed sun'];sun.rotation_euler=(.45,-.5,-.5);cam=sc.camera
rows=[]
for label,width in [('before',old),('thick',old)]:
 if label=='thick':add_girth()
 setval(tree,'Trunk width',width);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 points=[v.co for v in tree.evaluated_get(dg).data.vertices if 1.2<v.co.z<1.4]
 rows.append({'version':label,'trunk_width_control':width,'diameter_x_at_1_3m':max(v.x for v in points)-min(v.x for v in points),'diameter_y_at_1_3m':max(v.y for v in points)-min(v.y for v in points),'twig_instances':sum(1 for i in dg.object_instances if i.is_instance)})
 for view,pos,target,scale in [('full',(14,-20,11),(0,0,4.2),11.8),('trunk',(5,-8,4),(0,0,1.8),4.3)]:
  if label=='before' and (REVIEW/(label+'_'+view+'_trunk_revision.png')).exists():continue
  cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
  sc.render.filepath=str(REVIEW/(label+'_'+view+'_trunk_revision.png'));bpy.ops.render.render(write_still=True)
# Keep the approved wider trunk active in both the single-tree and river preset.
other=bpy.data.objects['03 Riverside | leaning'];m=other.modifiers.new('Local trunk girth | preserve crown','NODES');m.node_group=tree.modifiers[-1].node_group
cam.location=(14,-20,11);cam.rotation_euler=(Vector((0,0,4.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=11.8
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_thick_trunk.blend'),compress=True)
(REVIEW/'trunk_revision.json').write_text(json.dumps({'measurements':rows,'method':'Shared continuous trunk-to-crown width field; twig roots follow same deformation; crown spread and height unchanged','original_preserved':True},indent=2),encoding='utf-8')
print('OAK_THICK_TRUNK_READY',rows,flush=True)
