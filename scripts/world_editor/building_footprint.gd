extends RefCounted
## Convex footprints avoid treating rotated empty corners and courtyards as solid.
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")

static func from_points(points: Array[Vector3]) -> Dictionary:
	var flat := PackedVector2Array(); var bounds := AABB(points[0],Vector3.ZERO)
	for p in points: flat.append(Vector2(p.x,p.z)); bounds=bounds.expand(p)
	return {"polygon":Geometry2D.convex_hull(flat),"bounds":bounds}

static func record_shape(record: Dictionary) -> Dictionary: return from_points(Geometry.corners(record))

static func record_shapes(record: Dictionary) -> Array:
	if record.has("rock_bank"):
		var data=preload("res://scripts/world3d/rock_bank_mesh.gd");var rows:Array=data.sections(record);var result:Array=[]
		var pose:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"));var scale:=Geometry.vector(record,"size")
		for i in rows.size()-1:
			var points:Array[Vector3]=[]
			for row in [rows[i],rows[i+1]]:
				for p:Vector3 in [row.outer,row.inner]:points.append(pose*(p*scale));points.append(pose*((p+Vector3.DOWN*record.rock_bank.height)*scale))
			result.append(from_points(points))
		return result
	if record.has("terrain_mesh"):
		var terrain=preload("res://scripts/world3d/terrain_surface.gd"); var t: Dictionary=record.terrain_mesh
		var world: Transform3D=terrain.transform(record); var out: Array=[]
		var fields: Array=[]
		for region in record.get("terrain_regions",{}).get("regions",[]):
			if region.has("furrows"): fields.append({"bounds":preload("res://scripts/world3d/terrain_regions.gd").bounds(preload("res://scripts/world3d/terrain_regions.gd").points(region)),"height":region.furrows.height})
		for z in int(t.rows):
			for x in int(t.columns):
				if not terrain.solid(t,x,z): continue
				var points: Array[Vector3]=[]
				var top_low:=INF; var top_high:=-INF
				var extra:=0.; var base: Vector3=terrain.point(record,x,z)
				var cell_bounds:=Rect2(Vector2(base.x,base.z),Vector2(record.size[0]/t.columns,record.size[2]/t.rows))
				for field in fields:
					if field.bounds.intersects(cell_bounds): extra=maxf(extra,field.height)
				for p in terrain.cell(record,x,z):
					var top: Vector3=world*(p+Vector3.UP*extra); top_low=minf(top_low,(world*p).y); top_high=maxf(top_high,top.y)
					points.append(top); points.append(world*Vector3(p.x,t.floor*record.size[1],p.z))
				out.append(from_points(points).merged({"top_min_y":top_low,"top_max_y":top_high}))
		return out
	if record.has("fixture") and record.has("fortification"):return fixture_shapes(record)
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

static func fixture_shapes(record:Dictionary)->Array:
	var closed:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"))
	var local:=AABB(-Geometry.vector(record,"size")*.5,Geometry.vector(record,"size")); var pivot: Vector3=closed*Vector3(record.fixture.pivot[0],record.fixture.pivot[1],record.fixture.pivot[2]); var radius:=0.0
	for i in 8: radius=maxf(radius,(closed*local.get_endpoint(i)).distance_to(pivot))
	var steps:=maxi(1,ceili(absf(record.fixture.angle)/5.0)); var points: Array[Vector3]=[]
	for step in steps+1:
		var pose:=preload("res://scripts/world3d/building_fixtures.gd").pose(closed,record.fixture,float(step)/steps)
		for i in 8: points.append(pose*local.get_endpoint(i))
	var shape:=from_points(points)
	# Bound the missing arc between samples by its maximum sagitta. This
	# reserves the actual full opening sweep, not an unrelated 360-degree box.
	var padding:=radius*(1.0-cos(deg_to_rad(absf(record.fixture.angle)/steps)*.5))+.002
	var expanded:=Geometry2D.offset_polygon(shape.polygon,padding,Geometry2D.JOIN_ROUND)
	if not expanded.is_empty():
		shape.polygon=expanded[0]; shape.polygon.append(shape.polygon[0])
	shape.bounds=shape.bounds.grow(padding)
	return [shape]

static func supporting_ground(record: Dictionary, top: float, foot: float) -> bool:
	return not record.has("road_mesh") and not record.has("building") and record.get("surface_id") in ["ground","grass","dirt","road","stone","sand"] and top<=foot+.005

static func foundation_support_height(parameters:Dictionary,origin_y:float,records:Array)->float:
	# These layouts raise their actual ground floor above the placement origin
	# and extend a foundation down through it. Terrain may meet that foundation,
	# but must never be excused above the real interior floor. All records here
	# are already transformed into world space (generated or frozen prefab).
	if parameters.get("layout","") not in ["townhouse","hall"]:return origin_y
	var raised:Variant=parameters.get("base_height",0.)
	var depth:Variant=parameters.get("foundation_depth",0.)
	if (not raised is float and not raised is int) or (not depth is float and not depth is int):return origin_y
	if not is_finite(float(raised)) or not is_finite(float(depth)) or raised<=0. or raised>.9 or depth<=0. or depth>3.:return origin_y
	var floor_cap:=INF
	for r:Dictionary in records:
		var b:Dictionary=r.get("building",{})
		if b.get("floor",-1)!=0 or b.get("role","")!="floor":continue
		# Keep supporting_ground's 5 mm contact tolerance below the actual top;
		# edited or older prefabs cannot gain headroom merely from recipe metadata.
		floor_cap=minf(floor_cap,Geometry.bounds([r]).end.y-.005)
	if not is_finite(floor_cap) or floor_cap<=origin_y:return origin_y
	return minf(origin_y+float(raised),floor_cap)

static func terrain_components(records:Array)->Array:
	# Whole-building hulls are useful for reserving interiors and door access,
	# but must not extrude an upstairs shutter/eave down through its foundation.
	# Keep each native component's vertical range and its full fixture sweep.
	var result:Array=[]
	for record:Dictionary in records:
		for shape:Dictionary in components([record],Vector3.ZERO,Basis.IDENTITY):
			shape.part=str(record.get("building",{}).get("part",record.get("uuid","")));result.append(shape)
	return result

static func terrain_conflict(record:Dictionary,pieces:Array,support_height:float)->Dictionary:
	var T=preload("res://scripts/world3d/terrain_surface.gd")
	var Clip=preload("res://scripts/world3d/road_plan.gd")
	var Poly=preload("res://scripts/world3d/roof_plan.gd")
	# Preserve conservative handling for unsupported tilted ground / raised
	# furrows. This refinement concerns the actual triangulated height surface.
	if absf(record.rotation[0])+absf(record.rotation[2])>.0001 or preload("res://scripts/world3d/terrain_furrows.gd").maximum_height(record)>0:
		for cell:Dictionary in record_shapes(record):
			if not supporting_ground(record,cell.bounds.end.y,support_height) and batches_overlap(pieces,[cell]):return {"terrain_id":record.uuid,"conservative":true}
		return {}
	var t:Dictionary=record.terrain_mesh;var pose:Transform3D=T.transform(record)
	var available:Array=[];var terrain_bounds:=Geometry.bounds([record])
	for piece:Dictionary in pieces:
		if piece.bounds.grow(.01).intersects(terrain_bounds.grow(.01)):available.append(piece)
	if available.is_empty():return {}
	for z in int(t.rows):
		for x in int(t.columns):
			if not T.solid(t,x,z):continue
			var corners:Array=T.cell(record,x,z).map(func(p):return pose*p)
			var top:float=corners.map(func(p):return p.y).max()
			if supporting_ground(record,top,support_height):continue
			var cell_bounds:=AABB(corners[0],Vector3.ZERO)
			for p:Vector3 in corners:cell_bounds=cell_bounds.expand(p)
			var floor_y:float=pose.origin.y+float(t.floor)*record.size[1]
			cell_bounds.position.y=floor_y;cell_bounds.size.y=top-floor_y
			for piece:Dictionary in available:
				if not piece.bounds.grow(.01).intersects(cell_bounds.grow(.01)):continue
				var footprint:Array=[]
				for p:Vector2 in piece.polygon:footprint.append(p)
				if footprint.size()>1 and footprint[0]==footprint[-1]:footprint.pop_back()
				for ids in [[0,1,2],[0,2,3]]:
					var triangle:Array=ids.map(func(i):return Vector2(corners[i].x,corners[i].z))
					var overlap:Array=Clip.intersection(footprint,triangle)
					if overlap.size()<3 or Poly.area(overlap)<1e-9:continue
					var p:Vector3=corners[ids[0]];var normal:Vector3=(corners[ids[1]]-p).cross(corners[ids[2]]-p)
					for at:Vector2 in overlap:
						var y:=float(p.y)-(float(normal.x)*(float(at.x)-p.x)+float(normal.z)*(float(at.y)-p.z))/normal.y
						if supporting_ground(record,y,support_height):continue
						# Match the existing shape-overlap contact tolerance.
						if y<=piece.bounds.position.y+.01 or floor_y>=piece.bounds.end.y-.01:continue
						return {"terrain_id":record.uuid,"part":piece.get("part",""),"cell":[x,z],"position":[at.x,y,at.y],"support_height":support_height}
	return {}

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
		# Preserve oriented component corners. An intermediate world AABB fills
		# empty corners of a rotated house and incorrectly blocks nearby roads.
		var points: Array[Vector3]=[]
		for record in group:
			for point:Vector3 in Geometry.corners(record):points.append(origin+basis*point)
			if not record.has("fixture"): continue
			var closed:=Transform3D(Basis.from_euler(Geometry.vector(record,"rotation")*PI/180),Geometry.vector(record,"position"))
			var pivot: Vector3=closed*Vector3(record.fixture.pivot[0],record.fixture.pivot[1],record.fixture.pivot[2])
			var local:=AABB(-Geometry.vector(record,"size")/2,Geometry.vector(record,"size")); var radius:=0.0
			for i in 8:
				var offset:=closed*local.get_endpoint(i)-pivot
				radius=maxf(radius,Vector2(offset.x,offset.z).length())
			# A circumscribed circle reserves every hinge angle, independent of
			# building orientation; no part of the old full sweep is discarded.
			var sweep_radius:=radius/cos(PI/16.0)
			for step in 16:
				var angle:=TAU*step/16.0
				points.append(origin+basis*(pivot+Vector3(cos(angle)*sweep_radius,0,sin(angle)*sweep_radius)))
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
