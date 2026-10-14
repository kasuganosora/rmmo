import bpy,json
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/axel_guild_repaired.blend')
m=bpy.data.materials['Guild PBR | exterior limestone']
print('STONE_NODES',json.dumps([dict(name=n.name,type=n.type,uv_map=getattr(n,'uv_map',None),links=[(l.from_node.name,l.from_socket.name,l.to_socket.name) for s in n.inputs for l in s.links]) for n in m.node_tree.nodes]))
rows=[]
for o in bpy.data.objects:
 if o.type!='MESH' or not any('stone' in m.name.lower() for m in o.data.materials):continue
 if not any(x in o.name.lower() for x in ['dorm','gable','front','centre','central']):continue
 u=o.data.uv_layers
 rows.append(dict(name=o.name,material=[m.name for m in o.data.materials],uv=[(v.name,v.active_render) for v in u],active=u.active.name if u.active else None))
print('STONE_OBJECTS',json.dumps(rows))
bad=[]
for o in bpy.data.objects:
 if o.type!='MESH' or m not in o.data.materials[:]:continue
 if not o.data.uv_layers:continue
 uv=o.data.uv_layers.active
 for f in o.data.polygons:
  if o.data.materials[f.material_index]!=m:continue
  coords=[o.matrix_world@o.data.vertices[o.data.loops[li].vertex_index].co for li in f.loop_indices]
  uvs=[uv.data[li].uv.copy() for li in f.loop_indices]
  area=sum((coords[i]-coords[0]).cross(coords[i+1]-coords[0]).length/2 for i in range(1,len(coords)-1))
  uarea=abs(sum(uvs[i].x*uvs[(i+1)%len(uvs)].y-uvs[(i+1)%len(uvs)].x*uvs[i].y for i in range(len(uvs)))/2)
  if area>.01 and uarea/area<.01:
   bad.append(dict(object=o.name,face=f.index,area=area,uvarea=uarea,normal=list(f.normal),worldnormal=list((coords[1]-coords[0]).cross(coords[2]-coords[0]).normalized()),scale=list(o.scale),uv=[list(t) for t in uvs],material=m.name))
print('COLLAPSED',json.dumps(bad))
