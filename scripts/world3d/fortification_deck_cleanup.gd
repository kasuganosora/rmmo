extends RefCounted
## Offline repair/bake step. Each coplanar deck patch has one visible owner.
## Collision, identity, materials and original uncut vertex attributes stay intact.
const Frozen=preload("res://scripts/world3d/house_prefab.gd")
const CELL:=8.0
const EPS:=0.000001

static func area(p:PackedVector2Array)->float:
	var result:=0.0
	for i in range(1,p.size()-1):result+=cross(p[i]-p[0],p[i+1]-p[0])
	return result*.5
static func cross(a:Vector2,b:Vector2)->float:return float(a.x)*b.y-float(a.y)*b.x
static func half(p:PackedVector2Array,a:Vector2,b:Vector2,inside:bool)->PackedVector2Array:
	var result:=PackedVector2Array()
	for i in p.size():
		var u:=p[i];var v:=p[(i+1)%p.size()]
		var du:=cross(b-a,u-a);var dv:=cross(b-a,v-a)
		var keep_u:bool=du>=0 if inside else du<=0
		var keep_v:bool=dv>=0 if inside else dv<=0
		if keep_u:result.append(u)
		if keep_u!=keep_v:result.append(u.lerp(v,du/(du-dv)))
	return result
static func subtract(p:PackedVector2Array,cut:PackedVector2Array)->Array:
	var overlap:=p
	for i in cut.size():
		overlap=half(overlap,cut[i],cut[(i+1)%cut.size()],true)
		if overlap.size()<3:return [p]
	if absf(area(overlap))<=EPS:return [p]
	var remaining:=p;var result:Array=[]
	for i in cut.size():
		var outside:=half(remaining,cut[i],cut[(i+1)%cut.size()],false)
		if outside.size()>=3 and absf(area(outside))>EPS:result.append(outside)
		remaining=half(remaining,cut[i],cut[(i+1)%cut.size()],true)
		if remaining.size()<3:break
	return result
static func cells(p:PackedVector2Array)->Array:
	var bounds:=Rect2(p[0],Vector2.ZERO)
	for v in p:bounds=bounds.expand(v)
	var result:Array=[]
	for x in range(floori(bounds.position.x/CELL),floori(bounds.end.x/CELL)+1):
		for z in range(floori(bounds.position.y/CELL),floori(bounds.end.y/CELL)+1):result.append(Vector2i(x,z))
	return result

static func apply(records:Array,deck:float,floor_texture:String="")->Dictionary:
	var rows:Array=[];var triangles:Array=[]
	for r:Dictionary in records:
		if not r.has("house_prefab") or r.has("fixture") or not r.has("fortification"):continue
		# Generated fixed masonry is unrotated. Do not reinterpret hand transforms.
		if not Frozen.vec(r.rotation).is_zero_approx():continue
		var data:=Frozen.decode(r.house_prefab)
		if data.is_empty():return {"ok":false,"error":"Invalid frozen masonry"}
		var mesh_id:int=data.entries[0][1][0];var mesh:Dictionary=data.meshes[mesh_id]
		var row:={"record":r,"data":data,"mesh_id":mesh_id,"changes":{}}
		var row_id:=rows.size();rows.append(row)
		var origin:=Frozen.vec(r.position)
		for s in mesh.surfaces.size():
			var a:Array=mesh.surfaces[s];var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			if indices.is_empty():indices=PackedInt32Array(range(vertices.size()))
			var paint:Dictionary=data.materials[mesh.materials[s]].get("paint",{})
			var priority:=1 if not floor_texture.is_empty() and paint.get("texture_path","")==floor_texture else 0
			for k in range(0,indices.size(),3):
				var ids:=[indices[k],indices[k+1],indices[k+2]];var p:=PackedVector2Array();var flat:=true
				for id:int in ids:
					var v:Vector3=vertices[id]
					if absf(float(v.y)+origin.y-deck)>.0001 or a[Mesh.ARRAY_NORMAL]==null or a[Mesh.ARRAY_NORMAL][id].y<.99:flat=false;break
					p.append(Vector2(v.x,v.z))
				if not flat or absf(area(p))<EPS:continue
				if area(p)<0:p.reverse()
				triangles.append({"row":row_id,"surface":s,"offset":k,"ids":ids,"poly":p,"position":Vector2(origin.x,origin.z),"priority":priority})
	# Stable order; paving owns its full footprint, rubble remains outside it.
	triangles.sort_custom(func(a,b):return a.priority>b.priority if a.priority!=b.priority else (a.row<b.row if a.row!=b.row else (a.surface<b.surface if a.surface!=b.surface else a.offset<b.offset)))
	var bins:Dictionary={};var removed:=0.0;var changed_triangles:=0
	for triangle_index in triangles.size():
		var t:Dictionary=triangles[triangle_index]
		var origin:Vector2=t.poly[0];var local:=PackedVector2Array()
		for v:Vector2 in t.poly:local.append(v-origin)
		var world_poly:=PackedVector2Array()
		for v:Vector2 in t.poly:world_poly.append(v+t.position)
		var pieces:Array=[local];var candidates:Dictionary={};var keys:=cells(world_poly)
		for key in keys:
			for index:int in bins.get(key,[]):candidates[index]=true
		for index:int in candidates:
			var cut:=PackedVector2Array()
			var delta:Vector2=triangles[index].position-t.position
			for v:Vector2 in triangles[index].poly:cut.append((v-origin)+delta)
			var next:Array=[]
			for piece:PackedVector2Array in pieces:next.append_array(subtract(piece,cut))
			pieces=next
			if pieces.is_empty():break
		var left:=0.0
		for p:PackedVector2Array in pieces:left+=absf(area(p))
		var loss:float=absf(area(local))-left
		if loss>0.00001:
			removed+=loss;changed_triangles+=1
			var row:Dictionary=rows[t.row]
			if not row.changes.has(t.surface):row.changes[t.surface]={}
			row.changes[t.surface][t.offset]={"pieces":pieces,"origin":origin,"ids":t.ids}
		for key in keys:
			if not bins.has(key):bins[key]=[]
			bins[key].append(triangle_index)
	var updates:Array=[]
	for row:Dictionary in rows:
		if row.changes.is_empty():continue
		var data:Dictionary=row.data.duplicate(true);var mesh:Dictionary=data.meshes[row.mesh_id].duplicate(true)
		# Render and collision may reference the same entry: always detach rendering.
		if data.entries[0][1][1]==row.mesh_id:
			data.entries[0][1][0]=data.meshes.size();data.meshes.append(mesh)
		else:data.meshes[row.mesh_id]=mesh
		var slots:Array=row.changes.keys();slots.sort();slots.reverse()
		for s:int in slots:
			var rebuilt:=rebuild(mesh.surfaces[s],row.changes[s],Frozen.vec(row.record.position))
			if rebuilt.is_empty():mesh.surfaces.remove_at(s);mesh.materials.remove_at(s)
			else:mesh.surfaces[s]=rebuilt
		if not Frozen.Cook.valid_data(data):return {"ok":false,"error":"Invalid repaired mesh"}
		var bytes:=var_to_bytes(data)
		updates.append([row.record,{"version":1,"sha256":Frozen.Cook.Envelope.checksum(bytes).hex_encode(),"length":bytes.size(),"data":Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_ZSTD))}])
	for update:Array in updates:update[0].house_prefab=update[1]
	return {"ok":true,"triangles":triangles.size(),"changed_triangles":changed_triangles,"changed_records":updates.size(),"overlap_area":removed}

static func rebuild(a:Array,changes:Dictionary,origin:Vector3)->Array:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ids:PackedInt32Array=a[Mesh.ARRAY_INDEX]
	if ids.is_empty():ids=PackedInt32Array(range(a[Mesh.ARRAY_VERTEX].size()))
	for k in range(0,ids.size(),3):
		var triangle:=[ids[k],ids[k+1],ids[k+2]]
		if not changes.has(k):
			for j in 3:emit(st,a,triangle,Vector3(1 if j==0 else 0,1 if j==1 else 0,1 if j==2 else 0))
			continue
		var change:Dictionary=changes[k];var p:Array=[]
		for id:int in triangle:
			var v:Vector3=a[Mesh.ARRAY_VERTEX][id];p.append(Vector2(v.x,v.z)-change.origin)
		var determinant:=cross(p[1]-p[0],p[2]-p[0])
		for polygon:PackedVector2Array in change.pieces:
			for i in range(1,polygon.size()-1):
				for j:int in ([0,i+1,i] if determinant<0 else [0,i,i+1]):
					var v:=polygon[j];var b:=cross(v-p[0],p[2]-p[0])/determinant;var c:=cross(p[1]-p[0],v-p[0])/determinant
					emit(st,a,triangle,Vector3(1-b-c,b,c))
	st.index();return st.commit_to_arrays()
static func emit(st:SurfaceTool,a:Array,ids:Array,w:Vector3)->void:
	for slot in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if a[slot]==null:continue
		var value:Variant=a[slot][ids[0]]*w.x+a[slot][ids[1]]*w.y+a[slot][ids[2]]*w.z
		match slot:
			Mesh.ARRAY_NORMAL:st.set_normal(value.normalized())
			Mesh.ARRAY_COLOR:st.set_color(value)
			Mesh.ARRAY_TEX_UV:st.set_uv(value)
			Mesh.ARRAY_TEX_UV2:st.set_uv2(value)
	if a[Mesh.ARRAY_TANGENT]!=null:
		var tangent:=Vector3.ZERO;var sign_:=0.0
		for j in 3:
			var i:int=ids[j]*4;tangent+=Vector3(a[Mesh.ARRAY_TANGENT][i],a[Mesh.ARRAY_TANGENT][i+1],a[Mesh.ARRAY_TANGENT][i+2])*w[j];sign_+=a[Mesh.ARRAY_TANGENT][i+3]*w[j]
		st.set_tangent(Plane(tangent.normalized(),1 if sign_>=0 else -1))
	st.add_vertex(a[Mesh.ARRAY_VERTEX][ids[0]]*w.x+a[Mesh.ARRAY_VERTEX][ids[1]]*w.y+a[Mesh.ARRAY_VERTEX][ids[2]]*w.z)
