"""Blender background inspection of selected owned modular castle sources."""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector
folder=Path(sys.argv[sys.argv.index('--')+1])
result=[]
for path in sorted(folder.glob('*.fbx')):
    if not any(k in path.stem for k in ('CastleWall','CastleTower','TowerA','ArchedGate','CastleGate','DoorsB')):
        continue
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.fbx(filepath=str(path))
    items=[]
    for o in bpy.context.scene.objects:
        if o.type!='MESH': continue
        o.data.calc_loop_triangles()
        v=[o.matrix_world @ Vector(c) for c in o.bound_box]
        items.append({'name':o.name,'min':[min(p[i] for p in v) for i in range(3)],'max':[max(p[i] for p in v) for i in range(3)],'triangles':len(o.data.loop_triangles),'materials':[m.name for m in o.data.materials]})
    result.append({'file':path.name,'meshes':items})
(folder/'fbx_inspection.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('CASTLE_INSPECTED',len(result))
