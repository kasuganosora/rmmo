extends RefCounted
## Persist bounded convex prisms, normalized to record size so editor transforms,
## prefabs, glTF reload, collision and surface painting all share one geometry.
const Plan=preload("res://scripts/world3d/roof_plan.gd")

static func record(key: String, points: Array, extrusion: Vector3, color: Array, floor_: int, floor_y: float, semantic: String="roof_top") -> Dictionary:
	var bounds:=AABB(Plan.vec(points[0]),Vector3.ZERO)
	for p in points:
		bounds=bounds.expand(Plan.vec(p)); bounds=bounds.expand(Plan.vec(p)+extrusion)
	var size:=bounds.size; var center:=bounds.get_center(); var normalized: Array=[]
	for p in points: normalized.append(Plan.arr((Plan.vec(p)-center)/size))
	return {"uuid":key.replace("/","_"),"kind":"box","surface_id":"block","position":Plan.arr(center),"rotation":[0,0,0],"size":Plan.arr(size),"color":color,"editor_name":key,"building_shape":"roof_prism","roof_mesh":{"polygon":normalized,"extrusion":Plan.arr(extrusion/size),"semantic":semantic,"uv_origin":Plan.arr(center)},"building":{"part":key,"floor":floor_,"floor_y":floor_y,"role":"roof"}}

static func valid(record_: Dictionary) -> bool:
	var size_: Variant=record_.get("size")
	if not size_ is Array or size_.size()!=3: return false
	for value in size_:
		if (not value is int and not value is float) or not is_finite(float(value)) or value<=0: return false
	var data: Variant=record_.get("roof_mesh")
	if not data is Dictionary or data.size()<3 or data.size()>4 or data.keys().any(func(key):return key not in ["polygon","extrusion","semantic","uv_origin"]) or data.get("semantic") not in ["roof_top","gable"]: return false
	if data.has("uv_origin"):
		if not data.uv_origin is Array or data.uv_origin.size()!=3: return false
		for value in data.uv_origin:
			if (not value is int and not value is float) or not is_finite(float(value)) or absf(value)>100000: return false
	if not data.get("polygon") is Array or data.polygon.size()<3 or data.polygon.size()>32: return false
	if not data.get("extrusion") is Array or data.extrusion.size()!=3: return false
	var vectors: Array=data.polygon.duplicate(); vectors.append(data.extrusion)
	for p in vectors:
		if not p is Array or p.size()!=3: return false
		for v in p:
			if (not v is float and not v is int) or not is_finite(float(v)) or absf(v)>1.001: return false
	var e:=Plan.vec(data.extrusion); var poly: Array=data.polygon
	var normal:=Vector3.ZERO
	for i in range(1,poly.size()-1): normal+=(Plan.vec(poly[i])-Plan.vec(poly[0])).cross(Plan.vec(poly[i+1])-Plan.vec(poly[0]))
	if normal.length()<.000001 or absf(normal.normalized().dot(e))<.000001: return false
	normal=normal.normalized()
	for i in poly.size():
		var a:=Plan.vec(poly[i]); var b:=Plan.vec(poly[(i+1)%poly.size()]); var c:=Plan.vec(poly[(i+2)%poly.size()])
		if a.distance_squared_to(b)<.000000000001: return false
		if absf(normal.dot(a-Plan.vec(poly[0])))>.0001 or (b-a).cross(c-b).dot(normal)<-.000001: return false
		for point_ in poly:
			if (b-a).cross(Plan.vec(point_)-a).dot(normal)<-.000001: return false
		for j in 3:
			if absf(a[j])>.50001 or absf(a[j]+e[j])>.50002: return false
	return true

static func vertices(record_: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3]=[]; var size:=Plan.vec(record_.size); var data: Dictionary=record_.roof_mesh
	for p in data.polygon:
		out.append(Plan.vec(p)*size); out.append((Plan.vec(p)+Plan.vec(data.extrusion))*size)
	return out

static func mesh(record_: Dictionary, material: Material) -> ArrayMesh:
	var data: Dictionary=record_.roof_mesh; var size:=Plan.vec(record_.size); var poly: Array[Vector3]=[]
	for p in data.polygon: poly.append(Plan.vec(p)*size)
	var e:=Plan.vec(data.extrusion)*size
	# Anchor UVs in the generated building's local space, not the movable record
	# position. Neighbouring patches must stay aligned after a whole-house turn.
	var uv_origin:=Plan.vec(data.get("uv_origin",record_.position))
	var normal:=Vector3.ZERO
	for i in range(1,poly.size()-1): normal+=(poly[i+1]-poly[0]).cross(poly[i]-poly[0])
	if normal.dot(e)>0: poly.reverse(); normal=-normal
	normal=normal.normalized()
	var u:=(Vector3.RIGHT-normal*normal.x).normalized()
	if u.length()<.5: u=(Vector3.FORWARD-normal*normal.dot(Vector3.FORWARD)).normalized()
	var v:=normal.cross(u).normalized(); var result:=ArrayMesh.new()
	for surface in 3:
		var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var mat: Material=material.duplicate() if material!=null else StandardMaterial3D.new()
		if surface==1: mat.albedo_color=Color(.31,.25,.18) if data.semantic=="roof_top" else mat.albedo_color
		elif surface==2: mat.albedo_color=mat.albedo_color.darkened(.15)
		st.set_material(mat)
		var triangles: Array=[]
		if surface==0:
			for i in range(1,poly.size()-1): triangles.append([poly[0],poly[i],poly[i+1]])
		elif surface==1:
			for i in range(1,poly.size()-1): triangles.append([poly[0]+e,poly[i+1]+e,poly[i]+e])
		else:
			for i in poly.size():
				var a:=poly[i]; var b:=poly[(i+1)%poly.size()]
				if a.distance_to(b)<.000001: continue
				triangles.append([a,a+e,b+e]); triangles.append([a,b+e,b])
		for triangle in triangles:
			var n: Vector3=(triangle[2]-triangle[0]).cross(triangle[1]-triangle[0]).normalized()
			if n.length()<.5: continue
			var tu: Vector3=u if surface<2 else (triangle[1]-triangle[0]).normalized(); var tv: Vector3=v if surface<2 else n.cross(tu)
			for p in triangle:
				st.set_normal(n); st.set_uv(Vector2((p+uv_origin).dot(tu),(p+uv_origin).dot(tv))); st.add_vertex(p)
		st.generate_tangents(); st.commit(result)
		result.surface_set_name(surface,["roof_top" if data.semantic=="roof_top" else "gable","underside","edge"][surface])
	return result

static func beam(key: String, a: Vector3, b: Vector3, width: float, height_: float, color: Array, floor_: int, floor_y: float) -> Dictionary:
	var direction:=(b-a).normalized(); var basis:=Basis.looking_at(direction,Vector3.UP)
	return {"uuid":key.replace("/","_"),"kind":"box","surface_id":"block","position":Plan.arr((a+b)/2),"rotation":Plan.arr(basis.get_euler()*180/PI),"size":[width,height_,a.distance_to(b)+.006],"color":color,"editor_name":key,"building":{"part":key,"floor":floor_,"floor_y":floor_y,"role":"roof_tiles"}}

static func generate(solved: Dictionary) -> Array:
	var out: Array=[]; var modules: Dictionary={}
	for m in solved.modules: modules[m.id]=m
	for face in solved.faces:
		var m: Dictionary=modules[face.module]
		out.append(record(face.id,face.boundary,Vector3(0,-.14,0),m.colors.roof,face.floor,m.eave_y))
	for edge in solved.edges:
		var m: Dictionary=modules[edge.module]; var a:=Plan.vec(edge.a); var b:=Plan.vec(edge.b)
		if a.distance_to(b)<.02: continue
		var color: Array=m.colors.roof; var width:=.22; var height_:=.12; var offset:=Vector3(0,.045,0)
		if edge.type in ["valley","wall_abutment","opening"]:
			width=.16; height_=.025; color=[.29,.27,.24]; offset.y=.015
		elif edge.type in ["eave","gable"]: width=.13; height_=.21; color=m.colors.trim; offset.y=-.09
		out.append(beam(edge.module+"/"+edge.type+"/"+edge.id,a+offset,b+offset,width,height_,color,edge.floor,m.eave_y))
	# Close the wall below the final roof envelope, at the building wall plane.
	# Boundary line intervals are sampled analytically from all planar facets;
	# shared walls and already enclosed edges do not get a duplicate gable.
	for m in solved.modules:
		var r: Array=m.rect
		for side in 4:
			if side in m.get("open_sides",[]): continue
			var corners:=Plan.rect(r); var a: Vector2=corners[side]; var b: Vector2=corners[(side+1)%4]; var delta:=b-a
			var intervals: Array=[]
			for face in solved.faces:
				if absf(modules[face.module].eave_y-m.eave_y)>.001: continue
				var lo:=0.0; var hi:=1.0; var polygon: Array=[]
				for p in face.boundary: polygon.append(Vector2(p[0],p[2]))
				for i in polygon.size():
					var start: Vector2=polygon[i]; var edge: Vector2=polygon[(i+1)%polygon.size()]-start; var n:=Vector2(-edge.y,edge.x)
					var value:=n.dot(a-start); var change:=n.dot(delta)
					if absf(change)<.0000001:
						if value<-.0001: hi=-1; break
					elif change>0: lo=maxf(lo,-value/change)
					else: hi=minf(hi,-value/change)
				if hi-lo>.0001: intervals.append({"lo":lo,"hi":hi,"plane":Plan.vec(face.plane)})
			for i in intervals.size():
				var interval: Dictionary=intervals[i]; var p0: Vector2=a+delta*interval.lo; var p1: Vector2=a+delta*interval.hi
				var top0:=maxf(m.eave_y,Plan.height(interval.plane,p0)-.14); var top1:=maxf(m.eave_y,Plan.height(interval.plane,p1)-.14)
				if maxf(top0,top1)-m.eave_y<.015: continue
				var polygon: Array=[Plan.arr(Vector3(p0.x,m.eave_y,p0.y)),Plan.arr(Vector3(p1.x,m.eave_y,p1.y))]
				if top1>m.eave_y+.001: polygon.append(Plan.arr(Vector3(p1.x,top1,p1.y)))
				if top0>m.eave_y+.001: polygon.append(Plan.arr(Vector3(p0.x,top0,p0.y)))
				var inward:=Vector3(-delta.y,0,delta.x).normalized()*.2
				out.append(record(m.id+"/gable%d/patch%d"%[side,i],polygon,inward,m.colors.wall,m.floor,m.eave_y,"gable"))
	return out
