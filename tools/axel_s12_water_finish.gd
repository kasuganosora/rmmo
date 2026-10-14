extends RefCounted
## Content-only finish for the current S12 straight stream. Keeps native channel
## records and the river's ownership signatures; no baked/raw mesh is introduced.
const Channel = preload("res://scripts/world3d/channel_surface.gd")
const City = preload("res://scripts/world3d/city_layout.gd")
const Layer = preload("res://scripts/world3d/terrain_river_layer.gd")
const Poly = preload("res://scripts/world3d/roof_plan.gd")
const Road = preload("res://scripts/world3d/road_plan.gd")
const TerrainProjection = preload("res://scripts/world3d/terrain_projection.gd")
const RIVER_ID := "axel_s12_stream"
const PREFIX := "river_axel_s12_stream_finish_"
const NOTE := "S12 圆端及侧条属于内容补齐；河道删除或改线会连同补片清理，原生改线只重建直端，需对符合本配方的新河道重新应用 helper。"


static func fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}


static func polygons() -> Array:
	# Native carving rounds both ends beyond the rectangular water ribbon. The
	# actual 1 m bed intersects water at radius <= 1.927 m. A 2 m, 16-segment
	# cap ends inside the bank (minimum chord radius 1.990 m).
	var left: Array = []
	var right: Array = []
	for i in 17:
		var angle: float = PI * .5 + float(i) * PI / 16.0
		left.append(Vector2(snappedf(337.0 + 2.0 * cos(angle), .000001), snappedf(125.5 + 2.0 * sin(angle), .000001)))
		angle = -PI * .5 + float(i) * PI / 16.0
		right.append(Vector2(snappedf(378.0 + 2.0 * cos(angle), .000001), snappedf(125.5 + 2.0 * sin(angle), .000001)))
	# Touch the existing x=337/378 ends and z=123.7/127.3 sides exactly.
	# There is no positive-area overlap, elevation offset or duplicated top face.
	return [left, right, Poly.rect([337.0, 123.5, 378.0, 123.7]), Poly.rect([337.0, 127.3, 378.0, 127.5])]


static func apply(editor) -> Dictionary:
	if editor == null or editor._doc == null:
		return fail("缺少当前地图文档")
	if editor.saving():
		return fail("请等待地图读取或保存完成")
	var guard: Dictionary = editor._gameplay.guard()
	if not guard.get("ok", false):
		return guard
	if not Layer.valid(editor._doc.map_meta):
		return fail("现有河道恢复图层无效")
	var metadata: Dictionary = editor._doc.map_meta.duplicate(true)
	var layer: Dictionary = {}
	for candidate: Dictionary in metadata.get("terrain_rivers", []):
		if candidate.id == RIVER_ID:
			layer = candidate
	if layer.is_empty():
		return fail("请先生成 axel_s12_stream 河道")
	var request: Dictionary = layer.request
	if not Layer.same(request.points, [[337.0, 125.5], [378.0, 125.5]]) or request.get("curved", true):
		return fail("S12 中心线已改变，此补齐配方仅适用于当前水平直线")
	for pair: Array in [["width", 3.6], ["bank_width", 1.0], ["water_level", 7.45], ["depth", .5]]:
		if not Layer.same(request.get(pair[0]), pair[1]):
			return fail("S12 河宽、水位或河床参数已改变，请重新计算圆端")
	var template: Dictionary = {}
	var owned_finish: Dictionary = {}
	for part: Dictionary in layer.water:
		var current: Dictionary = editor._doc._find(part.id)
		if not editor._record_editable(current) or City.token(current) != part.signature:
			return fail("S12 已有水面被锁定、隐藏、删除或手改")
		if str(part.id).begins_with(PREFIX):
			owned_finish[part.id] = part.signature
		elif template.is_empty():
			template = current
	if template.is_empty() or not template.has("channel_mesh") or template.get("surface_id") != "water":
		return fail("没有可复用的原生 S12 水面材质")
	var terrains: Array = []
	for item: Dictionary in layer.terrains:
		var current: Dictionary = editor._doc._find(item.after.uuid)
		if not editor._record_editable(current):
			return fail("S12 河床不可编辑")
		var restored: Dictionary = Layer.restore(current, item.before, item.after)
		if not restored.ok:
			return restored
		terrains.append(current)

	var bins: Dictionary = {}
	for polygon: Array in polygons():
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon:
			bounds = bounds.expand(point)
		for z in range(floori(bounds.position.y / 32.0), floori(bounds.end.y / 32.0) + 1):
			for x in range(floori(bounds.position.x / 32.0), floori(bounds.end.x / 32.0) + 1):
				var clipped: Array = Road.intersection(polygon, Poly.rect([x * 32.0, z * 32.0, (x + 1) * 32.0, (z + 1) * 32.0]))
				if clipped.size() < 3 or Poly.area(clipped) < .00001:
					continue
				var key := Vector2i(x, z)
				if not bins.has(key):
					bins[key] = []
				bins[key].append(clipped)
	var keys: Array = bins.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var additions: Array = []
	var ids: Array = []
	var material_validation: Dictionary = {}
	for key: Vector2i in keys:
		var center := Vector3((key.x + .5) * 32.0, float(request.water_level) - .01, (key.y + .5) * 32.0)
		var local: Array = []
		for polygon: Array in bins[key]:
			local.append(polygon.map(func(p: Vector2): return [(p.x - center.x) / 32.0, (p.y - center.z) / 32.0]))
		var record: Dictionary = template.duplicate(true)
		record.uuid = PREFIX + str(additions.size())
		record.position = [center.x, center.y, center.z]
		record.rotation = [0.0, 0.0, 0.0]
		record.size = [32.0, .02, 32.0]
		record.collision = "none"
		record.editor_name = "S12 浅溪圆端与水岸补齐 " + str(additions.size() + 1)
		record.channel_mesh = {"polygons": local, "uv_origin": [center.x, center.y, center.z]}
		if not Channel.valid(record) or editor._doc.validate_save_record(record, material_validation) != OK:
			return fail("S12 水面补片未通过原生记录校验")
		if not editor._authoring.Settings.contains(record, editor._authoring.settings):
			return fail("S12 水面补片超出当前编辑楼层")
		var coverage: Dictionary = TerrainProjection.fit(record, terrains, 0.0, 100.0)
		if not coverage.ok:
			return fail("S12 补片没有完整河床承托")
		var existing: Dictionary = editor._doc._find(record.uuid)
		if not existing.is_empty() and (not owned_finish.has(record.uuid) or owned_finish[record.uuid] != City.token(record)):
			return fail("S12 补片 UUID 已存在且内容不同")
		additions.append(record)
		ids.append(record.uuid)
	if not owned_finish.is_empty():
		if owned_finish.size() != additions.size() or not ids.all(func(id): return owned_finish.has(id)):
			return fail("S12 补片只有部分存在，请先恢复完整河道")
		return {"ok": true, "changed": false, "ids": ids, "note": NOTE}
	if editor._doc.records.size() + additions.size() > 100000:
		return fail("地图物件数量超限")
	for record: Dictionary in additions:
		layer.water.append({"id": record.uuid, "signature": City.token(record)})
	if not Layer.valid(metadata):
		return fail("S12 补片所有权登记无效")
	# All geometry, dependencies and ownership have been validated before the
	# single transaction. The ordinary editor commit handles derived batching.
	editor._doc.checkpoint_recovery()
	editor._doc.records.append_array(additions)
	editor._doc.map_meta = metadata
	editor._commit_records(ids)
	return {"ok": true, "changed": true, "ids": ids, "records_added": additions.size(), "water_top_y": request.water_level, "note": NOTE}
