import bpy
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
root=Path.cwd()
for path in ['assets/characters/source_models/maid/inspected.blend','assets/characters/imported/female/editable/character.blend']:
 bpy.ops.wm.open_mainfile(filepath=str(art_path(path.removeprefix('assets/'))));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
 print('FILE',path)
 for b in rig.data.bones:
  if 'LeftFoot' in b.name or 'LeftToe' in b.name:print(b.name,tuple(rig.matrix_world@b.head_local),tuple(rig.matrix_world@b.tail_local))
