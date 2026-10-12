"""Read-only Blender inventory for the guild finish pass."""
import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo')
OUT=ROOT/'review_artifacts/axel_guild_finish_20261012'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'review_artifacts/axel_guild_materials_20261011/axel_guild_materials_v4.blend'))
rows=[]
for o in bpy.data.objects:
    if o.type!='MESH':continue
    if not any(k in o.name.lower() for k in ['floor','rose','glass','banner','bird','ground','window']):continue
    pts=[o.matrix_world@Vector(c) for c in o.bound_box]
    rows.append(dict(name=o.name,group=o.get('semantic_group'),bounds=[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]],materials=[m.name if m else '' for m in o.data.materials]))
(OUT/'probe.json').write_text(json.dumps(rows,indent=2),encoding='utf8')
print('FINISH_PROBE',len(rows))
