"""Reopen optimized authoring file and verify native parameter continuity."""
import bpy,sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,REVIEW,setval
name='street_oak_thick_reduced.blend' if '--reduced-wood' in sys.argv else ('street_oak_thick_trunk.blend' if '--thick-trunk' in sys.argv else 'street_oak_game_reviewed.blend')
bpy.ops.wm.open_mainfile(filepath=str(ART/name))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;tree=bpy.data.objects['STREET OAK | editable parameters']
tests=[]
for name,values in [('approved',{}),('height',{'Height (m)':7.}),('crown',{'Crown spread':1.5}),('seed',{'Seed':91}),('wind',{'Wind (m)':.04})]:
 for key,value in values.items():setval(tree,key,value)
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();count=sum(1 for i in dg.object_instances if i.is_instance)
 assert count==505,(name,count)
 assert all(0.<d<30. for d in tree.dimensions)
 tests.append({'parameter':name,'instances':count,'dimensions':list(tree.dimensions)})
assert all(im.packed_file for im in bpy.data.images if im.source=='FILE')
if '--reduced-wood' in sys.argv:
 import numpy as np
 def leaf_data(mesh):
  rows=[]
  for p in mesh.polygons:
   if 'needle_volume' not in mesh.materials[p.material_index].name:continue
   for loop in p.loop_indices:rows.append(tuple(mesh.vertices[mesh.loops[loop].vertex_index].co)+tuple(mesh.uv_layers[0].data[loop].uv))
  return np.array(rows)
 for mesh in {o.data for o in bpy.data.collections['SOURCE_C | conservative optimized modules'].objects}:
  source=bpy.data.meshes[mesh.name+'_preserved']
  assert np.array_equal(leaf_data(source),leaf_data(mesh)),mesh.name
 tests.append({'test':'all leaf card positions and UV unchanged','passed':True})
(REVIEW/'authoring_validation.json').write_text(json.dumps({'passed':True,'packed_images':True,'tests':tests,'source_unchanged':True},indent=2),encoding='utf-8')
print('OAK_AUTHORING_PARAMETERS_PASS',flush=True)
