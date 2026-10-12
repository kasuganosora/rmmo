import bpy,json
from pathlib import Path
from mathutils import Vector
p=Path('D:/code/rmmo_runtime/art_sources/axel_guild/fab_knight_statue_v1')
bpy.ops.wm.open_mainfile(filepath=str(p/'source/Knight Statue.blend'))
rows=[]
for o in bpy.data.objects:
    if o.type!='MESH':continue
    o.data.calc_loop_triangles()
    vs=[o.matrix_world@Vector(v) for v in o.bound_box]
    rows.append({'name':o.name,'triangles':len(o.data.loop_triangles),
                 'bounds':[[min(v[i] for v in vs),max(v[i] for v in vs)] for i in range(3)],
                 'materials':[m.name for m in o.data.materials],'rotation':list(o.rotation_euler)})
(p/'source_inspection.json').write_text(json.dumps(rows,indent=2),encoding='utf8')
print('STATUE_SOURCE',json.dumps(rows))
