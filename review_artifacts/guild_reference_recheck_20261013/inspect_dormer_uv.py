import bpy, json, math
from mathutils import Vector
from pathlib import Path

base=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3')
bpy.ops.wm.open_mainfile(filepath=str(base/'axel_guild_repaired.blend'))
eye=Vector((21,-6.1,12.3)); aim=Vector((23,1.2,9.8))
forward=(aim-eye).normalized();right=forward.cross(Vector((0,0,1))).normalized();up=right.cross(forward).normalized()
deps=bpy.context.evaluated_depsgraph_get()
hits=[];objects={}
samples=[(860,820),(162,850),(172,735),(1128,245),(885,200),(1048,178),(870,357),(780,800),(907,167)]
for x,y in samples:
    ray=(forward+right*((2*x/1400-1)*1.4*math.tan(math.radians(34)/2))+up*((1-2*y/1000)*math.tan(math.radians(34)/2))).normalized()
    ok,co,normal,face_index,obj,matrix=bpy.context.scene.ray_cast(deps,eye,ray)
    if not ok:continue
    original=bpy.data.objects.get(obj.name)
    hits.append(dict(pixel=[x,y],object=obj.name,point=list(co),normal=list(normal),face=face_index))
    objects[obj.name]=original
rows=[]
for obj in objects.values():
    matrix=obj.matrix_world; layers=[dict(name=u.name,active=u==obj.data.uv_layers.active,render=u.active_render) for u in obj.data.uv_layers]
    mats=[]
    for mat in obj.data.materials:
        if not mat:continue
        textures=[]
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type=='TEX_IMAGE':textures.append(dict(name=node.name,image=node.image.name if node.image else None,uv_links=[dict(node=l.from_node.name,type=l.from_node.type,uvmap=getattr(l.from_node,'uv_map',None)) for l in node.inputs['Vector'].links]))
        mats.append(dict(name=mat.name,textures=textures))
    faces=[]
    for f in obj.data.polygons:
        world=[matrix@obj.data.vertices[obj.data.loops[li].vertex_index].co for li in f.loop_indices]
        geometric=(world[1]-world[0]).cross(world[2]-world[0]).normalized()
        normal=(matrix.to_3x3().inverted().transposed()@f.normal).normalized()
        faces.append(dict(index=f.index,material=obj.data.materials[f.material_index].name,normal=list(normal),geometric_normal=list(geometric),world=[list(c) for c in world],uvs={u.name:[list(u.data[li].uv) for li in f.loop_indices] for u in obj.data.uv_layers}))
    evaluated=obj.evaluated_get(deps);derived=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=deps);eval_faces=[]
    for f in derived.polygons:
        if f.index not in [3,4]:continue
        eval_faces.append(dict(index=f.index,material=derived.materials[f.material_index].name,normal=list(f.normal),world=[list(matrix@derived.vertices[derived.loops[li].vertex_index].co) for li in f.loop_indices],uvs={u.name:[list(u.data[li].uv) for li in f.loop_indices] for u in derived.uv_layers}))
    evaluated.to_mesh_clear()
    rows.append(dict(name=obj.name,mesh=obj.data.name,mesh_users=obj.data.users,linked_objects=[o.name for o in bpy.data.objects if o.type=='MESH' and o.data==obj.data],layers=layers,materials=mats,faces=faces,modifiers=[dict(name=m.name,type=m.type,thickness=getattr(m,'thickness',None),offset=getattr(m,'offset',None)) for m in obj.modifiers],evaluated_faces=eval_faces))
out=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/dormer_uv_diagnosis.json')
out.write_text(json.dumps(dict(camera=dict(eye=list(eye),aim=list(aim),vfov=34),hits=hits,objects=rows),indent=2),encoding='utf8')
print('UV_RAY_HITS',json.dumps(hits),flush=True)
