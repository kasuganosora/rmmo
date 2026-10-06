"""Reopen procedural delivery; verify packed dependencies and live controls."""
import bpy,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from build_blender_parametric_pine import setval
ROOT=Path('D:/code/rmmo_runtime');ART=ROOT/'art_sources/bridge_street_kit/baltic_pine_procedural'
fine='--fine-clusters' in sys.argv
path=ART/('baltic_pine_fine_clusters_runtime.blend' if fine else 'baltic_pine_small_clusters_runtime.blend')
if '--shaded' in sys.argv:path=ART/('baltic_pine_dense_cards_v5.blend' if fine else 'baltic_pine_dense_cards_v4.blend')
if '--game-cards' in sys.argv:path=ART/'baltic_pine_game_v6.blend'
bpy.ops.wm.open_mainfile(filepath=str(path));sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc
tree=bpy.data.objects['BALTIC PINE | editable parameters']
def matrices():
 bpy.context.view_layer.update()
 return [tuple(v for row in i.matrix_world for v in row) for i in bpy.context.evaluated_depsgraph_get().object_instances if i.is_instance]
before=matrices();assert len(before)==583
native_triangles=None
if '--game-cards' in sys.argv:
 dg=bpy.context.evaluated_depsgraph_get();mesh=bpy.data.meshes.new_from_object(tree.evaluated_get(dg),depsgraph=dg)
 native_triangles=sum(len(p.vertices)-2 for p in mesh.polygons)+sum(sum(len(p.vertices)-2 for p in i.object.data.polygons) for i in dg.object_instances if i.is_instance)
 assert native_triangles<60000,native_triangles
 bpy.data.meshes.remove(mesh)
controls=[s.name for s in tree.modifiers[0].node_group.interface.items_tree if s.item_type=='SOCKET' and s.in_out=='INPUT']
setval(tree,'Crown spread',1.7);after=matrices();assert len(after)==583 and before!=after
images=[i for i in bpy.data.images if i.source=='FILE' and i.users];assert images and all(i.packed_file for i in images)
out=ROOT/'review_artifacts'/('pine_dense_v3_game' if '--game-cards' in sys.argv else ('pine_dense_v3_fine' if fine else 'pine_dense_v3'));out.mkdir(exist_ok=True,parents=True)
(out/'runtime_blend_integrity.json').write_text(json.dumps({'reopened':True,'native_expanded_triangles':native_triangles,'instances':len(before),'crown_control_changes_instance_matrices':True,'packed_file_images':len(images),'controls':controls,'file':str(path),'bytes':path.stat().st_size},indent=2),encoding='utf-8')
print('PROCEDURAL_CLUSTER_VERIFIED',len(before),len(images),flush=True)
