extends RefCounted
## Remove duplicate coplanar skins at solid architectural joins. Each original
## object keeps its identity, collision solid, floor and editable materials.
const EPS:=.0001
const CELL:=4.0
const ROLES:=["floor","beam","stone_trim","post"]
static func v(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
static func cells(a:AABB)->Array:
	var out:Array=[]
	for x in range(floori((a.position.x-EPS)/CELL),floori((a.end.x+EPS)/CELL)+1):
		for y in range(floori((a.position.y-EPS)/CELL),floori((a.end.y+EPS)/CELL)+1):
			for z in range(floori((a.position.z-EPS)/CELL),floori((a.end.z+EPS)/CELL)+1):out.append(Vector3i(x,y,z))
	return out
static func subtract(a:Rect2,b:Rect2)->Array:
	var cut:=a.intersection(b)
	if cut.size.x<EPS or cut.size.y<EPS:return [a]
	var result:Array=[]
	for r in [Rect2(a.position,Vector2(cut.position.x-a.position.x,a.size.y)),Rect2(Vector2(cut.end.x,a.position.y),Vector2(a.end.x-cut.end.x,a.size.y)),Rect2(Vector2(cut.position.x,a.position.y),Vector2(cut.size.x,cut.position.y-a.position.y)),Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,a.end.y-cut.end.y))]:
		if r.size.x>EPS and r.size.y>EPS:result.append(r)
	return result
static func apply(plan:Dictionary)->void:
	var rows:Array=[];var bins:Dictionary={}
	var walls:=preload("res://scripts/world3d/house_wall_contacts.gd").solids(plan.records)
	for r:Dictionary in plan.records:
		if r.has("building_shape") or r.has("fixture") or r.building.role not in ROLES or not v(r.rotation).is_zero_approx():continue
		var bounds:=AABB(v(r.position)-v(r.size)/2,v(r.size));var index:=rows.size()
		rows.append({"record":r,"bounds":bounds})
		for cell in cells(bounds):
			if not bins.has(cell):bins[cell]=[]
			bins[cell].append(index)
	for i in rows.size():
		var row:Dictionary=rows[i];var a:AABB=row.bounds;var candidates:Dictionary={}
		for cell in cells(a):
			for other in bins[cell]:
				if other!=i:candidates[other]=true
		var patches:Array=[];var changed:=false
		for face in 6:
			var axis:=face/2;var sign_:float=-1 if face%2==0 else 1
			var u:=(axis+1)%3;var w:=(axis+2)%3
			var plane:float=a.position[axis] if sign_<0 else a.end[axis]
			var fragments:Array=[Rect2(Vector2(a.position[u],a.position[w]),Vector2(a.size[u],a.size[w]))]
			# End faces of corner dressings can coincide with perpendicular walls.
			# Remove only their buried part; keep the wall, silhouette and collision.
			if row.record.building.role!="floor":
				for cut:Rect2 in preload("res://scripts/world3d/house_wall_contacts.gd").cuts(walls,axis,plane,int(row.record.building.floor),fragments[0]):
					var next:Array=[]
					for f:Rect2 in fragments:
						var pieces:=subtract(f,cut)
						if pieces.size()!=1 or pieces[0]!=f:changed=true
						next.append_array(pieces)
					fragments=next
			for j:int in candidates:
				var b:AABB=rows[j].bounds
				var other_face:float=b.position[axis] if sign_<0 else b.end[axis]
				# Stable ownership of equal exterior planes. Do not remove geometry
				# just because an independently hidden upper storey encloses it.
				if j<i or absf(plane-other_face)>EPS:continue
				var cut:=Rect2(Vector2(b.position[u],b.position[w]),Vector2(b.size[u],b.size[w]))
				var next:Array=[]
				for f:Rect2 in fragments:
					var pieces:=subtract(f,cut)
					if pieces.size()!=1 or pieces[0]!=f:changed=true
					next.append_array(pieces)
				fragments=next
			for f:Rect2 in fragments:
				patches.append([face,(f.position.x-a.position[u])/a.size[u]-.5,(f.position.y-a.position[w])/a.size[w]-.5,(f.end.x-a.position[u])/a.size[u]-.5,(f.end.y-a.position[w])/a.size[w]-.5])
		if changed and not patches.is_empty():
			row.record.building_shape="joined_box";row.record.box_faces=patches
static func valid(r:Dictionary)->bool:
	var patches:Variant=r.get("box_faces")
	if not patches is Array or patches.is_empty() or patches.size()>128:return false
	for patch in patches:
		if not patch is Array or patch.size()!=5:return false
		for value in patch:
			if (not value is int and not value is float) or not is_finite(value):return false
		if patch[0]!=int(patch[0]) or patch[0]<0 or patch[0]>5:return false
		if patch[1]<-.50001 or patch[2]<-.50001 or patch[3]>.50001 or patch[4]>.50001 or patch[3]<=patch[1] or patch[4]<=patch[2]:return false
	return true
static func mesh(r:Dictionary,material:Material)->ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(material)
	var size:=v(r.size)
	for patch:Array in r.box_faces:
		var face:=int(patch[0]);var axis:=face/2;var u:=(axis+1)%3;var w:=(axis+2)%3;var sign_:float=-1 if face%2==0 else 1
		var normal:=Vector3.ZERO;normal[axis]=sign_
		var corners:Array=[]
		for uv in [Vector2(patch[1],patch[2]),Vector2(patch[3],patch[2]),Vector2(patch[3],patch[4]),Vector2(patch[1],patch[4])]:
			var point:=Vector3.ZERO;point[axis]=sign_*.5;point[u]=uv.x;point[w]=uv.y;corners.append(point*size)
		for index in ([0,2,1,0,3,2] if sign_>0 else [0,1,2,0,2,3]):
			var point:Vector3=corners[index];st.set_normal(normal);st.set_uv(Vector2(point[u],point[w]));st.add_vertex(point)
	st.generate_tangents();var result:=st.commit()
	preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(result)
	return result
