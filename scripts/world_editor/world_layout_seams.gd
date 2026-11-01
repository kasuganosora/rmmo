extends RefCounted
## Read-only authoring evidence from native records. Never a traversal ticket.
const Geometry = preload("res://scripts/world3d/world_layout_geometry.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Snapshot = preload("res://scripts/world3d/document_source_snapshot.gd")
const Cursor = preload("res://scripts/world3d/document_open_cursor.gd")
const Resources = preload("res://scripts/world3d/map_resource_store.gd")
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Furrows = preload("res://scripts/world3d/terrain_furrows.gd")
const Regions = preload("res://scripts/world3d/terrain_regions.gd")
const TOLERANCE_M := 0.001
## Sampling topology needs much tighter, scale-relative agreement than height.
const SAMPLING_RELATIVE_TOLERANCE := 0.000000001
const SAMPLING_MIN_TOLERANCE_M := 0.000000000001
const MAX_SAMPLES := 8192
const MAX_RECORDS := 25000
const MAX_SOURCE_BYTES := 64 * 1024 * 1024

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok":false,"reason_code":code,"message":message,"diagnostics":[]}

static func inspect(layout: Dictionary, bindings: Array, root: String, space_id: String = "", seam_id: String = "") -> Dictionary:
	var checked := Geometry.validate(layout)
	if not checked.ok: return checked
	var sources := {}
	var inputs := []
	var diagnostics: Array = checked.diagnostics.duplicate(true)
	var seams: Array = []
	var selected_space := false
	var selected_seam := false
	var sample_count := 0
	for space: Dictionary in checked.layout.spaces:
		if not space_id.is_empty() and space.id != space_id: continue
		selected_space = true
		for seam: Dictionary in space.seams:
			if not seam_id.is_empty() and seam.id != seam_id: continue
			selected_seam = true
			var placements := {}
			for p: Dictionary in space.placements: placements[p.id] = p
			var records := {}
			for side: Dictionary in [seam.a,seam.b]:
				var binding: Dictionary = {}
				for candidate: Dictionary in bindings:
					if candidate.space_id == space.id and candidate.placement_id == side.placement_id: binding = candidate; break
				if binding.is_empty(): return _fail("map_unavailable","接缝地图缺少已验证的来源绑定。")
				if not sources.has(binding.path):
					var loaded := _read(binding,root)
					if not loaded.ok: return loaded
					sources[binding.path] = loaded
					inputs.append({"path":binding.path,"map_sha":loaded.signature,"dependencies":loaded.dependencies})
				records[side.placement_id] = sources[binding.path].records
			var result := compare(space.id,seam,placements,records)
			if not result.ok: return result
			sample_count += result.samples
			if sample_count > MAX_SAMPLES: return _fail("seam_limit","接缝采样超出预算，请按空间或接缝分别检查。")
			seams.append(result)
			diagnostics.append_array(result.diagnostics)
	if not selected_space: return _fail("space_not_found","指定连续空间不存在。")
	if not seam_id.is_empty() and not selected_seam: return _fail("seam_not_found","指定接缝不存在。")
	# Reobserve both map bytes and immutable definitions before publishing evidence.
	for path: String in sources:
		var source: Dictionary = sources[path]
		if not Paths.allowed(path,root) or not source.snapshot.matches_disk(): return _fail("map_revision_changed","检查期间地图发生变化，报告已废弃。")
		if not Resources.verify_dependencies(source.dependencies,path,root,1): return _fail("map_revision_changed","检查期间原生资源发生变化，报告已废弃。")
	return {"ok":true,"diagnostics":diagnostics,"seams":seams,"inputs":inputs,"samples":sample_count,
		"report_id":JSON.stringify([checked.layout,inputs],"",true,true).sha256_text(),"scope":"saved_native_heightfield_edges",
		"heightfields_match":not seams.is_empty() and seams.all(func(row):return row.heightfields_match),
		"can_transfer":false,"continuous_ready":false,"unverified_checks":["bridge_or_mesh_support","capsule_clearance","normals_material_water","runtime_physics","navigation"],
		"message":"只检查作者布局与原生高度场边界；通行、桥面、材质和运行发布仍须后续验证。"}

static func _read(binding: Dictionary, root: String) -> Dictionary:
	var path: String = binding.path
	if not Paths.allowed(path,root): return _fail("path_not_allowed","接缝来源不在允许的资源根。")
	var snapshot := Snapshot.read_file(path,MAX_SOURCE_BYTES,MAX_SOURCE_BYTES)
	if not snapshot.error.is_empty(): return _fail("map_unavailable","无法在有界预算内读取接缝地图。")
	var expected: String = binding.get("source_sha",binding.get("map_sha",""))
	if expected.is_empty() or snapshot._signature != expected: return _fail("map_revision_changed","地图来源修订已变化，请刷新布局。")
	var index := Cursor.native_root(snapshot._data)
	if index < 0: return _fail("seam_source_unsupported","高度场诊断需要当前原生引用地图；不会隐式迁移旧文件。")
	var extra: Dictionary = snapshot._data.nodes[index].extras
	if extra.rmmo_records.size() > MAX_RECORDS: return _fail("seam_limit","地图记录超过接缝读取预算。")
	var total_bytes := 0
	for row: Variant in extra.rmmo_records:
		if not row is Dictionary or not row.get("rmmo_ref") is Dictionary: return _fail("seam_source_unsupported","原生地图记录无效。")
		var length: Variant = row.rmmo_ref.get("length")
		if not (length is int or length is float) or not is_finite(float(length)) or length < 0 or length > MAX_SOURCE_BYTES: return _fail("seam_limit","原生定义超出接缝读取预算。")
		total_bytes += int(length)
		if total_bytes > MAX_SOURCE_BYTES: return _fail("seam_limit","原生定义总量超出接缝读取预算。")
	var loaded := Cursor.hydrate_references(extra,path,root,1,false)
	if not loaded.ok: return _fail("map_dependencies_invalid",str(loaded.get("reason","地图依赖验证失败。")))
	if not Paths.allowed(path,root) or not snapshot.matches_disk(): return _fail("map_revision_changed","地图读取期间发生变化。")
	return {"ok":true,"records":loaded.extras.rmmo_records,"dependencies":loaded.dependencies,"signature":snapshot._signature,"snapshot":snapshot}

## Pure numerical seam inspection, also used by regression without scene loads.
static func compare(space_id: String, seam: Dictionary, placements: Dictionary, records: Dictionary) -> Dictionary:
	var pa: Dictionary = placements[seam.a.placement_id]
	var pb: Dictionary = placements[seam.b.placement_id]
	var axis := 2 if str(seam.a.edge).begins_with("x") else 0
	# Keep tangent samples near the first map origin. Adding a large world origin
	# before comparing a small grid would discard precisely the detail we check.
	var reference: float = pa.origin_m[axis]
	var a := _edge(pa,seam.a,records[pa.id],reference)
	var b := _edge(pb,seam.b,records[pb.id],reference)
	var cross_delta: float = (float(pa.origin_m[2-axis])-float(pb.origin_m[2-axis]))+(float(a.at)-float(b.at))
	var knots: Array = [a.start,a.end]
	for edge: Dictionary in [a,b]:
		for endpoint: float in [edge.start,edge.end]:
			if endpoint > a.start and endpoint < a.end: knots.append(endpoint)
		for part: Dictionary in edge.parts:
			for endpoint: float in [part.low,part.high]:
				if endpoint > a.start and endpoint < a.end: knots.append(endpoint)
			for i in part.count + 1:
				var value: float = part.low + i * part.step
				if value > a.start and value < a.end: knots.append(value)
			if knots.size() > MAX_SAMPLES: return _fail("seam_limit","单条接缝采样超出预算。")
	knots.sort()
	var unique: Array = []
	for value: float in knots:
		# Never merge a small real uncovered interval into its neighbour.
		if unique.is_empty() or value != float(unique.back()): unique.append(value)
	if unique.size()*2 > MAX_SAMPLES: return _fail("seam_limit","单条接缝采样超出预算。")
	var points: Array = unique.duplicate()
	for i in unique.size()-1: points.append((float(unique[i])+float(unique[i+1]))*.5)
	points.sort()
	var diagnostics: Array = []
	var max_delta := 0.0
	var mismatch := false
	var codes := {}
	for value: float in points:
		var left := _sample(a,value)
		var right := _sample(b,value)
		var code := ""
		var message := ""
		if not left.ok or not right.ok or cross_delta != 0.0:
			code = "terrain_support_unverified"
			message = "此位置未验证连续的原生高度场外边界：只支持与声明边界实际重合的唯一实心外边，不支持内部截线、重复覆盖、洞口、旋转或耕垄；不以高度容差扩张覆盖。"
			if cross_delta != 0.0: message = "两侧原生外边界不在同一条空间直线上，布局的 1 mm 比较容差不会填补真实间隙或自动吸附。"
		else:
			var delta := _height_delta(left,right)
			max_delta = maxf(max_delta,delta)
			if not _sampling_matches(left,right):
				code = "terrain_sampling_mismatch"; message = "两侧采样间距或相位不同，需要显式重采样或过渡设计。"
			elif delta > TOLERANCE_M:
				code = "terrain_height_mismatch"; message = "两侧边界高度不一致，未自动取平均。"
		if code.is_empty(): continue
		mismatch = true
		# Bounded actionable examples; preserve aggregate max delta over all samples.
		if int(codes.get(code,0)) >= 4: continue
		codes[code] = int(codes.get(code,0)) + 1
		var along_world := reference+value
		var local_a := [a.at,float(left.get("local_height",0.0)),value] if axis==2 else [value,float(left.get("local_height",0.0)),a.at]
		var along_b := (reference-float(pb.origin_m[axis]))+value
		var local_b := [b.at,float(right.get("local_height",0.0)),along_b] if axis==2 else [along_b,float(right.get("local_height",0.0)),b.at]
		var world := [a.constant,float(left.get("height",pa.origin_m[1])),along_world] if axis==2 else [along_world,float(left.get("height",pa.origin_m[1])),a.constant]
		var world_b := [b.constant,float(right.get("height",pb.origin_m[1])),along_world] if axis==2 else [along_world,float(right.get("height",pb.origin_m[1])),b.constant]
		diagnostics.append({"code":code,"severity":"warning" if code=="terrain_support_unverified" else "error","message":message,"space_id":space_id,"seam_id":seam.id,"placement_ids":[pa.id,pb.id],"local_a_m":local_a,"local_b_m":local_b,"space_position_m":world,"space_a_m":world,"space_b_m":world_b,"height_a_m":left.get("height"),"height_b_m":right.get("height"),"tolerance_m":TOLERANCE_M,"sampling_tolerance_m":_sampling_tolerance(float(left.get("step",0.0)),float(right.get("step",0.0))),"horizontal_offset_m":cross_delta,"coverage_a":left.get("reason_code","native_outer_edge"),"coverage_b":right.get("reason_code","native_outer_edge"),"excluded_a":a.excluded,"excluded_b":b.excluded})
	return {"ok":true,"space_id":space_id,"seam_id":seam.id,"heightfields_match":not mismatch,"samples":points.size(),"max_height_delta_m":max_delta,"diagnostics":diagnostics,"can_transfer":false}

static func _edge(placement: Dictionary, side: Dictionary, records: Array, reference: float) -> Dictionary:
	var x_edge: bool = str(side.edge).begins_with("x")
	var axis := 2 if x_edge else 0
	var cross := 0 if x_edge else 2
	var bounds: Array = placement.ownership_xz_m
	var at: float = bounds[(0 if side.edge=="x_min" else 2) if x_edge else (1 if side.edge=="z_min" else 3)]
	var shift: float = float(placement.origin_m[axis])-reference
	var positive := str(side.edge).ends_with("max")
	var result := {"axis":axis,"at":at,"constant":float(placement.origin_m[cross])+at,"start":shift+float(side.interval_m[0]),"end":shift+float(side.interval_m[1]),"parts":[],"excluded":{}}
	for item: Variant in records:
		if not item is Dictionary: _exclude(result,"invalid_record"); continue
		var record: Dictionary = item
		if not record.has("terrain_mesh"): continue
		if record.has("terrain_volume") or not Terrain.valid(record): _exclude(result,"invalid_heightfield"); continue
		if not record.get("position") is Array or record.position.size()!=3 or not record.get("rotation") is Array or record.rotation.size()!=3: _exclude(result,"invalid_transform"); continue
		if not record.rotation.all(func(v):return (v is int or v is float) and is_finite(float(v)) and float(v)==0.0): _exclude(result,"unsupported_rotation"); continue
		if not record.position.all(func(v):return (v is int or v is float) and is_finite(float(v)) and absf(float(v))<=1000000000000.0): _exclude(result,"invalid_transform"); continue
		# Hydration checks byte closure, not every optional record schema. Validate
		# regions before Furrows.maximum_height follows nested dictionaries.
		if not Regions.valid(record): _exclude(result,"invalid_terrain_regions"); continue
		if Furrows.maximum_height(record)!=0.0: _exclude(result,"unsupported_furrows"); continue
		var low_cross: float = float(record.position[cross])-float(record.size[cross])*.5
		var high_cross: float = float(record.position[cross])+float(record.size[cross])*.5
		if at != (high_cross if positive else low_cross):
			_exclude(result,"interior_cut_unsupported" if at>low_cross and at<high_cross else "native_outer_edge_not_coincident")
			continue
		var low: float = shift+(float(record.position[axis])-float(record.size[axis])*.5)
		var high: float = shift+(float(record.position[axis])+float(record.size[axis])*.5)
		if high<=result.start or low>=result.end: continue
		var count: int = int(record.terrain_mesh.rows if x_edge else record.terrain_mesh.columns)
		result.parts.append({"record":record,"origin_y":float(placement.origin_m[1]),"positive":positive,"low":low,"high":high,"count":count,"step":float(record.size[axis])/count})
	return result

static func _exclude(edge: Dictionary, reason: String) -> void:
	edge.excluded[reason] = int(edge.excluded.get(reason,0))+1

static func _sampling_tolerance(a: float, b: float) -> float:
	return maxf(SAMPLING_MIN_TOLERANCE_M,minf(absf(a),absf(b))*SAMPLING_RELATIVE_TOLERANCE)

static func _sampling_matches(a: Dictionary, b: Dictionary) -> bool:
	var tolerance := _sampling_tolerance(a.step,b.step)
	if absf(float(a.step)-float(b.step)) > tolerance: return false
	var delta: float = float(a.phase)-float(b.phase)
	return absf(delta-roundf(delta/float(a.step))*float(a.step)) <= tolerance

static func _height_delta(a: Dictionary, b: Dictionary) -> float:
	return absf((float(a.origin_y)-float(b.origin_y))+(float(a.local_height)-float(b.local_height)))

static func _sample(edge: Dictionary, value: float) -> Dictionary:
	if value<edge.start or value>edge.end: return {"ok":false,"reason_code":"outside_declared_interval"}
	var found: Array = []
	var hole := false
	for part: Dictionary in edge.parts:
		if value<part.low or value>part.high: continue
		var r: Dictionary = part.record
		var t: Dictionary = r.terrain_mesh
		var along: float = (value-float(part.low))/float(part.step)
		if value==part.low: along=0.0
		if value==part.high: along=float(part.count)
		var other: float = float(t.columns if edge.axis==2 else t.rows) if part.positive else 0.0
		var u: float = other if edge.axis==2 else along
		var v: float = along if edge.axis==2 else other
		var x := clampi(int(floorf(u)),0,int(t.columns)-1)
		var z := clampi(int(floorf(v)),0,int(t.rows)-1)
		if not Terrain.solid(t,x,z): hole=true; continue
		var fu := u-x; var fv := v-z; var stride := int(t.columns)+1
		var h00: float = t.heights[z*stride+x]; var h10: float = t.heights[z*stride+x+1]
		var h11: float = t.heights[(z+1)*stride+x+1]; var h01: float = t.heights[(z+1)*stride+x]
		var height := h00+(h10-h00)*fu+(h11-h10)*fv if fu>=fv else h00+(h11-h01)*fu+(h01-h00)*fv
		var local_height := float(r.position[1])+height*float(r.size[1])
		found.append({"ok":true,"height":float(part.origin_y)+local_height,"local_height":local_height,"origin_y":part.origin_y,"step":part.step,"phase":part.low,"low":part.low,"high":part.high})
	if found.is_empty(): return {"ok":false,"reason_code":"native_hole" if hole else "no_native_outer_edge"}
	for i in found.size():
		for j in i:
			# Equal coplanar records are still ambiguous ownership. Only a shared
			# tile endpoint may legitimately contribute two agreeing samples.
			if minf(found[i].high,found[j].high)>maxf(found[i].low,found[j].low): return {"ok":false,"reason_code":"overlapping_native_edges"}
		if _height_delta(found[i],found[0])>TOLERANCE_M or not _sampling_matches(found[i],found[0]): return {"ok":false,"reason_code":"incompatible_tile_endpoint"}
	return found[0]
