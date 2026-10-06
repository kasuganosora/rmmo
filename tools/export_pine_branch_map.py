"""Read native V6 branch instances without changing the Blender master."""
import bpy, sys, json
import numpy as np
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from build_blender_parametric_pine import setval
ROOT=Path('D:/code/rmmo_runtime')
OUT=ROOT/'assets/pine_parametric';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_game_v6.blend'))
bpy.context.window.scene=bpy.data.scenes['Scene']
tree=bpy.data.objects['BALTIC PINE | editable parameters']
presets=bpy.data.scenes['PRESETS | compact - mature - windswept']
for key,obj in zip(['compact','mature','windswept'], sorted([o for o in presets.objects if o.asset_data],key=lambda o:o.name)):
 for s in tree.modifiers[0].node_group.interface.items_tree:
  if s.item_type=='SOCKET' and s.in_out=='INPUT':setval(tree,s.name,obj.modifiers[0].get(s.identifier,s.default_value))
 setval(tree,'Wind (m)',0.);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 points=[];ids=[];anchors=[]
 for i in dg.object_instances:
  if not i.is_instance:continue
  branch=len(anchors);m=i.matrix_world;v=m.translation;anchors.append([v.x,v.z,-v.y])
  for p in i.object.original.data.vertices:
   v=m@p.co;points.append([v.x,v.z,-v.y]);ids.append(branch)
 assert len(anchors)==583,len(anchors)
 np.savez_compressed(str(OUT/(key+'_branches.npz')),points=np.array(points),ids=np.array(ids),anchors=np.array(anchors))
 print('BRANCH_MAP',key,len(points),flush=True)
