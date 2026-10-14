import bpy,json,math
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend')
out=[]
for o in bpy.data.objects:
 if o.type!='MESH' or not any(o.name.startswith(x) for x in ('Guild_serving_jug_080_WB furniture','Guild_wash_ewer_057_WB furniture','Guild_bottle_round_112_WB furniture')):continue
 adj=[[] for _ in o.data.vertices]
 for e in o.data.edges:a,b=e.vertices;adj[a].append(b);adj[b].append(a)
 remaining=set(range(len(adj)));comps=[]
 while remaining:
  todo=[remaining.pop()];part=[]
  while todo:
   v=todo.pop();part.append(v)
   for n in adj[v]:
    if n in remaining:remaining.remove(n);todo.append(n)
  comps.append(sorted(part))
 comp=max(comps,key=len);rings=[]
 for i in comp:
  p=o.data.vertices[i].co;r=math.hypot(p.x,p.y)
  if not rings or abs(r-rings[-1][0])>1e-6 or abs(p.z-rings[-1][1])>1e-6:rings.append([r,p.z,1])
  else:rings[-1][2]+=1
 out.append(dict(name=o.name,components=[len(c) for c in comps],rings=rings[:8],all_ring_sizes=sorted(set(r[2] for r in rings)),ringcount=len(rings),matrix=[list(r) for r in o.matrix_local]))
print('RINGS',json.dumps(out))
for o in bpy.data.objects:
 if o.type=='MESH' and o.name in ['203 TWIN side.001','Front wall L0']:
  print('UV',o.name,[(u.name,u.active_render) for u in o.data.uv_layers], [m.name for m in o.data.materials])
