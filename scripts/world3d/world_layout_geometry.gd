extends RefCounted
## Pure author-layout geometry. No scene, file, surface or entry authority.
const Address = preload("res://scripts/world3d/world_address.gd")
const MAX_SPACES := 32
const MAX_PLACEMENTS := 128
const MAX_SEAMS := 256
const SEAM_POSITION_TOLERANCE_M := 0.001
const EDGES := ["x_min", "x_max", "z_min", "z_max"]
const OPPOSITE := {"x_min": "x_max", "x_max": "x_min", "z_min": "z_max", "z_max": "z_min"}


static func validate(layout: Dictionary) -> Dictionary:
	var shape := _fields(layout, ["schema_version", "world_key", "units", "up_axis", "spaces"], [], "layout")
	if not shape.ok: return shape
	if not _numeric(layout.schema_version) or float(layout.schema_version) != 1.0:
		return _fail("invalid_layout", "仅支持世界布局 schema_version 1。", "schema_version")
	if not _id(layout.world_key) or not layout.units is String or not layout.up_axis is String or layout.units != "meters" or layout.up_axis != "Y":
		return _fail("invalid_layout", "世界标识、米制单位或 Y 轴约定无效。", "layout")
	if not layout.spaces is Array or layout.spaces.is_empty() or layout.spaces.size() > MAX_SPACES:
		return _fail("layout_limit_exceeded", "spaces 必须为包含 1–32 个空间的数组。", "spaces")
	var normalized := {"schema_version": 1, "world_key": layout.world_key, "units": "meters", "up_axis": "Y", "spaces": []}
	var space_ids := {}; var placement_count := 0; var seam_count := 0
	var diagnostics: Array = []
	for index in layout.spaces.size():
		var path := "spaces[%d]" % index
		var source: Variant = layout.spaces[index]
		if not source is Dictionary: return _fail("invalid_layout", "空间必须是对象。", path)
		shape = _fields(source, ["id", "placements", "seams"], [], path)
		if not shape.ok: return shape
		if not _id(source.id): return _fail("invalid_layout", "空间 ID 无效。", path + ".id")
		if space_ids.has(source.id): return _fail("duplicate_space", "空间 ID 重复。", path + ".id", {"space_id": source.id})
		space_ids[source.id] = true
		if not source.placements is Array or not source.seams is Array:
			return _fail("invalid_layout", "placements 和 seams 必须是数组。", path, {"space_id": source.id})
		placement_count += source.placements.size(); seam_count += source.seams.size()
		if placement_count > MAX_PLACEMENTS or seam_count > MAX_SEAMS:
			return _fail("layout_limit_exceeded", "布局最多包含 128 个放置和 256 条接缝。", path)
		var space := {"id": source.id, "placements": [], "seams": []}
		var placements := {}; var maps := {}; var seam_ids := {}
		for pi in source.placements.size():
			var pp := path + ".placements[%d]" % pi
			var raw: Variant = source.placements[pi]
			if not raw is Dictionary: return _fail("invalid_layout", "地图放置必须是对象。", pp)
			shape = _fields(raw, ["id", "pack_id", "map_number", "origin_m", "ownership_xz_m"], ["pack_version"], pp)
			if not shape.ok: return shape
			if not _id(raw.id) or not _id(raw.pack_id) or not raw.map_number is String:
				return _fail("invalid_layout", "放置 ID、资源包 ID 或字符串地图编号无效。", pp)
			if raw.has("pack_version") and not _version(raw.pack_version):
				return _fail("invalid_layout", "包版本必须是非空且不含控制字符的短字符串。", pp + ".pack_version")
			var number := Address.normalize_number(raw.map_number)
			if not number.ok: return _fail(number.reason_code, number.message, pp + ".map_number")
			var key: String = raw.pack_id + ":" + number.map_number
			if placements.has(raw.id): return _fail("duplicate_placement", "同一空间的放置 ID 重复。", pp, {"space_id": source.id, "placement_ids": [raw.id]})
			if maps.has(key): return _fail("duplicate_map_placement", "同一空间只能放置同一地图一次。", pp, {"space_id": source.id, "placement_ids": [maps[key], raw.id]})
			var origin := _numbers(raw.origin_m, 3, pp + ".origin_m")
			if not origin.ok: return origin
			var bounds := _numbers(raw.ownership_xz_m, 4, pp + ".ownership_xz_m")
			if not bounds.ok: return bounds
			if bounds.values[2] <= bounds.values[0] or bounds.values[3] <= bounds.values[1]:
				return _fail("invalid_ownership", "地图归属矩形必须有正宽度和正长度。", pp + ".ownership_xz_m", {"space_id": source.id, "placement_ids": [raw.id]})
			var placement := {"id": raw.id, "pack_id": raw.pack_id, "map_number": number.map_number, "origin_m": origin.values, "ownership_xz_m": bounds.values}
			if raw.has("pack_version"): placement.pack_version = raw.pack_version
			var world_rect := _rect(placement)
			for scalar: float in world_rect:
				if not _coordinate(scalar): return _fail("coordinate_out_of_range", "地图平移后的范围超出地址坐标范围。", pp, {"space_id": source.id, "placement_ids": [raw.id]})
			if world_rect[2] <= world_rect[0] or world_rect[3] <= world_rect[1]:
				return _fail("coordinate_precision_loss", "此原点下的地图范围小于可表示精度。", pp, {"space_id": source.id, "placement_ids": [raw.id]})
			placements[raw.id] = placement; maps[key] = raw.id; space.placements.append(placement)
		for si in source.seams.size():
			var sp := path + ".seams[%d]" % si
			var raw: Variant = source.seams[si]
			if not raw is Dictionary: return _fail("invalid_layout", "接缝必须是对象。", sp)
			shape = _fields(raw, ["id", "a", "b", "mode"], [], sp)
			if not shape.ok: return shape
			if not _id(raw.id) or not raw.mode is String or raw.mode != "continuous": return _fail("invalid_layout", "接缝 ID 或连接方式无效。", sp)
			if seam_ids.has(raw.id): return _fail("duplicate_seam", "同一空间的接缝 ID 重复。", sp, {"space_id": source.id, "seam_id": raw.id})
			seam_ids[raw.id] = true
			var seam := {"id": raw.id, "mode": "continuous"}
			for side: String in ["a", "b"]:
				if not raw[side] is Dictionary: return _fail("invalid_layout", "接缝端点描述必须是对象。", sp + "." + side)
				shape = _fields(raw[side], ["placement_id", "edge", "interval_m"], [], sp + "." + side)
				if not shape.ok: return shape
				var endpoint: Dictionary = raw[side]
				if not _id(endpoint.placement_id) or not endpoint.edge is String or not endpoint.edge in EDGES:
					return _fail("invalid_layout", "接缝放置标识或边名无效。", sp + "." + side)
				var interval := _numbers(endpoint.interval_m, 2, sp + "." + side + ".interval_m")
				if not interval.ok: return interval
				if interval.values[1] <= interval.values[0]: return _fail("invalid_seam_interval", "接缝区间必须有正长度。", sp, {"space_id": source.id, "seam_id": raw.id})
				seam[side] = {"placement_id": endpoint.placement_id, "edge": endpoint.edge, "interval_m": interval.values}
			space.seams.append(seam)
		_topology(space, placements, path, diagnostics)
		normalized.spaces.append(space)
	for diagnostic: Dictionary in diagnostics:
		if diagnostic.severity == "error":
			return {"ok": false, "reason_code": diagnostic.code, "message": diagnostic.message, "diagnostics": diagnostics}
	return {"ok": true, "reason_code": "", "message": "布局结构有效；尚未验证实际地形、碰撞或导航。", "diagnostics": diagnostics, "layout": normalized}


static func resolve(layout: Dictionary, address: Dictionary, space_id: String = "", placement_id: String = "") -> Dictionary:
	var checked := validate(layout)
	if not checked.ok: return checked
	if (not space_id.is_empty() and not _id(space_id)) or (not placement_id.is_empty() and not _id(placement_id)):
		return _fail("invalid_context", "空间或放置标识无效。", "context")
	if not address.get("pack_id") is String or not address.get("map_number") is String or not address.get("position_m") is Array:
		return _fail("invalid_address", "地址必须包含字符串包 ID、编号和坐标数组。", "address")
	var point := Address.format_address(address.pack_id, address.map_number, address.position_m)
	if not point.ok: return _fail(point.reason_code, point.message, "address")
	var matches: Array = []
	for space: Dictionary in checked.layout.spaces:
		if not space_id.is_empty() and space.id != space_id: continue
		for placement: Dictionary in space.placements:
			if placement.pack_id == point.pack_id and placement.map_number == point.map_number and (placement_id.is_empty() or placement.id == placement_id):
				matches.append({"space_id": space.id, "placement": placement})
	if matches.is_empty(): return _fail("map_not_in_world", "指定上下文中没有此地图放置。", "address")
	if matches.size() > 1:
		var candidates: Array = []
		for item: Dictionary in matches: candidates.append({"space_id": item.space_id, "placement_id": item.placement.id})
		var result := _fail("ambiguous_context", "此地图位于多个空间，请指定空间或放置。", "context")
		result.candidates = candidates
		return result
	var selected: Dictionary = matches[0]
	if not _contains(selected.placement.ownership_xz_m, point.position_m[0], point.position_m[2]):
		return _fail("outside_ownership", "地址不在所选地图的半开归属范围内。", "address", {"space_id": selected.space_id, "placement_ids": [selected.placement.id], "local_a_m": point.position_m})
	return _resolved(checked.layout.world_key, selected.space_id, selected.placement, point.position_m)


static func locate(layout: Dictionary, space_id: String, space_position_m: Array) -> Dictionary:
	var checked := validate(layout)
	if not checked.ok: return checked
	if not _id(space_id): return _fail("invalid_context", "需要明确有效的空间 ID。", "space_id")
	var point := _numbers(space_position_m, 3, "space_position_m")
	if not point.ok: return point
	var found := false
	for space: Dictionary in checked.layout.spaces:
		if space.id != space_id: continue
		found = true
		for placement: Dictionary in space.placements:
			if _contains(_rect(placement), point.values[0], point.values[2]):
				var local: Array = []
				for axis in 3: local.append(float(point.values[axis]) - float(placement.origin_m[axis]))
				return _resolved(checked.layout.world_key, space_id, placement, local)
	return _fail("outside_ownership" if found else "space_not_found", "此点没有地图归属。" if found else "找不到指定空间。", "space_position_m", {"space_id": space_id, "space_position_m": point.values})


static func _resolved(world_key: String, space_id: String, placement: Dictionary, local: Array) -> Dictionary:
	var address := Address.format_address(placement.pack_id, placement.map_number, local)
	if not address.ok: return _fail(address.reason_code, address.message, "local_position_m")
	var world: Array = []
	for axis in 3:
		var scalar: float = float(placement.origin_m[axis]) + float(local[axis])
		if not _coordinate(scalar): return _fail("coordinate_out_of_range", "转换后的连续空间位置超出地址范围。", "space_position_m")
		world.append(0.0 if scalar == 0.0 else scalar)
	var result := {"ok": true, "reason_code": "", "message": "已解析地图归属；未验证表面或通行。", "diagnostics": [], "world_key": world_key, "space_id": space_id, "placement_id": placement.id, "pack_id": placement.pack_id, "map_number": placement.map_number, "address": address.address, "position_m": address.position_m, "local_position_m": address.position_m.duplicate(), "space_position_m": world, "membership": "inside", "surface_validated": false, "physics_ready": false}
	if placement.has("pack_version"): result.pack_version = placement.pack_version
	return result


static func _topology(space: Dictionary, placements: Dictionary, path: String, diagnostics: Array) -> void:
	for i in space.placements.size():
		var a: Dictionary = space.placements[i]; var ar := _rect(a)
		for j in range(i + 1, space.placements.size()):
			var b: Dictionary = space.placements[j]; var br := _rect(b)
			var overlap := [maxf(ar[0], br[0]), maxf(ar[1], br[1]), minf(ar[2], br[2]), minf(ar[3], br[3])]
			if overlap[0] < overlap[2] and overlap[1] < overlap[3]:
				var at := [overlap[0] + (overlap[2] - overlap[0]) * 0.5, float(a.origin_m[1]), overlap[1] + (overlap[3] - overlap[1]) * 0.5]
				var extra := _point_context(space.id, a, b, at)
				extra.overlap_xz_m = overlap
				diagnostics.append(_diagnostic("ownership_overlap", "error", "同一空间的地图归属范围有正面积重叠。", path, extra))
	var used := {}; var valid_seams: Array = []
	for index in space.seams.size():
		var seam: Dictionary = space.seams[index]; var sp := path + ".seams[%d]" % index
		var base := {"space_id": space.id, "seam_id": seam.id, "placement_ids": [seam.a.placement_id, seam.b.placement_id]}
		if not placements.has(seam.a.placement_id) or not placements.has(seam.b.placement_id) or seam.a.placement_id == seam.b.placement_id:
			diagnostics.append(_diagnostic("invalid_seam_placement", "error", "接缝需要两个存在且不同的地图放置。", sp, base)); continue
		var a: Dictionary = placements[seam.a.placement_id]; var b: Dictionary = placements[seam.b.placement_id]
		var context := _seam_context(space.id, seam, a, b)
		var valid := true
		for side: String in ["a", "b"]:
			var p: Dictionary = a if side == "a" else b
			var bound: Array = p.ownership_xz_m
			var offset := 1 if str(seam[side].edge).begins_with("x_") else 0
			if seam[side].interval_m[0] < bound[offset] or seam[side].interval_m[1] > bound[offset + 2]:
				var detail := context.duplicate(true); detail.side = side
				diagnostics.append(_diagnostic("seam_interval_outside", "error", "接缝区间超出对应地图边界。", sp + "." + side, detail)); valid = false
		if OPPOSITE[seam.a.edge] != seam.b.edge:
			diagnostics.append(_diagnostic("seam_edge_mismatch", "error", "接缝两侧必须是方向相反的同轴边。", sp, context)); valid = false
		elif context.horizontal_error_m > SEAM_POSITION_TOLERANCE_M:
			diagnostics.append(_diagnostic("seam_mismatch", "error", "接缝水平端点不重合。", sp, context)); valid = false
		elif context.horizontal_error_m > 0.0:
			diagnostics.append(_diagnostic("seam_small_offset", "info", "接缝水平端点存在容差内偏移，原坐标保留。", sp, context))
		if not valid: continue
		for side: String in ["a", "b"]:
			var endpoint: Dictionary = seam[side]
			var key: String = endpoint.placement_id + ":" + endpoint.edge
			for previous: Dictionary in used.get(key, []):
				if maxf(previous.interval[0], endpoint.interval_m[0]) < minf(previous.interval[1], endpoint.interval_m[1]):
					var detail := context.duplicate(true); detail.conflicting_seam_id = previous.id; detail.side = side
					diagnostics.append(_diagnostic("duplicate_seam_interval", "error", "同一地图边上的接缝区间重复覆盖。", sp, detail))
			if not used.has(key): used[key] = []
			used[key].append({"interval": endpoint.interval_m, "id": seam.id})
		valid_seams.append({"seam": seam, "context": context})
	_adjacent_diagnostics(space, valid_seams, path, diagnostics)


static func _adjacent_diagnostics(space: Dictionary, valid_seams: Array, path: String, diagnostics: Array) -> void:
	var corner_candidates := {}
	for p: Dictionary in space.placements:
		var rect := _rect(p)
		for x: float in [rect[0], rect[2]]:
			for z: float in [rect[1], rect[3]]: corner_candidates[JSON.stringify([x, z], "", true, true)] = [x, z]
	for key: String in corner_candidates:
		var corner: Array = corner_candidates[key]; var touching: Array = []
		for p: Dictionary in space.placements:
			var rect := _rect(p)
			if corner[0] >= rect[0] and corner[0] <= rect[2] and corner[1] >= rect[1] and corner[1] <= rect[3] and (corner[0] == rect[0] or corner[0] == rect[2] or corner[1] == rect[1] or corner[1] == rect[3]): touching.append(p.id)
		if touching.size() >= 3: diagnostics.append(_diagnostic("corner_contact", "info", "此处有多个地图边界交汇，通行仍需实际覆盖验证。", path, {"space_id": space.id, "seam_id": "", "placement_ids": touching, "space_position_m": [corner[0], 0.0, corner[1]]}))
	for i in space.placements.size():
		var a: Dictionary = space.placements[i]; var ar := _rect(a)
		for j in range(i + 1, space.placements.size()):
			var b: Dictionary = space.placements[j]; var br := _rect(b)
			for edges: Array in [["x_max", "x_min", 2, 0, 1, 3], ["x_min", "x_max", 0, 2, 1, 3], ["z_max", "z_min", 3, 1, 0, 2], ["z_min", "z_max", 1, 3, 0, 2]]:
				if absf(ar[edges[2]] - br[edges[3]]) > SEAM_POSITION_TOLERANCE_M: continue
				var lo := maxf(ar[edges[4]], br[edges[4]]); var hi := minf(ar[edges[5]], br[edges[5]])
				if hi <= lo: continue
				var gaps: Array = [[lo, hi]]
				for item: Dictionary in valid_seams:
					var seam: Dictionary = item.seam
					var direct: bool = seam.a.placement_id == a.id and seam.b.placement_id == b.id and seam.a.edge == edges[0] and seam.b.edge == edges[1]
					var reverse: bool = seam.a.placement_id == b.id and seam.b.placement_id == a.id and seam.a.edge == edges[1] and seam.b.edge == edges[0]
					if not direct and not reverse: continue
					var axis := 2 if str(edges[0]).begins_with("x_") else 0
					var context: Dictionary = item.context
					var covered := [maxf(context.space_segment_a_m[0][axis], context.space_segment_b_m[0][axis]), minf(context.space_segment_a_m[1][axis], context.space_segment_b_m[1][axis])]
					gaps = _subtract(gaps, covered)
				for gap: Array in gaps:
					var axis := 2 if str(edges[0]).begins_with("x_") else 0
					var artificial := {"id": "", "a": {"placement_id": a.id, "edge": edges[0], "interval_m": [gap[0] - a.origin_m[axis], gap[1] - a.origin_m[axis]]}, "b": {"placement_id": b.id, "edge": edges[1], "interval_m": [gap[0] - b.origin_m[axis], gap[1] - b.origin_m[axis]]}}
					diagnostics.append(_diagnostic("adjacent_uncovered", "info", "相邻边段尚未声明连续连接；允许保留为非通行边界。", path, _seam_context(space.id, artificial, a, b)))


static func _subtract(intervals: Array, covered: Array) -> Array:
	var result: Array = []
	if covered[1] <= covered[0]: return intervals
	for interval: Array in intervals:
		if covered[1] <= interval[0] or covered[0] >= interval[1]: result.append(interval); continue
		if covered[0] > interval[0]: result.append([interval[0], covered[0]])
		if covered[1] < interval[1]: result.append([covered[1], interval[1]])
	return result


static func _seam_context(space_id: String, seam: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	var la := _segment(a, seam.a); var lb := _segment(b, seam.b)
	var wa := [_translate(a, la[0]), _translate(a, la[1])]; var wb := [_translate(b, lb[0]), _translate(b, lb[1])]
	var error := 0.0
	for end in 2:
		for axis in [0, 2]: error = maxf(error, absf(wa[end][axis] - wb[end][axis]))
	return {"space_id": space_id, "seam_id": seam.id, "placement_ids": [a.id, b.id], "local_a_m": la[0], "local_b_m": lb[0], "space_position_m": wa[0], "space_a_m": wa[0], "space_b_m": wb[0], "local_segment_a_m": la, "local_segment_b_m": lb, "space_segment_a_m": wa, "space_segment_b_m": wb, "delta_m": [wb[0][0] - wa[0][0], wb[0][1] - wa[0][1], wb[0][2] - wa[0][2]], "horizontal_error_m": error, "tolerance_m": SEAM_POSITION_TOLERANCE_M}


static func _segment(placement: Dictionary, endpoint: Dictionary) -> Array:
	var r: Array = placement.ownership_xz_m; var span: Array = endpoint.interval_m
	match endpoint.edge:
		"x_min": return [[r[0], 0.0, span[0]], [r[0], 0.0, span[1]]]
		"x_max": return [[r[2], 0.0, span[0]], [r[2], 0.0, span[1]]]
		"z_min": return [[span[0], 0.0, r[1]], [span[1], 0.0, r[1]]]
	return [[span[0], 0.0, r[3]], [span[1], 0.0, r[3]]]


static func _point_context(space_id: String, a: Dictionary, b: Dictionary, world: Array) -> Dictionary:
	return {"space_id": space_id, "seam_id": "", "placement_ids": [a.id, b.id], "space_position_m": world, "space_a_m": world, "space_b_m": [world[0], float(b.origin_m[1]), world[2]], "local_a_m": [world[0] - a.origin_m[0], 0.0, world[2] - a.origin_m[2]], "local_b_m": [world[0] - b.origin_m[0], 0.0, world[2] - b.origin_m[2]]}


static func _translate(placement: Dictionary, point: Array) -> Array:
	return [float(placement.origin_m[0]) + float(point[0]), float(placement.origin_m[1]) + float(point[1]), float(placement.origin_m[2]) + float(point[2])]


static func _rect(p: Dictionary) -> Array:
	var r: Array = p.ownership_xz_m; var o: Array = p.origin_m
	return [float(o[0]) + float(r[0]), float(o[2]) + float(r[1]), float(o[0]) + float(r[2]), float(o[2]) + float(r[3])]


static func _contains(rect: Array, x: float, z: float) -> bool:
	return x >= rect[0] and x < rect[2] and z >= rect[1] and z < rect[3]


static func _fields(value: Dictionary, required: Array, optional: Array, path: String) -> Dictionary:
	for field: String in required:
		if not value.has(field): return _fail("invalid_layout", "缺少字段：" + field, path)
	for key: Variant in value:
		# Dictionary dot assignment creates StringName keys in GDScript; they
		# serialize as the same JSON field names and must match UI/HTTP inputs.
		if not (key is String or key is StringName): return _fail("unknown_layout_field", "布局字段名必须是字符串。", path)
		var field := str(key)
		if (not required.has(field)) and (not optional.has(field)): return _fail("unknown_layout_field", "不支持的布局字段：" + field, path)
	return {"ok": true}


static func _numbers(raw: Variant, count: int, path: String) -> Dictionary:
	if not raw is Array or raw.size() != count: return _fail("invalid_layout", "坐标数组长度无效。", path)
	var values: Array = []
	for scalar: Variant in raw:
		if not _numeric(scalar) or not is_finite(float(scalar)): return _fail("invalid_layout", "坐标必须是有限数值。", path)
		if not _coordinate(float(scalar)): return _fail("coordinate_out_of_range", "坐标超出 ±1000000000000 米。", path)
		values.append(0.0 if float(scalar) == 0.0 else float(scalar))
	return {"ok": true, "values": values}


static func _numeric(value: Variant) -> bool:
	return value is int or value is float


static func _coordinate(value: float) -> bool:
	return is_finite(value) and absf(value) <= Address.MAX_COORDINATE_M


static func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128: return false
	for index in value.length():
		var c: int = value.unicode_at(index)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95): return false
	return true


static func _version(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128: return false
	for index in value.length():
		var c: int = value.unicode_at(index)
		if c < 32 or c == 127: return false
	return true


static func _diagnostic(code: String, severity: String, message: String, path: String, context: Dictionary = {}) -> Dictionary:
	return {"code": code, "severity": severity, "message": message, "path": path}.merged(context)


static func _fail(code: String, message: String, path: String, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason_code": code, "message": message, "diagnostics": [_diagnostic(code, "error", message, path, context)]}
