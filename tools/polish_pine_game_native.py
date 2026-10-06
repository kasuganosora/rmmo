"""Keep the game-budget Geometry Nodes source editable, with matching trunk simplification."""
import bpy
from pathlib import Path
path=Path('D:/code/rmmo_runtime/art_sources/bridge_street_kit/baltic_pine_procedural/baltic_pine_game_v6.blend')
bpy.ops.wm.open_mainfile(filepath=str(path))
for obj in bpy.data.objects:
 if any(m.type=='NODES' and 'Pine' in m.node_group.name for m in obj.modifiers if m.type=='NODES'):
  if 'Game trunk silhouette' not in obj.modifiers:
   dec=obj.modifiers.new('Game trunk silhouette','DECIMATE');dec.ratio=.18
for scene in bpy.data.scenes:
 if scene.render.engine=='CYCLES':scene.cycles.transparent_max_bounces=128
bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
print('GAME_NATIVE_READY',flush=True)
