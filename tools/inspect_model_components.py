import bpy,json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from art_paths import art_path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(art_path('characters/source_models/inspected/artoria.blend')))
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    adj=[[] for _ in o.data.vertices]
    for e in o.data.edges:
        a,b=e.vertices;adj[a].append(b);adj[b].append(a)
    unseen=set(range(len(adj)));parts=[]
    while unseen:
        todo=[unseen.pop()];component=[]
        while todo:
            v=todo.pop();component.append(v)
            for n in adj[v]:
                if n in unseen:unseen.remove(n);todo.append(n)
        pts=[o.matrix_world@o.data.vertices[v].co for v in component]
        parts.append({'count':len(component),'min':[round(min(p[i] for p in pts),4) for i in range(3)],'max':[round(max(p[i] for p in pts),4) for i in range(3)],'seed':component[0]})
    print('COMPONENTS',o.name,json.dumps(sorted(parts,key=lambda p:-p['count'])),flush=True)
for m in bpy.data.materials:
    print('MAT',m.name,[(n.type,n.name,[(i.name,str(i.default_value)) for i in n.inputs if not i.is_linked and i.name in ['Base Color','Emission Color','Emission Strength','Alpha']]) for n in m.node_tree.nodes],flush=True)
