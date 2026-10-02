extends RefCounted
## Record-space bounds also work before a mesh is instantiated.

static func vector(record: Dictionary, field: String) -> Vector3:
	var values: Array = record.get(field, [0, 0, 0])
	return Vector3(values[0], values[1], values[2])


static func corners(record: Dictionary) -> Array[Vector3]:
	var size := vector(record, "size")
	var local := AABB(-size * 0.5, size)
	if record.get("kind") == "asset":
		local = AABB(vector(record, "bounds_position") * size, vector(record, "bounds_size") * size)
	var transform := Transform3D(Basis.from_euler(vector(record, "rotation") * PI / 180.0), vector(record, "position"))
	if record.has("fixture"): transform=preload("res://scripts/world3d/building_fixtures.gd").transform(record)
	var result: Array[Vector3] = []
	if record.has("terrain_mesh"):
		var terrain_bounds:=preload("res://scripts/world3d/terrain_surface.gd").bounds(record)
		for i in 8: result.append(transform*terrain_bounds.get_endpoint(i))
		return result
	if record.has("channel_mesh"):
		for p in preload("res://scripts/world3d/channel_surface.gd").vertices(record): result.append(transform*p)
		return result
	if record.has("road_mesh"):
		for p in preload("res://scripts/world3d/road_surface.gd").vertices(record): result.append(transform*p)
		return result
	if record.get("building_shape")=="roof_prism":
		for p in preload("res://scripts/world3d/roof_mesh.gd").vertices(record): result.append(transform*p)
		return result
	for i in 8: result.append(transform * local.get_endpoint(i))
	return result


static func bounds(records: Array) -> AABB:
	var result := AABB()
	var first := true
	for record in records:
		for point in corners(record):
			if first:
				result = AABB(point, Vector3.ZERO)
				first = false
			else: result = result.expand(point)
	return result


static func editable(record: Dictionary) -> bool:
	return not record.is_empty() and not bool(record.get("editor_locked", false)) and not bool(record.get("editor_hidden", false))


static func label(record: Dictionary) -> String:
	return str(record.get("editor_name", record.get("label", record.get("name", record.get("kind", "物件")))))


static func new_group_id() -> String:
	return "group_" + Crypto.new().generate_random_bytes(12).hex_encode()


static func duplicate_records(doc, originals: Array, offset: Vector3, group_label: String = "") -> Array[String]:
	var ids: Array[String] = []
	var remap := {}
	var groups := {}
	var copies: Array = []
	var prefab_group := new_group_id() if not group_label.is_empty() else ""
	for record in originals:
		var copy: Dictionary = record.duplicate(true)
		preload("res://scripts/world3d/building_fixtures.gd").bake_snapshot(copy)
		copy.erase("building") # Ordinary copies are independent, not another owner's generated parts.
		copy.erase("road_source")
		var id: String = doc._push(str(copy.kind), str(copy.get("surface_id", "model")), Vector3.ZERO, Vector3.ONE)
		remap[str(copy.uuid)] = id
		copy.uuid = id
		copy.erase("editor_hidden")
		copy.erase("editor_locked")
		preload("res://scripts/world3d/auto_tile_rules.gd").detach(copy)
		var position := vector(copy, "position") + offset
		copy.position = [position.x, position.y, position.z]
		var old_group := str(copy.get("editor_group", ""))
		if not prefab_group.is_empty():
			copy.editor_group = prefab_group
			copy.editor_group_name = group_label
		elif not old_group.is_empty():
			if not groups.has(old_group): groups[old_group] = new_group_id()
			copy.editor_group = groups[old_group]
		doc.records[-1] = copy
		copies.append(copy)
		ids.append(id)
	for copy in copies:
		if copy.has("event"): _remap_references(copy.event, remap)
	return ids


static func _remap_references(value: Variant, remap: Dictionary) -> void:
	if value is Array:
		for child in value: _remap_references(child, remap)
	elif value is Dictionary:
		for key in value:
			if key in ["target", "event_id", "npc_id", "id"] and value[key] is String and remap.has(value[key]):
				value[key] = remap[value[key]]
			else: _remap_references(value[key], remap)
