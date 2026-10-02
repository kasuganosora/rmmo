extends RefCounted
## Convex footprints avoid treating rotated empty corners and courtyards as solid.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")

static func from_points(points: Array[Vector3]) -> Dictionary:
	var flat := PackedVector2Array(); var bounds := AABB(points[0],Vector3.ZERO)
	for p in points: flat.append(Vector2(p.x,p.z)); bounds=bounds.expand(p)
	return {"polygon":Geometry2D.convex_hull(flat),"bounds":bounds}

static func record_shape(record: Dictionary) -> Dictionary: return from_points(Geometry.corners(record))

static func record_shapes(record: Dictionary) -> Array:
	if record.has("terrain_mesh"):
		var terrain=preload("res://scripts/world3d/terrain_surface.gd"); var t: Dictionary=record.terrain_mesh
		var world: Transform3D=terrain.transform(record); var out: Array=[]
		for z in int(t.rows):
			for x in int(t.columns):
				if not terrain.solid(t,x,z): continue
				var points: Array[Vector3]=[]
				var top_low:=INF; var top_high:=-INF
				for p in terrain.cell(record,x,z):
					var top: Vector3=world*p; top_low=minf(top_low,top.y); top_high=maxf(top_high,top.y)
					points.append(top); points.append(world*Vector3(p.x,t.floor*record.size[1],p.z))
				out.append(from_points(points).merged({"top_min_y":top_low,"top_max_y":top_high}))
		return out
	if record.has("fixture") and record.has("fortification"):
		var closed:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position")); var pivot: Vector3=closed*Vector3(record.fixture.pivot[0],record.fixture.pivot[1],record.fixture.pivot[2]); var radius:=0.0
		var size:=Geometry.vector(record,"size"); var local:=AABB(-size*.5,size)
		for i in 8:
			var offset: Vector3=closed*local.get_endpoint(i)-pivot; radius=maxf(radius,Vector2(offset.x,offset.z).length())
		var points: Array[Vector3]=[]
		var bounds:=AABB(Vector3(pivot.x-radius,record.position[1]-size.y*.5,pivot.z-radius),Vector3(radius*2,size.y,radius*2))
		for i in 8: points.append(bounds.get_endpoint(i))
		return [from_points(points)]
	if not record.has("road_mesh") and not record.has("channel_mesh"): return [record_shape(record)]
	var transform:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"))
	var shapes: Array=[]
	var polygons: Array=preload("res://scripts/world3d/channel_surface.gd").local_polygons(record) if record.has("channel_mesh") else preload("res://scripts/world3d/road_surface.gd").local_polygons(record)
	var clearance: float=record.get("channel_clearance",0) if record.has("channel_mesh") else record.get("road_clearance",3)
	for polygon in polygons:
		var points: Array[Vector3]=[]
		for p in polygon:
			points.append(transform*(p-Vector3.UP*float(record.size[1])))
			points.append(transform*(p+Vector3.UP*clearance))
		shapes.append(from_points(points))
	return shapes

static func supporting_ground(record: Dictionary, top: float, foot: float) -> bool:
	return not record.has("road_mesh") and not record.has("building") and record.get("surface_id") in ["ground","grass","dirt","road","stone","sand"] and top<=foot+.005

static func level_ground(record: Dictionary, shape: Dictionary, height: float) -> bool:
	if record.get("kind")!="box" or record.has("building_shape") or record.has("road_mesh") or record.has("building") or record.get("collision","")=="none": return false
	if record.get("surface_id") not in ["ground","grass","dirt","stone","sand"] or absf(record.rotation[0])+absf(record.rotation[2])>.001: return false
	return absf(shape.get("top_max_y",shape.bounds.end.y)-height)<.005 and absf(shape.get("top_min_y",shape.bounds.end.y)-height)<.005

static func local_bounds(records: Array) -> AABB:
	var shapes:=components(records,Vector3.ZERO,Basis.IDENTITY)
	var result: AABB=shapes[0].bounds
	for shape in shapes.slice(1): result=result.merge(shape.bounds)
	return result

static func components(records: Array, origin: Vector3, basis: Basis) -> Array:
	var groups := {}
	var result: Array = []
	for record in records:
		if record.get("building_shape")=="roof_prism" or record.building.role=="roof_tiles":
			var points: Array[Vector3]=[]
			for point in Geometry.corners(record): points.append(origin+basis*point)
			result.append(from_points(points))
			continue
		var part: String = record.building.part.get_slice("/",0)
		var key := part if part in ["wing","wing_left","wing_right","workshop","yard"] else "main"
		if not groups.has(key): groups[key]=[]
		groups[key].append(record)
	for group in groups.values():
		var bounds := Geometry.bounds(group); var points: Array[Vector3]=[]
		for record in group:
			if not record.has("fixture"): continue
			var closed:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"))
			var pivot: Vector3=closed*Vector3(record.fixture.pivot[0],record.fixture.pivot[1],record.fixture.pivot[2])
			var local:=AABB(-Geometry.vector(record,"size")/2,Geometry.vector(record,"size")); var radius:=0.0
			for i in 8:
				var offset:=closed*local.get_endpoint(i)-pivot
				radius=maxf(radius,Vector2(offset.x,offset.z).length())
			# Reserve a complete hinge sweep against other houses and props.
			bounds=bounds.expand(pivot+Vector3(radius,0,radius)).expand(pivot-Vector3(radius,0,radius))
		for i in 8: points.append(origin+basis*bounds.get_endpoint(i))
		result.append(from_points(points))
	return result

static func overlaps(a: Dictionary, b: Dictionary, margin := .005) -> bool:
	for axis in 3:
		if a.bounds.end[axis]<=b.bounds.position[axis]+margin*2 or b.bounds.end[axis]<=a.bounds.position[axis]+margin*2: return false
	for polygon in [a.polygon,b.polygon]:
		for i in polygon.size()-1:
			var edge: Vector2 = polygon[i+1]-polygon[i]
			if edge.length_squared()<.00000001: continue
			var axis := Vector2(-edge.y,edge.x).normalized()
			var amin := INF; var amax := -INF; var bmin := INF; var bmax := -INF
			for point in a.polygon: amin=minf(amin,axis.dot(point)); amax=maxf(amax,axis.dot(point))
			for point in b.polygon: bmin=minf(bmin,axis.dot(point)); bmax=maxf(bmax,axis.dot(point))
			if amax<=bmin+margin or bmax<=amin+margin: return false
	return true

static func batches_overlap(a: Array, b: Array) -> bool:
	for left in a:
		for right in b:
			if overlaps(left,right): return true
	return false
