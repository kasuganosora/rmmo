import bpy,json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
root=Path.cwd();bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(art_path('characters/source_models/maid/Maid.fbx')))
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  ps=[o.matrix_world@v.co for v in o.data.vertices]
  print('MESH',o.name,len(ps),'bounds',[[round(min(p[i] for p in ps),3),round(max(p[i] for p in ps),3)] for i in range(3)],'mats',[(m.name if m else '') for m in o.data.materials], 'groups',[v.name for v in o.vertex_groups][:10])
 if o.type=='ARMATURE':
  print('RIG',o.name,len(o.data.bones))
  print([(b.name,tuple(round(v,3) for v in o.matrix_world@b.head_local)) for b in o.data.bones if any(s in b.name.lower() for s in ['hips','spine','chest','upperleg','head','upperarm','foot'])])
for mat in bpy.data.materials:
 print('MAT',mat.name,[(n.type,n.image.filepath if n.type=='TEX_IMAGE' and n.image else '') for n in mat.node_tree.nodes] if mat.use_nodes else [])
bpy.ops.wm.save_as_mainfile(filepath=str(art_path('characters/source_models/maid/inspected.blend')))
