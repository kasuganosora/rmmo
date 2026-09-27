import bpy
from collections import defaultdict
o=bpy.data.objects['MaidDress'];parent=list(range(len(o.data.vertices)))
def root(i):
    while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
    return i
for e in o.data.edges:
    a,b=map(root,e.vertices);parent[b]=a
groups=defaultdict(list)
for v in o.data.vertices:groups[root(v.index)].append(v)
colors=defaultdict(list)
for loop,color in zip(o.data.loops,o.data.color_attributes.active_color.data):colors[root(loop.vertex_index)].append(color.color[1])
for key,vs in sorted(groups.items(),key=lambda e:-len(e[1]))[:20]:
    p=[o.matrix_world@v.co for v in vs]
    print('ISLAND',len(vs),'bounds',[(round(min(v[i] for v in p),3),round(max(v[i] for v in p),3)) for i in range(3)],'layer',round(sum(colors[key])/max(1,len(colors[key])),3))
