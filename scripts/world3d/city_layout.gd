extends RefCounted
## Layout metadata. Helpers remain editor-only; generated pavement lives in records.
const S = preload("res://scripts/world3d/document_schema.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")

static func object(properties: Dictionary, required: Array = []) -> Dictionary:
	return {"type":"object", "properties":properties, "required":required, "additionalProperties":false}
static func text(limit: int = 80) -> Dictionary:
	return {"type":"string", "maxLength":limit}
static func array(items: Dictionary, maximum: int, minimum: int = 0) -> Dictionary:
	return {"type":"array", "items":items, "minItems":minimum, "maxItems":maximum}
static func choice(values: Array) -> Dictionary:
	return {"type":"string", "enum":values}
static func v2() -> Dictionary:
	return array(S.number(0,4096),2,2)
static func camera_schema() -> Dictionary:
	return object({"projection":choice(["top","perspective"]), "center":S.vector(-100000,100000), "distance":S.number(2,10000), "span":S.number(2,10000), "yaw":S.number(-180,180), "pitch":S.number(-89,-5)})
static func reference_schema() -> Dictionary:
	return object({"path":text(2048), "pixel_size":array(S.number(1,4096,true),2,2), "center":S.vector(-100000,100000), "meters_per_pixel":S.number(.001,100), "yaw":S.number(-180,180), "opacity":S.number(0,1), "visible":{"type":"boolean"}, "locked":{"type":"boolean"}}, ["path","pixel_size","center","meters_per_pixel","yaw","opacity","visible","locked"])
static func node_schema() -> Dictionary:
	return object({"id":text(), "position":S.vector(-100000,100000), "locked":{"type":"boolean"}, "hidden":{"type":"boolean"}}, ["id","position"])
static func edge_schema() -> Dictionary:
	return object({"id":text(), "from":text(), "to":text(), "name":text(120), "width_start":S.number(1,60), "width_end":S.number(1,60), "kind":choice(["ground","bridge"]), "controls":array(S.vector(-100000,100000),2,2), "stone_bridge":object({"id":text(100),"start":S.vector(-10000,10000),"end":S.vector(-10000,10000),"width":S.number(3,16),"signature":text(64),"source_token":text(64)},["id","start","end","width","signature","source_token"]), "bridge_ref":object({"waterway_id":text(),"bridge_id":text()},["waterway_id","bridge_id"]), "locked":{"type":"boolean"}, "hidden":{"type":"boolean"}}, ["id","from","to","width_start","width_end","kind"])
static func graph_schema() -> Dictionary:
	return object({"nodes":array(node_schema(),256), "edges":array(edge_schema(),512)}, ["nodes","edges"])
static func schema() -> Dictionary:
	var properties := {"version":S.number(1,1,true), "roads":graph_schema(), "bookmarks":array(object({"id":text(),"name":text(80),"camera":camera_schema()},["id","name","camera"]),32), "reference":reference_schema()}
	properties.zones=array(preload("res://scripts/world3d/planning_zones.gd").schema(),128)
	properties.vegetation=preload("res://scripts/world3d/vegetation_scatter.gd").manifest_schema()
	properties.waterways=preload("res://scripts/world3d/waterway_data.gd").manifest_schema()
	properties.fortifications=preload("res://scripts/world3d/fortification_data.gd").manifest_schema()
	properties.block_layout=object({"version":S.number(1,1,true),"settings":object({"lot_width":S.number(8,32),"lot_depth":S.number(12,40),"setback":S.number(.5,10),"gap":S.number(.5,8),"style":choice(["medieval","urban_village","standard"]),"seed":S.number(0,2147483647,true),"max_buildings":S.number(1,16,true)},["lot_width","lot_depth","setback","gap","style","seed","max_buildings"]),"lots":array(object({"lot_id":text(80),"block_id":text(80),"building_id":text(80),"source_token":text(64)},["lot_id","block_id","building_id","source_token"]),4096)},["version","settings","lots"])
	properties.road_surface=object({"version":S.number(1,1,true),"graph_token":text(64),"settings":object({"thickness":S.number(.1,.5),"lift":S.number(.005,.05),"clearance":S.number(2.5,10),"material_id":text(256)}.merged(preload("res://scripts/world3d/road_kerb.gd").settings()),["thickness","lift","clearance","material_id"]),"parts":array(object({"key":text(100),"id":text(100),"signature":text(64),"paint_signature":text(64)},["key","id","signature","paint_signature"]),4096)},["version","graph_token","settings","parts"])
	return object(properties,["version","roads","bookmarks"])
static func defaults() -> Dictionary:
	return {"version":1, "roads":{"nodes":[],"edges":[]}, "bookmarks":[]}
static func resolve(meta: Dictionary) -> Dictionary:
	return meta.get("editor_layout",defaults()).duplicate(true)
static func vec(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])
static func xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
static func fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}
static func valid_id(value: String) -> bool:
	return not value.is_empty() and value.is_valid_identifier()
static func valid(meta: Dictionary) -> bool:
	if not meta.has("editor_layout"): return true
	var data: Variant = meta.editor_layout
	if not S.validate(data,schema()).is_empty(): return false
	if not preload("res://scripts/world3d/planning_zones.gd").valid(data.get("zones",[])): return false
	if not preload("res://scripts/world3d/vegetation_scatter.gd").valid(data.get("vegetation",[])): return false
	if not preload("res://scripts/world3d/waterway_data.gd").valid(data.get("waterways",[])): return false
	if not preload("res://scripts/world3d/fortification_data.gd").valid(data.get("fortifications",[])): return false
	if data.has("block_layout"):
		var lots:={}; var buildings:={}
		for lot in data.block_layout.lots:
			if not valid_id(lot.lot_id) or not valid_id(lot.block_id) or not valid_id(lot.building_id) or lot.source_token.length()!=64 or lots.has(lot.lot_id) or buildings.has(lot.building_id): return false
			lots[lot.lot_id]=true; buildings[lot.building_id]=true
	if data.has("road_surface"):
		if data.road_surface.graph_token.length()!=64: return false
		var keys:={}; var members:={}
		for part in data.road_surface.parts:
			if not valid_id(part.key) or not valid_id(part.id) or keys.has(part.key) or members.has(part.id): return false
			if part.signature.length()!=64 or part.paint_signature.length()!=64: return false
			keys[part.key]=true; members[part.id]=true
	if data.has("reference"):
		var ref: Dictionary = data.reference
		if not Paths.allowed(ref.path) or ref.path.get_extension().to_lower() != "png": return false
		if maxf(ref.pixel_size[0],ref.pixel_size[1])*ref.meters_per_pixel > 10000: return false
	var ids := {}
	for b in data.bookmarks:
		if not valid_id(b.id) or ids.has(b.id) or str(b.name).strip_edges().is_empty(): return false
		ids[b.id] = true
		for field in camera_schema().properties:
			if not b.camera.has(field): return false
	return analyze(data.roads).ok and preload("res://scripts/world3d/road_bridges.gd").resolve(data).ok

static func canonical(value: Variant) -> Variant:
	# Integer microunits make JSON roundtrips stable without trusting float spelling.
	if value is float or value is int: return "number:"+str(roundi(float(value)*1000000))
	if value is Array: return value.map(func(item):return canonical(item))
	if value is Dictionary:
		var result:={}
		for key in value: result[key]=canonical(value[key])
		return result
	return value
static func token(graph: Variant) -> String:
	return JSON.stringify(canonical(graph)).sha256_text()

static func samples(edge: Dictionary, nodes: Dictionary) -> Array[Vector3]:
	var a := vec(nodes[edge.from].position); var b := vec(nodes[edge.to].position)
	if not edge.has("controls"): return [a,b]
	var c := vec(edge.controls[0]); var d := vec(edge.controls[1])
	# The graph stores exact cubic handles. Sampling is only for its editor guide/diagnostics.
	var steps := clampi(ceili((a.distance_to(c)+c.distance_to(d)+d.distance_to(b))/8.0),16,128)
	var result: Array[Vector3] = []
	for i in steps+1: result.append(a.bezier_interpolate(c,d,b,float(i)/steps))
	return result

static func analyze(graph: Dictionary) -> Dictionary:
	var issue := S.validate(graph,graph_schema(),"roads")
	if not issue.is_empty(): return fail(issue)
	var nodes := {}; var edges := {}; var pairs := {}; var paths := {}; var warnings: Array = []
	for node in graph.nodes:
		if not valid_id(node.id) or nodes.has(node.id): return fail("道路节点 ID 无效或重复")
		nodes[node.id] = node
	for edge in graph.edges:
		if not valid_id(edge.id) or edges.has(edge.id): return fail("道路线段 ID 无效或重复")
		if not nodes.has(edge.from) or not nodes.has(edge.to) or edge.from == edge.to: return fail("道路线段端点缺失或为同一节点")
		var endpoints: Array = [edge.from,edge.to]; endpoints.sort()
		var pair := str(endpoints)
		if pairs.has(pair): return fail("相同端点已有线段；请在中途增加节点以区分分支")
		pairs[pair] = true; edges[edge.id] = edge
		var points := samples(edge,nodes); var length_ := 0.0; var grade := 0.0
		for i in points.size()-1:
			var delta := points[i+1]-points[i]; var horizontal := Vector2(delta.x,delta.z).length()
			if horizontal < .05: return fail("道路包含小于 5 厘米的平面线段或退化曲线："+edge.id)
			length_ += delta.length(); grade = maxf(grade,absf(delta.y)/horizontal)
		if length_ < .5: return fail("道路线段必须至少长 0.5 米")
		if grade > .15: warnings.append({"code":"steep_grade","edge_id":edge.id,"grade":grade})
		paths[edge.id] = points
	# A spatial hash bounds the broad phase; intersections are diagnostic, never silent joins.
	var segments: Array = []; var buckets := {}; var checked := {}; var warnings_seen := {}
	for edge in graph.edges:
		var points: Array = paths[edge.id]
		for i in points.size()-1:
			var a: Vector3 = points[i]; var b: Vector3 = points[i+1]
			# Long straight lines are partitioned for the diagnostic broad phase only.
			var pieces := maxi(1,ceili(a.distance_to(b)/32.0))
			if segments.size()+pieces > 16384: return fail("道路采样超过 16384 段，请按区域分批规划")
			for j in pieces:
				var segment := {"a":a.lerp(b,float(j)/pieces), "b":a.lerp(b,float(j+1)/pieces),"edge":edge,"part":i,"index":segments.size()}
				segments.append(segment)
				var lo: Vector3 = segment.a.min(segment.b); var hi: Vector3 = segment.a.max(segment.b)
				for x in range(floori(lo.x/64),floori(hi.x/64)+1):
					for z in range(floori(lo.z/64),floori(hi.z/64)+1):
						var key := Vector2i(x,z)
						if not buckets.has(key): buckets[key] = []
						for other in buckets[key]:
							var pair_key := Vector2i(other.index,segment.index)
							if checked.has(pair_key): continue
							checked[pair_key] = true
							if checked.size() > 1000000: return fail("道路局部过密，交叉检查超过预算，请拆分规划")
							_intersection(other,segment,nodes,warnings,warnings_seen)
						buckets[key].append(segment)
	return {"ok":true,"nodes":nodes,"paths":paths,"diagnostics":warnings,"sample_segments":segments.size()}

static func _intersection(a: Dictionary, b: Dictionary, nodes: Dictionary, warnings: Array, seen: Dictionary) -> void:
	if a.edge.id == b.edge.id and absi(a.index-b.index) <= 1: return
	var p := Vector2(a.a.x,a.a.z); var r := Vector2(a.b.x-a.a.x,a.b.z-a.a.z)
	var q := Vector2(b.a.x,b.a.z); var s := Vector2(b.b.x-b.a.x,b.b.z-b.a.z)
	var det := r.cross(s)
	if absf(det) < .00001:
		if a.edge.id == b.edge.id or absf((q-p).cross(r)) > .001*r.length(): return
		var t0 := (q-p).dot(r)/r.length_squared(); var t1 := (q+s-p).dot(r)/r.length_squared()
		if minf(1,maxf(t0,t1))-maxf(0,minf(t0,t1)) > .001:
			var overlap_key := str([a.edge.id,b.edge.id,"overlap"])
			if not seen.has(overlap_key):
				var mid: float=(maxf(0,minf(t0,t1))+minf(1,maxf(t0,t1)))*.5
				var at: Vector3=a.a.lerp(a.b,mid)
				var on_b: float=clampf((Vector2(at.x,at.z)-q).dot(s)/s.length_squared(),0,1)
				var dy:=absf(at.y-b.a.lerp(b.b,on_b).y)
				var code:="grade_separated_crossing" if dy>.5 and (a.edge.kind=="bridge" or b.edge.kind=="bridge") else "overlapping_centerlines"
				warnings.append({"code":code,"edges":[a.edge.id,b.edge.id],"position":xyz(at),"height_difference":dy}); seen[overlap_key] = true
		return
	var t := (q-p).cross(s)/det; var u := (q-p).cross(r)/det
	if t < -.00001 or t > 1.00001 or u < -.00001 or u > 1.00001: return
	var point: Vector3 = a.a.lerp(a.b,t); var other: Vector3 = b.a.lerp(b.b,u)
	for id in [a.edge.from,a.edge.to]:
		if id in [b.edge.from,b.edge.to] and point.distance_to(vec(nodes[id].position)) < .02: return
	var separated := absf(point.y-other.y) > .5
	var code := "grade_separated_crossing" if separated and (a.edge.kind=="bridge" or b.edge.kind=="bridge") else ("height_conflict" if separated else "unconnected_crossing")
	if a.edge.id == b.edge.id: code = "self_crossing"
	var key := str([a.edge.id,b.edge.id,roundi(point.x*10),roundi(point.z*10)])
	if seen.has(key): return
	seen[key] = true
	warnings.append({"code":code,"edges":[a.edge.id,b.edge.id],"position":xyz(point),"height_difference":absf(point.y-other.y)})
