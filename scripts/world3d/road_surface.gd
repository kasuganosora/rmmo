extends RefCounted
## Disjoint convex patches in a fixed 32 m cell; holes are absence of patches.
const Poly=preload("res://scripts/world3d/roof_plan.gd")
const S=preload("res://scripts/world3d/document_schema.gd")

static func valid(record: Dictionary) -> bool:
	if not record.has("road_mesh"): return not record.has("road_source") and not record.has("road_clearance")
	var schema:={"type":"object","properties":{"polygons":{"type":"array","minItems":1,"maxItems":512,"items":{"type":"array","minItems":3,"maxItems":40,"items":{"type":"array","minItems":2,"maxItems":2,"items":S.number(-.50001,.50001)}}},"uv_origin":S.vector(-100000,100000)},"required":["polygons","uv_origin"],"additionalProperties":false}
	schema.properties.grade={"type":"array","minItems":2,"maxItems":2,"items":S.number(-.15,.15)}
	if not S.validate(record.road_mesh,schema).is_empty() or record.get("kind")!="box": return false
	if record.road_mesh.has("grade") and Vector2(record.road_mesh.grade[0],record.road_mesh.grade[1]).length()>.150001: return false
	if record.has("building") or record.has("tile3d") or record.has("building_shape"): return false
	if not S.validate(record.get("size"),S.vector(.001,100000)).is_empty(): return false
	if not S.validate(record.get("road_clearance",3.0),S.number(2.5,10)).is_empty(): return false
	if record.has("road_source") and (not record.road_source is String or not record.road_source.is_valid_identifier()): return false
	for raw in record.road_mesh.polygons:
		var p: Array=[]
		for point in raw: p.append(Vector2(point[0],point[1]))
		var signed_area:=0.0
		for i in range(1,p.size()-1): signed_area+=(p[i]-p[0]).cross(p[i+1]-p[0])
		if signed_area<.000000002: return false
		for i in p.size():
			var a: Vector2=p[i]; var b: Vector2=p[(i+1)%p.size()]
			if a.distance_squared_to(b)<.0000000000001: return false
			for c in p:
				if (b-a).cross(c-a)<-.000001: return false
	return true

static func local_polygons(record: Dictionary) -> Array:
	var out: Array=[]
	for raw in record.road_mesh.polygons:
		var p: Array[Vector3]=[]
		var grade: Array=record.road_mesh.get("grade",[0,0])
		for v in raw:
			var x: float=v[0]*record.size[0]; var z: float=v[1]*record.size[2]
			p.append(Vector3(x,record.size[1]*.5+grade[0]*x+grade[1]*z,z))
		out.append(p)
	return out

static func vertices(record: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3]=[]
	for poly in local_polygons(record):
		for p in poly: out.append(p); out.append(p-Vector3.UP*float(record.size[1]))
	return out

static func mesh(record: Dictionary, material: Material) -> ArrayMesh:
	var result:=ArrayMesh.new()
	var built:=arrays(record)
	for surface in built.size():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built[surface])
		result.surface_set_material(surface,material if material!=null else StandardMaterial3D.new())
		result.surface_set_name(surface,["pavement","underside","edge"][surface])
	return result

static func arrays(record:Dictionary)->Array:
	var result:Array=[];var polys:=local_polygons(record);var drop:=Vector3.DOWN*float(record.size[1])
	var uv:=Poly.vec(record.road_mesh.uv_origin)
	for surface in 3:
		var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in polys:
			var triangles: Array=[]
			if surface<2:
				for i in range(1,p.size()-1):
					triangles.append([p[0],p[i],p[i+1]] if surface==0 else [p[0]+drop,p[i+1]+drop,p[i]+drop])
			else:
				for i in p.size():
					var a: Vector3=p[i]; var b: Vector3=p[(i+1)%p.size()]
					triangles.append([a,a+drop,b+drop]); triangles.append([a,b+drop,b])
			for triangle in triangles:
				var normal: Vector3=(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
				if normal.length()<.5: continue
				for point in triangle:
					st.set_normal(normal); st.set_uv(Vector2(point.x+uv.x,point.z+uv.z) if surface<2 else Vector2((point+uv).dot(Vector3.UP.cross(normal)),point.y+uv.y)); st.add_vertex(point)
		st.generate_tangents(); result.append(st.commit_to_arrays())
	return result

static func signature(record: Dictionary) -> String:
	var value:={}
	for field in ["position","rotation","size","road_mesh","road_clearance","collision","kind","color","invisible","wind_response"]:
		if record.has(field): value[field]=record[field]
	return preload("res://scripts/world3d/city_layout.gd").token(value)
