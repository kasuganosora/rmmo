extends RefCounted
## Continuous support for ordinary frozen residences, without editing inputs.
## A successful result proves ground-floor coverage and the vertical soil range
## inside the actual foundation. It does not replace native obstacle, fixture,
## doorway or playable-collision validation of the complete placement.
const Terrain = preload("res://scripts/world3d/terrain_surface.gd")
const Geometry = preload("res://scripts/world_editor/selection_geometry.gd")
const Furrows = preload("res://scripts/world3d/terrain_furrows.gd")
const House = preload("res://scripts/world3d/house_prefab.gd")
const AREA_EPS := 0.0000001 # m²; fixed numerical residual, not a support allowance.
const HEIGHT_EPS := 0.00001
const MAX_FRAGMENTS := 16384
const MAX_OVERLAPS := 65536


static func failure(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	return {"ok": false, "stage": "residential_support", "code": code,
		"error": message, "exact": true, "conservative": false}.merged(detail, true)


static func unsupported(message: String, detail: Dictionary = {}) -> Dictionary:
	return failure("residential_support_unsupported", message,
		{"exact": false, "conservative": true}.merged(detail, true))


static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func vector_values(value: Variant, positive := false) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for item in value:
		if not number(item) or (positive and item <= 0):
			return false
	return true


static func valid_box(record: Dictionary) -> bool:
	return record.get("kind") == "box" and vector_values(record.get("position")) \
		and vector_values(record.get("size"), true) and vector_values(record.get("rotation")) \
		and record.rotation[0] == 0 and record.rotation[2] == 0 \
		and record.get("building_shape", "") in ["", "joined_box"] \
		and not record.has("fixture") and not record.has("terrain_grade") \
		and record.get("collision", "walk") != "none"


## Polygon arithmetic deliberately uses scalar doubles in placement-relative
## coordinates. Adding a 10 km world translation before a float32 Vector2 clip
## would discard narrow support defects. Polygons are convex and CCW.
static func area(polygon: Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var sum := 0.0
	var origin: Array = polygon[0]
	for i in range(1, polygon.size() - 1):
		var a: Array = polygon[i]
		var b: Array = polygon[i + 1]
		sum += (float(a[0]) - origin[0]) * (float(b[1]) - origin[1]) \
			- (float(a[1]) - origin[1]) * (float(b[0]) - origin[0])
	return absf(sum) * 0.5


static func clean(polygon: Array) -> Array:
	var result: Array = []
	for point: Array in polygon:
		if result.is_empty() or absf(point[0] - result[-1][0]) + absf(point[1] - result[-1][1]) > 1e-12:
			result.append(point)
	if result.size() > 1 and absf(result[0][0] - result[-1][0]) + absf(result[0][1] - result[-1][1]) <= 1e-12:
		result.pop_back()
	return result if result.size() >= 3 and area(result) > 1e-12 else []


static func clip(polygon: Array, a: Array, b: Array, inside := true) -> Array:
	var result: Array = []
	var dx: float = b[0] - a[0]
	var dz: float = b[1] - a[1]
	var sign_: float = 1.0 if inside else -1.0
	for i in polygon.size():
		var p: Array = polygon[i]
		var q: Array = polygon[(i + 1) % polygon.size()]
		var dp: float = sign_ * (dx * (p[1] - a[1]) - dz * (p[0] - a[0]))
		var dq: float = sign_ * (dx * (q[1] - a[1]) - dz * (q[0] - a[0]))
		if dp >= 0.0:
			result.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			var fraction: float = dp / (dp - dq)
			result.append([p[0] + (q[0] - p[0]) * fraction, p[1] + (q[1] - p[1]) * fraction])
	return clean(result)


static func intersection(polygon: Array, mask: Array) -> Array:
	var result := polygon
	for i in mask.size():
		result = clip(result, mask[i], mask[(i + 1) % mask.size()])
		if result.is_empty():
			break
	return result


static func subtract(polygon: Array, mask: Array) -> Array:
	var remaining := polygon
	var result: Array = []
	for i in mask.size():
		var outside := clip(remaining, mask[i], mask[(i + 1) % mask.size()], false)
		if not outside.is_empty():
			result.append(outside)
		remaining = clip(remaining, mask[i], mask[(i + 1) % mask.size()])
		if remaining.is_empty():
			break
	return result


static func bounds(polygon: Array) -> Array:
	var result: Array = [INF, INF, -INF, -INF]
	for point: Array in polygon:
		result[0] = minf(result[0], point[0]); result[1] = minf(result[1], point[1])
		result[2] = maxf(result[2], point[0]); result[3] = maxf(result[3], point[1])
	return result


static func bounds_overlap(a: Array, b: Array) -> bool:
	return a[0] <= b[2] and a[2] >= b[0] and a[1] <= b[3] and a[3] >= b[1]


static func box_polygon(record: Dictionary, yaw: float) -> Array:
	var a := deg_to_rad(float(record.rotation[1]))
	var b := deg_to_rad(yaw)
	var result: Array = []
	for sign_: Array in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		var x: float = sign_[0] * float(record.size[0]) * 0.5
		var z: float = sign_[1] * float(record.size[2]) * 0.5
		var rx: float = float(record.position[0]) + cos(a) * x + sin(a) * z
		var rz: float = float(record.position[2]) - sin(a) * x + cos(a) * z
		result.append([cos(b) * rx + sin(b) * rz, -sin(b) * rx + cos(b) * rz])
	return result


static func support_components(records: Array, yaw: float, parameters: Dictionary) -> Dictionary:
	if parameters.get("layout", "") not in ["townhouse", "hall"]:
		return unsupported("首版仅支持有真实连续基础的普通 townhouse/hall 住宅")
	var frozen := frozen_support_records(records)
	if not frozen.ok:
		return frozen
	records = frozen.records
	var foundations: Dictionary = {}
	for raw in records:
		if not raw is Dictionary or not raw.get("building", {}) is Dictionary:
			return unsupported("住宅构件缺少有效的建筑语义")
		var building: Dictionary = raw.get("building", {})
		if building.get("role", "") != "foundation":
			continue
		var part := str(building.get("part", ""))
		if foundations.has(part):
			return unsupported("基础构件身份不唯一", {"part": part})
		foundations[part] = raw
	var components: Array = []
	var excluded: Array = []
	for record: Dictionary in records:
		var building: Dictionary = record.get("building", {})
		if building.get("floor", -1) != 0 or building.get("role", "") != "floor":
			continue
		var detail := {"record_id": str(record.get("uuid", "")), "part": str(building.get("part", ""))}
		if not valid_box(record) or not number(building.get("floor_y")):
			return unsupported("首层支撑面必须为未倾斜的原生实体楼板", detail)
		var bottom: float = float(record.position[1]) - float(record.size[1]) * 0.5
		# The native generator marks half-storey landings as floor 0 too. Only
		# explicitly named raised landings without foundations are excluded.
		if bottom > float(building.floor_y) + 0.05:
			if str(building.get("part", "")).contains("landing") and not foundations.has(detail.part + "/foundation"):
				excluded.append(detail.record_id)
				continue
			return unsupported("架空或非首层支撑楼板需要明确的支撑域", detail)
		if not foundations.has(detail.part + "/foundation"):
			return unsupported("首层楼板缺少对应的真实基础，不能凭配方补出承托", detail)
		var foundation: Dictionary = foundations[detail.part + "/foundation"]
		if not valid_box(foundation) or foundation.get("building", {}).get("floor", -1) != 0:
			return unsupported("基础形状或楼层不受支持", detail)
		var polygon := box_polygon(record, yaw)
		var base_polygon := box_polygon(foundation, yaw)
		var common := area(intersection(polygon, base_polygon))
		if absf(area(polygon) - common) > AREA_EPS or absf(area(base_polygon) - common) > AREA_EPS:
			return unsupported("基础投影必须完整对应实际首层楼板", detail)
		var base_top: float = float(foundation.position[1]) + float(foundation.size[1]) * 0.5
		if absf(base_top - bottom) > HEIGHT_EPS:
			return unsupported("基础必须连接实际楼板底面，不能跨越未声明空隙", detail)
		components.append(detail.merged({"polygon": polygon, "bounds": bounds(polygon),
			"area": area(polygon), "floor_bottom": bottom,
			"foundation_bottom": float(foundation.position[1]) - float(foundation.size[1]) * 0.5,
			"foundation_id": str(foundation.get("uuid", ""))}))
	if components.is_empty():
		return unsupported("缺少可识别的首层楼板和基础支撑域")
	return {"ok": true, "components": components, "excluded_landings": excluded}


static func frozen_faces(record: Dictionary) -> Dictionary:
	var data := House.decode(record.house_prefab)
	if data.is_empty():
		return unsupported("冻结住宅几何 SHA 或数据无效", {"record_id": record.get("uuid", "")})
	var source: Dictionary = data.meshes[int(data.entries[0][1][1])]
	var faces: Array = []
	for surface: Array in source.surfaces:
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		var indices: Variant = surface[Mesh.ARRAY_INDEX]
		if indices != null and not indices.is_empty():
			for index: int in indices:
				faces.append(vertices[index])
		else:
			for vertex: Vector3 in vertices:
				faces.append(vertex)
	if faces.is_empty() or faces.size() > 150000:
		return unsupported("冻结住宅缺少受支持的碰撞三角形或超出预算", {"record_id": record.get("uuid", "")})
	return {"ok": true, "faces": faces}


## A frozen source retains each box's twelve collision triangles in order even
## though rendering is merged/indexed. Accept a candidate only after proving all
## six rectangular faces, with no missing/duplicate half-face. Merely observing
## a low horizontal patch would not prove a filled foundation underneath.
static func closed_box(faces: Array, start: int) -> Dictionary:
	if start + 36 > faces.size():
		return {}
	var box := AABB(faces[start], Vector3.ZERO)
	for i in range(start + 1, start + 36):
		box = box.expand(faces[i])
	if minf(box.size.x, minf(box.size.y, box.size.z)) <= HEIGHT_EPS:
		return {}
	var sides: Array = [[], [], [], [], [], []]
	for i in range(start, start + 36, 3):
		var side := -1
		for axis in 3:
			for end in 2:
				var value: float = box.position[axis] if end == 0 else box.end[axis]
				if absf(faces[i][axis] - value) <= HEIGHT_EPS and absf(faces[i + 1][axis] - value) <= HEIGHT_EPS and absf(faces[i + 2][axis] - value) <= HEIGHT_EPS:
					side = axis * 2 + end
		if side < 0:
			return {}
		var axis := side / 2
		var u := (axis + 1) % 3; var v := (axis + 2) % 3
		var triangle: Array = []
		for j in 3:
			var p: Vector3 = faces[i + j]
			for dimension in 3:
				if minf(absf(p[dimension] - box.position[dimension]), absf(p[dimension] - box.end[dimension])) > HEIGHT_EPS:
					return {}
			triangle.append([float(p[u]), float(p[v])])
		var cross: float = (triangle[1][0] - triangle[0][0]) * (triangle[2][1] - triangle[0][1]) - (triangle[1][1] - triangle[0][1]) * (triangle[2][0] - triangle[0][0])
		if cross < 0:
			triangle.reverse()
		sides[side].append(triangle)
	for side in 6:
		if sides[side].size() != 2:
			return {}
		var axis := side / 2
		var expected: float = box.size[(axis + 1) % 3] * box.size[(axis + 2) % 3]
		var tolerance: float = maxf(AREA_EPS, expected * 1e-7)
		if absf(area(sides[side][0]) + area(sides[side][1]) - expected) > tolerance or area(intersection(sides[side][0], sides[side][1])) > tolerance:
			return {}
	return {"bounds": box}


static func box_record(parent: Dictionary, box: AABB) -> Dictionary:
	var result := parent.duplicate(true)
	var basis := Basis(Vector3.UP, deg_to_rad(float(parent.rotation[1])))
	var center: Vector3 = Geometry.vector(parent, "position") + basis * box.get_center()
	result.position = [center.x, center.y, center.z]
	result.size = [box.size.x, box.size.y, box.size.z]
	for key in ["house_prefab", "building_shape", "box_faces", "fixture"]:
		result.erase(key)
	return result


static func frozen_support_records(records: Array) -> Dictionary:
	var result := records.duplicate(true)
	var shells: Array = []
	for record in records:
		if not record is Dictionary or not record.get("building", {}) is Dictionary:
			return unsupported("住宅构件缺少有效建筑语义")
		if not record.has("house_prefab") or record.building.get("floor", -1) != 0 or record.has("fixture") or record.building.get("role") != "shell":
			continue
		if not valid_box(record):
			return unsupported("冻结壳体变换不受支持", {"record_id": record.get("uuid", "")})
		var decoded := frozen_faces(record)
		if not decoded.ok:
			return decoded
		shells.append({"record": record, "faces": decoded.faces})
	for i in result.size():
		var floor_record: Dictionary = result[i]
		if not floor_record.has("house_prefab") or floor_record.get("building", {}).get("floor", -1) != 0 or floor_record.building.get("role") != "floor":
			continue
		if not valid_box(floor_record):
			return unsupported("冻结楼板变换不受支持", {"record_id": floor_record.get("uuid", "")})
		var decoded := frozen_faces(floor_record)
		if not decoded.ok:
			return decoded
		var slab := closed_box(decoded.faces, 0) if decoded.faces.size() == 36 else {}
		if slab.is_empty():
			return unsupported("冻结楼板碰撞必须证明为完整实体盒", {"record_id": floor_record.get("uuid", "")})
		floor_record = box_record(floor_record, slab.bounds)
		result[i] = floor_record
		var polygon := box_polygon(floor_record, 0.0)
		var bottom: float = float(floor_record.position[1]) - float(floor_record.size[1]) * 0.5
		# Raised landings are not required to grow a fictitious foundation.
		if bottom > float(floor_record.building.get("floor_y", 0.0)) + 0.05:
			floor_record.building.part = str(floor_record.building.part) + "/landing"
			continue
		var found := false
		for shell: Dictionary in shells:
			for start in range(0, shell.faces.size() - 35, 3):
				# The foundation's original collision box may follow arbitrary
				# non-box primitives; do not assume a global 36-vertex alignment.
				var candidate := closed_box(shell.faces, start)
				if candidate.is_empty():
					continue
				var foundation := box_record(shell.record, candidate.bounds)
				var top: float = float(foundation.position[1]) + float(foundation.size[1]) * 0.5
				if absf(top - bottom) > HEIGHT_EPS:
					continue
				var footprint := box_polygon(foundation, 0.0)
				var common := area(intersection(polygon, footprint))
				if absf(area(polygon) - common) > AREA_EPS or absf(area(footprint) - common) > AREA_EPS:
					continue
				foundation.uuid = str(shell.record.uuid) + "/support_triangle_" + str(start / 3)
				foundation.building = floor_record.building.duplicate(true)
				foundation.building.role = "foundation"
				foundation.building.part = str(floor_record.building.part) + "/foundation"
				result.append(foundation)
				found = true
				break
			if found:
				break
		if not found:
			return unsupported("冻结碰撞中无法证明与楼板连接的完整实体基础", {"record_id": floor_record.uuid})
	return {"ok": true, "records": result}


static func terrain_point(record: Dictionary, point: Vector3, origin: Vector3) -> Array:
	var angle := deg_to_rad(float(record.rotation[1]))
	return [float(record.position[0]) - float(origin.x) + cos(angle) * point.x + sin(angle) * point.z,
		float(record.position[1]) + point.y,
		float(record.position[2]) - float(origin.z) - sin(angle) * point.x + cos(angle) * point.z]


static func height_at(corners: Array, point: Array) -> float:
	var a: Array = corners[0]; var b: Array = corners[1]; var c: Array = corners[2]
	var bx: float = b[0] - a[0]; var bz: float = b[2] - a[2]
	var cx: float = c[0] - a[0]; var cz: float = c[2] - a[2]
	var px: float = point[0] - a[0]; var pz: float = point[1] - a[2]
	var determinant: float = bx * cz - bz * cx
	return float(a[1]) + ((px * cz - pz * cx) * (b[1] - a[1]) \
		+ (bx * pz - bz * px) * (c[1] - a[1])) / determinant


static func witness(component: Dictionary, terrain: Dictionary, x: int, z: int,
		triangle: int, point: Array, height: float, origin: Vector3) -> Dictionary:
	return {"record_id": component.record_id, "part": component.part,
		"foundation_id": component.foundation_id, "terrain_id": str(terrain.get("uuid", "")),
		"cell": [x, z], "triangle_index": triangle,
		"position": [float(origin.x) + point[0], height, float(origin.z) + point[1]],
		"terrain_height": height, "floor_bottom": component.floor_bottom,
		"foundation_bottom": component.foundation_bottom}


static func solve(doc, local_records: Array, position: Vector3, yaw: float,
		parameters: Dictionary, options: Dictionary = {}) -> Dictionary:
	var version: Variant = options.get("input_version", null)
	var result := _solve(doc, local_records, position, yaw, parameters, options)
	result.input_version = version
	return result


static func _solve(doc, local_records: Array, position: Vector3, yaw: float,
		parameters: Dictionary, options: Dictionary) -> Dictionary:
	if not position.is_finite() or not is_finite(yaw):
		return failure("residential_support_invalid_input", "安放位置和旋转必须为有限值")
	for key in options:
		if key not in ["min_y", "max_y", "max_shift", "input_version"]:
			return failure("residential_support_invalid_input", "未知支撑选项：" + str(key))
		if key != "input_version" and not number(options[key]):
			return failure("residential_support_invalid_input", "标高边界必须为有限值")
	if options.get("max_shift", 0.0) < 0.0 or options.get("min_y", -INF) > options.get("max_y", INF):
		return failure("residential_support_invalid_input", "标高边界顺序或最大调整量无效")
	if doc == null or not doc.get("records") is Array:
		return failure("residential_support_invalid_input", "缺少文档记录")
	var extracted := support_components(local_records, yaw, parameters)
	if not extracted.ok:
		return extracted
	var lower := -INF; var upper := INF
	var lower_witness: Dictionary = {}; var upper_witness: Dictionary = {}
	var terrain_ids: Array = []; var reports: Array = []
	var counts := {"terrain_candidates": 0, "cells_visited": 0, "triangle_clips": 0, "overlaps": 0}
	for component: Dictionary in extracted.components:
		var checked := region(doc, component, position, counts)
		if not checked.ok:
			return checked
		reports.append(checked.component)
		for id: String in checked.terrain_ids:
			if not terrain_ids.has(id):
				terrain_ids.append(id)
		if checked.lower > lower:
			lower = checked.lower; lower_witness = checked.lower_witness
		if checked.upper < upper:
			upper = checked.upper; upper_witness = checked.upper_witness
	if lower > upper:
		return failure("residential_support_height_interval", "地形起伏超过实际基础可承托高度，无法同时避免悬空和埋入楼板",
			{"interval": [lower, upper], "lower_witness": lower_witness, "upper_witness": upper_witness, "counts": counts})
	var geometric_interval := [lower, upper]
	lower = maxf(lower, float(options.get("min_y", -INF)))
	upper = minf(upper, float(options.get("max_y", INF)))
	if options.has("max_shift"):
		lower = maxf(lower, float(position.y) - float(options.max_shift))
		upper = minf(upper, float(position.y) + float(options.max_shift))
	if lower > upper:
		return failure("residential_support_height_limit", "安全支撑标高超出调用方允许的调整范围",
			{"interval": [lower, upper], "geometric_interval": geometric_interval,
			"lower_witness": lower_witness, "upper_witness": upper_witness, "counts": counts})
	var solved := position
	solved.y = clampf(position.y, lower, upper)
	return {"ok": true, "position": solved, "support": {"interval": [lower, upper],
		"geometric_interval": geometric_interval, "components": reports, "terrain_ids": terrain_ids,
		"lower_witness": lower_witness, "upper_witness": upper_witness, "counts": counts,
		"excluded_landings": extracted.excluded_landings, "area_tolerance": AREA_EPS,
		"scope": "continuous_ground_floor_foundation_only", "requires_native_placement_validation": true}}


static func region(doc, component: Dictionary, position: Vector3, counts: Dictionary, include_pieces := false) -> Dictionary:
	var lower := -INF; var upper := INF
	var lower_witness: Dictionary = {}; var upper_witness: Dictionary = {}
	var terrain_ids: Array = []; var pieces: Array = []
	var uncovered: Array = [component.polygon]
	var covered := 0.0; var lowest := INF; var highest := -INF
	var last_witness: Dictionary = {}; var hole_witness: Dictionary = {}
	for terrain: Dictionary in doc.records:
		if not terrain.has("terrain_mesh") and not terrain.has("terrain_volume"):
			continue
		if not vector_values(terrain.get("position")) or not vector_values(terrain.get("rotation")) or not vector_values(terrain.get("size"), true):
			return unsupported("地形变换无效", {"terrain_id": terrain.get("uuid", "")})
		# Conservative only for identifying unsupported intersecting terrain.
		if terrain.has("terrain_volume") or terrain.rotation[0] != 0 or terrain.rotation[2] != 0:
			var box: AABB = Geometry.bounds([terrain])
			var extent := [float(box.position.x) - position.x, float(box.position.z) - position.z,
				float(box.end.x) - position.x, float(box.end.z) - position.z]
			if bounds_overlap(component.bounds, extent):
				return unsupported("首版不支持倾斜高度场、体积地形或多层支撑", {"terrain_id": terrain.get("uuid", ""), "record_id": component.record_id})
			continue
		if not Terrain.valid(terrain):
			return failure("residential_support_invalid_terrain", "地形数据无效", {"terrain_id": terrain.get("uuid", "")})
		var t: Dictionary = terrain.terrain_mesh
		var terrain_polygon: Array = []
		for grid: Array in [[0, 0], [t.columns, 0], [t.columns, t.rows], [0, t.rows]]:
			var p := terrain_point(terrain, Terrain.point(terrain, grid[0], grid[1]), position)
			terrain_polygon.append([p[0], p[2]])
		if not bounds_overlap(component.bounds, bounds(terrain_polygon)):
			continue
		if area(intersection(component.polygon, terrain_polygon)) <= AREA_EPS:
			continue
		if Furrows.maximum_height(terrain) > 0.0:
			return unsupported("首版不支持含垄沟的支撑地形", {"terrain_id": terrain.get("uuid", ""), "record_id": component.record_id})
		if terrain.get("editor_hidden", false):
			return unsupported("隐藏地形不提供当前编辑器碰撞承托，请先显示地形", {"terrain_id": terrain.get("uuid", ""), "record_id": component.record_id})
		if terrain.get("collision", "walk") == "none":
			return unsupported("支撑地形必须提供实际碰撞", {"terrain_id": terrain.get("uuid", "")})
		counts.terrain_candidates += 1
		# The native topological domain is the tile rectangle minus complete hole
		# cells. Subtract that exact domain once; subtracting every triangle leaves
		# thousands of needless slivers even on a flat intact tile. Heights below
		# are still proved on every actual clipped native triangle.
		var terrain_coverage: Array = [intersection(component.polygon, terrain_polygon)]
		for z in int(t.rows):
			for x in int(t.columns):
				counts.cells_visited += 1
				var cell: Array = []
				for point: Vector3 in Terrain.cell(terrain, x, z):
					cell.append(terrain_point(terrain, point, position))
				if not Terrain.solid(t, x, z):
					var hole: Array = cell.map(func(p): return [p[0], p[2]])
					var rest: Array = []
					for fragment: Array in terrain_coverage:
						rest.append_array(subtract(fragment, hole))
					terrain_coverage = rest
					if rest.size() > MAX_FRAGMENTS:
						return unsupported("连续支撑缺口分区超出计算预算", {"counts": counts})
				for triangle_index in 2:
					var indices: Array = [0, 1, 2] if triangle_index == 0 else [0, 2, 3]
					var triangle: Array = []; var corners: Array = []
					for index: int in indices:
						corners.append(cell[index]); triangle.append([cell[index][0], cell[index][2]])
					if not bounds_overlap(component.bounds, bounds(triangle)):
						continue
					counts.triangle_clips += 1
					var overlap := intersection(component.polygon, triangle)
					var overlap_area := area(overlap)
					if overlap_area <= 1e-12:
						continue
					last_witness = witness(component, terrain, x, z, triangle_index, overlap[0], height_at(corners, overlap[0]), position)
					if not Terrain.solid(t, x, z):
						hole_witness = last_witness
						continue
					counts.overlaps += 1
					if counts.overlaps > MAX_OVERLAPS:
						return unsupported("连续支撑分区超出计算预算", {"counts": counts})
					covered += overlap_area
					if not terrain_ids.has(terrain.uuid):
						terrain_ids.append(terrain.uuid)
					var heights: Array = []
					for point: Array in overlap:
						var height := height_at(corners, point)
						heights.append(height)
						lowest = minf(lowest, height); highest = maxf(highest, height)
						var low: float = height - component.floor_bottom
						var high: float = height - component.foundation_bottom
						if low > lower:
							lower = low; lower_witness = witness(component, terrain, x, z, triangle_index, point, height, position)
						if high < upper:
							upper = high; upper_witness = witness(component, terrain, x, z, triangle_index, point, height, position)
					if include_pieces:
						pieces.append({"polygon": overlap, "bounds": bounds(overlap), "heights": heights, "corners": corners, "terrain_id": terrain.uuid, "cell": [x, z], "triangle_index": triangle_index})
		for polygon: Array in terrain_coverage:
			var remaining: Array = []
			for fragment: Array in uncovered:
				remaining.append_array(subtract(fragment, polygon))
			if remaining.size() > MAX_FRAGMENTS:
				return unsupported("连续支撑缺口分区超出计算预算", {"counts": counts})
			uncovered = remaining
	var missing := 0.0
	for fragment: Array in uncovered:
		missing += area(fragment)
	if missing > AREA_EPS:
		var location: Array = uncovered[0][0]
		var detail: Dictionary = hole_witness.duplicate() if not hole_witness.is_empty() else {"record_id": component.record_id, "part": component.part}
		detail.merge({"missing_area": missing, "support_area": component.area,
			"gap_polygon": uncovered[0].map(func(p): return [float(position.x) + p[0], float(position.z) + p[1]]),
			"position": [float(position.x) + location[0], float(position.y), float(position.z) + location[1]], "counts": counts}, true)
		return failure("residential_support_coverage_gap", "实际首层支撑域存在地形孔洞或未覆盖区域", detail)
	if covered - (float(component.area) - missing) > AREA_EPS:
		return unsupported("支撑域存在重叠地形，无法确定唯一高度场", last_witness.merged({"overlap_area": covered - component.area + missing, "counts": counts}))
	if not hole_witness.is_empty():
		return unsupported("地形洞口由其他地形覆盖，需明确多层支撑语义", hole_witness)
	var report := {"record_id": component.record_id, "part": component.part, "foundation_id": component.foundation_id,
		"area": component.area, "covered_area": covered, "missing_area": missing,
		"terrain_range": [lowest, highest], "floor_bottom": component.floor_bottom, "foundation_bottom": component.foundation_bottom}
	return {"ok": true, "component": report, "lower": lower, "upper": upper, "lower_witness": lower_witness, "upper_witness": upper_witness, "terrain_ids": terrain_ids, "pieces": pieces, "counts": counts}


## Shared convex corridor proof. Returns full coverage plus the largest real
## triangle slope and cross-terrain height jump; callers set their own actor/
## road limits. No finite point sampling is used for these three guarantees.
static func terrain_region(doc, polygon: Variant) -> Dictionary:
	if doc == null or not doc.get("records") is Array or not (polygon is Array or polygon is PackedVector2Array) or polygon.size() < 3 or polygon.size() > 128:
		return failure("residential_support_invalid_input", "走廊需要文档和 3–128 个凸多边形顶点")
	var world: Array = []
	for value in polygon:
		if value is Vector2 and value.is_finite():
			world.append([float(value.x), float(value.y)])
		elif value is Array and value.size() == 2 and number(value[0]) and number(value[1]):
			world.append([float(value[0]), float(value[1])])
		else:
			return failure("residential_support_invalid_input", "走廊顶点必须为有限 XZ 坐标")
	var origin := Vector3(world[0][0], 0.0, world[0][1])
	var local: Array = []
	for p: Array in world:
		local.append([p[0] - float(origin.x), p[1] - float(origin.z)])
	local = clean(local)
	if local.is_empty() or area(local) <= AREA_EPS:
		return unsupported("走廊投影退化或小于可靠面积范围")
	var orientation := 0.0
	for i in local.size():
		var a: Array = local[i]; var b: Array = local[(i + 1) % local.size()]; var c: Array = local[(i + 2) % local.size()]
		var cross: float = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
		if absf(cross) <= 1e-12:
			continue
		if orientation != 0.0 and signf(cross) != orientation:
			return unsupported("首版走廊覆盖证明仅支持凸多边形")
		orientation = signf(cross)
	if orientation < 0:
		local.reverse()
	# Convexity also requires every vertex to lie inside every edge; a winding
	# star can have same-sign local turns while still self-intersecting.
	for i in local.size():
		var a: Array = local[i]; var b: Array = local[(i + 1) % local.size()]
		for p: Array in local:
			if (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) < -1e-10:
				return unsupported("走廊投影自交或非凸")
	var component := {"record_id": "", "part": "corridor", "foundation_id": "", "polygon": local,
		"bounds": bounds(local), "area": area(local), "floor_bottom": 0.0, "foundation_bottom": 0.0}
	var counts := {"terrain_candidates": 0, "cells_visited": 0, "triangle_clips": 0, "overlaps": 0}
	var checked := region(doc, component, origin, counts, true)
	if not checked.ok:
		return checked
	var max_grade := 0.0; var grade_witness: Dictionary = {}
	for piece: Dictionary in checked.pieces:
		var a: Array = piece.corners[0]; var b: Array = piece.corners[1]; var c: Array = piece.corners[2]
		var bx: float = b[0] - a[0]; var bz: float = b[2] - a[2]; var by: float = b[1] - a[1]
		var cx: float = c[0] - a[0]; var cz: float = c[2] - a[2]; var cy: float = c[1] - a[1]
		var determinant: float = bx * cz - bz * cx
		var gx: float = (by * cz - cy * bz) / determinant
		var gz: float = (bx * cy - cx * by) / determinant
		var grade := sqrt(gx * gx + gz * gz)
		if grade > max_grade:
			max_grade = grade
			grade_witness = {"terrain_id": piece.terrain_id, "cell": piece.cell, "triangle_index": piece.triangle_index,
				"position": [float(origin.x) + piece.polygon[0][0], piece.heights[0], float(origin.z) + piece.polygon[0][1]], "grade": grade}
	var seam := seam_steps(checked.pieces, origin)
	if not seam.ok:
		return seam
	return {"ok": true, "stage": "residential_support", "exact": true, "conservative": false,
		"area": checked.component.area, "covered_area": checked.component.covered_area,
		"height_range": checked.component.terrain_range, "max_grade": max_grade, "grade_witness": grade_witness,
		"max_seam_step": seam.max_step, "seam_witness": seam.witness,
		"terrain_ids": checked.terrain_ids, "counts": counts, "area_tolerance": AREA_EPS,
		"scope": "continuous_heightfield_region_only"}


static func seam_steps(pieces: Array, origin: Vector3) -> Dictionary:
	var max_step := 0.0; var at: Dictionary = {}; var comparisons := 0
	var adjacent: Dictionary = {}
	for piece: Dictionary in pieces:
		adjacent[piece.terrain_id] = []
	if adjacent.size() <= 1:
		return {"ok": true, "max_step": 0.0, "witness": {}}
	for i in pieces.size():
		var a: Dictionary = pieces[i]
		for j in range(i + 1, pieces.size()):
			var b: Dictionary = pieces[j]
			if a.terrain_id == b.terrain_id:
				continue # A native heightfield shares exact cell vertices.
			comparisons += 1
			if comparisons > 2000000:
				return unsupported("地形接缝证明超出预算，需缩小走廊范围")
			if not bounds_overlap(a.bounds, b.bounds):
				continue
			for ea in a.polygon.size():
				var p: Array = a.polygon[ea]; var q: Array = a.polygon[(ea + 1) % a.polygon.size()]
				var dx: float = q[0] - p[0]; var dz: float = q[1] - p[1]
				var length_squared: float = dx * dx + dz * dz
				if length_squared <= 1e-20:
					continue
				for eb in b.polygon.size():
					var r: Array = b.polygon[eb]; var s: Array = b.polygon[(eb + 1) % b.polygon.size()]
					if absf(dx * (r[1] - p[1]) - dz * (r[0] - p[0])) > 1e-8 * sqrt(length_squared) or absf(dx * (s[1] - p[1]) - dz * (s[0] - p[0])) > 1e-8 * sqrt(length_squared):
						continue
					var tr: float = ((r[0] - p[0]) * dx + (r[1] - p[1]) * dz) / length_squared
					var ts: float = ((s[0] - p[0]) * dx + (s[1] - p[1]) * dz) / length_squared
					var lo: float = maxf(0.0, minf(tr, ts)); var hi: float = minf(1.0, maxf(tr, ts))
					if hi - lo <= 1e-10 or absf(ts - tr) <= 1e-12:
						continue
					if not adjacent[a.terrain_id].has(b.terrain_id):
						adjacent[a.terrain_id].append(b.terrain_id)
						adjacent[b.terrain_id].append(a.terrain_id)
					for t: float in [lo, hi]:
						var ya: float = lerpf(a.heights[ea], a.heights[(ea + 1) % a.polygon.size()], t)
						var yb: float = lerpf(b.heights[eb], b.heights[(eb + 1) % b.polygon.size()], (t - tr) / (ts - tr))
						var step := absf(ya - yb)
						if step > max_step:
							max_step = step
							at = {"terrain_ids": [a.terrain_id, b.terrain_id], "cells": [a.cell, b.cell],
								"position": [float(origin.x) + p[0] + t * dx, ya, float(origin.z) + p[1] + t * dz], "heights": [ya, yb], "step": step}
	# A tiny numerical coverage residual must not hide an unproved seam between
	# distinct tiles. Every owner in the convex connected region needs a chain
	# of actually checked shared segments, not merely matching total area.
	var reached: Array = [adjacent.keys()[0]]
	var cursor := 0
	while cursor < reached.size():
		for id: String in adjacent[reached[cursor]]:
			if not reached.has(id):
				reached.append(id)
		cursor += 1
	if reached.size() != adjacent.size():
		return unsupported("无法证明全部地形接缝的连续高度，请核对边界或坐标精度", {"terrain_ids": adjacent.keys()})
	return {"ok": true, "max_step": max_step, "witness": at}
