"""Derive game oak from approved wide-crown master, retaining editable source.

Whole connected leaves are ray-baked to locally fitted cards. Small groups are
isolated while baking so adjacent layers never fill their transparent gaps.
"""
import bpy, sys, json, math
import numpy as np
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import export_pine_small_clusters as baker
import export_pine_runtime as shared
from build_blender_parametric_oak import setval
ROOT=Path('D:/code/rmmo_runtime')
ART=ROOT/'art_sources/bridge_street_kit/english_oak_procedural'
OUT=ROOT/'assets/street_oak_game';OUT.mkdir(parents=True,exist_ok=True)
REVIEW=ROOT/'review_artifacts/street_oak_game';REVIEW.mkdir(parents=True,exist_ok=True)

# Keep both original bark UV and per-leaf vein UV during isolated ray baking.
base_subset=shared.mesh_subset
def subset(src,selected,name):
 m=base_subset(src,selected,name)
 idx=np.concatenate([np.arange(p.loop_start,p.loop_start+p.loop_total) for p in selected])
 if src.uv_layers:m.uv_layers[0].name=src.uv_layers[0].name
 for uv in list(src.uv_layers)[1:]:
  data=np.empty(len(src.loops)*2,np.float32);uv.data.foreach_get('uv',data)
  m.uv_layers.new(name=uv.name).data.foreach_set('uv',data.reshape(-1,2)[idx].ravel())
 return m
shared.mesh_subset=subset
baker.OUT=OUT;baker.CELL=.025;baker.TILE=128;baker.FINE=True
shared.OUT=OUT

def triangles(mesh):return sum(len(p.vertices)-2 for p in mesh.polygons)
def render(sc,cam,sun,tree):
 sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True;sc.cycles.seed=21
 sc.render.resolution_x=1000;sc.render.resolution_y=1000;sc.render.resolution_percentage=100
 sc.view_settings.exposure=.5
 for view,pos,target,scale,rotation in [
  ('full',(14,-20,11),(0,0,4.2),11.8,(.45,-.5,-.5)),
  ('side',(-18,-14,8),(0,0,4.2),11.8,(.45,-.5,-.5)),
  ('foliage',(6,-10,7),(1.8,-.2,6.4),2.5,(.45,-.5,-.5)),
  ('backlight',(14,-20,11),(0,0,4.2),11.8,(.8,.35,2.8))]:
  cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sun.rotation_euler=rotation
  for label,optimized in [('master',False),('game',True)]:
   if label=='master' and '--game-only' in sys.argv and (REVIEW/(label+'_'+view+'.png')).exists():continue
   setval(tree,'Optimized',optimized);sc.render.filepath=str(REVIEW/(label+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
 setval(tree,'Optimized',True)

def main():
 bpy.ops.wm.open_mainfile(filepath=str(ART/'street_oak_parametric.blend'))
 sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;tree=bpy.data.objects['STREET OAK | editable parameters']
 preset=bpy.data.objects['03 Riverside | leaning']
 for s in tree.modifiers[0].node_group.interface.items_tree:
  if s.item_type=='SOCKET' and s.in_out=='INPUT':setval(tree,s.name,preset.modifiers[0].get(s.identifier,s.default_value))
 setval(tree,'Wind (m)',0.);setval(tree,'Optimized',True)
 col=bpy.data.collections['SOURCE_C | conservative optimized modules']
 meshes=list({o.data.name:o.data for o in col.objects}.values())
 original_names={o.name:o.data.name for o in col.objects}
 if '--reuse-meshes' in sys.argv:
  raise RuntimeError('Use saved game blend for downstream review/export')
 modules=baker.bake_modules(meshes)
 bpy.context.window.scene=sc
 for o in col.objects:o.data=modules[original_names[o.name]]
 # The main skeleton stays true 3D, with a conservative independent reduction.
 trunkcol=bpy.data.collections['SOURCE_C | optimized trunk']
 for o in trunkcol.objects:
  o.data=o.data.copy();sc.collection.objects.link(o)
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  dec=o.modifiers.new('Game woody skeleton','DECIMATE');dec.ratio=.15;bpy.ops.object.modifier_apply(modifier=dec.name)
  sc.collection.objects.unlink(o)
 bpy.context.view_layer.objects.active=tree;tree.select_set(True)
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 instances=[triangles(i.object.data) for i in dg.object_instances if i.is_instance]
 total=triangles(tree.evaluated_get(dg).data)+sum(instances)
 report={'source':str(ART/'street_oak_parametric.blend'),'preset':'03 Riverside | leaning','source_triangles':16607056,'near_triangles':total,'instances':len(instances),'leaf_policy':'Whole connected leaves, locally fitted isolated ray bake; no whole branch sheets; all 505 twig instances retained.','cell_source_m':baker.CELL,'runtime_published':False}
 (REVIEW/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print('OAK_GAME_BUILD',report,flush=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.pack()
 bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_game.blend'),compress=True)
 render(sc,sc.camera,bpy.data.objects['REVIEW | fixed sun'],tree)
 bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_game.blend'),compress=True)
 print('OAK_GAME_REVIEW_READY',flush=True)

if __name__=='__main__':main()
