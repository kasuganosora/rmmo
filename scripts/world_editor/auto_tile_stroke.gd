extends RefCounted
## One brush transaction, indexed cells, cardinally connected interpolation.
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
var active := false
var changed := false
var doc
var family := ""
var cell_size := 4.0
var elevation := 0.0
var erase := false
var before: Array = []
var index := {}
var last: Variant = null
var touched := {}
var error := ""
var options := {}
var editable: Callable


func begin(document, selected_family: String, spacing: float, height: float, erasing: bool, settings: Dictionary = {}) -> void:
	doc = document
	family = selected_family
	cell_size = spacing
	elevation = snappedf(height, 0.001)
	erase = erasing
	before = doc.records.duplicate(true)
	index = Rules.index_records(doc.records)
	last = null
	touched.clear()
	changed = false
	error = Rules.options_error(family, elevation, settings)
	options = Rules.normalized_options(family, settings)
	active = error.is_empty() and family in Rules.FAMILIES and cell_size > 0 and is_finite(cell_size) and is_finite(elevation)


func paint(point: Vector3) -> Array[String]:
	var changed_ids: Array[String] = []
	if not active or not point.is_finite(): return changed_ids
	var cell := Rules.cell_at(point, cell_size)
	var from: Vector2i = cell if last == null else last
	if absi(cell.x - from.x) + absi(cell.y - from.y) > 1024:
		error = "一次拖动画笔跨度超过 1024 格，请缩小范围"
		last = null
		return changed_ids
	var cells := _line(from, cell)
	last = cell
	var affected := {}
	for at in cells:
		var layer := float(options.get("base_height", 0)) if family == "cliff" else elevation
		var key := Rules.key(at, family, cell_size, layer)
		if touched.has(key): continue
		touched[key] = true
		var record: Dictionary = index.get(key, {})
		if not record.is_empty() and editable.is_valid() and not editable.call(record): continue
		if bool(record.get("editor_locked", false)) or bool(record.get("editor_hidden", false)): continue
		if erase:
			if record.is_empty() or record.tile3d.family != family: continue
			changed_ids.append(str(record.uuid))
			doc.remove(str(record.uuid))
			index.erase(key)
		else:
			if not record.is_empty() and record.tile3d.family == family and float(record.tile3d.elevation) == elevation and record.tile3d.get("options", {}) == options: continue
			if record.is_empty():
				var uuid: String = doc.add_box_silent("ground", Vector3.ZERO, Vector3.ONE)
				record = doc._find(uuid)
			Rules.configure(record, at, family, cell_size, elevation, options)
			index[key] = record
			changed_ids.append(str(record.uuid))
		changed = true
		affected[key] = true
		for offset in Rules.OFFSETS: affected[at + offset] = true
		affected[at] = true
	# A height change also affects bridge landings on other logical layers.
	var surfaces := Rules.landing_index(index)
	for record: Dictionary in index.values():
		var tile: Dictionary = record.tile3d
		if not affected.has(Vector2i(tile.cell[0], tile.cell[1])) or float(tile.cell_size) != cell_size: continue
		if Rules.refresh(index, record, surfaces) and not changed_ids.has(str(record.uuid)):
			changed_ids.append(str(record.uuid))
	return changed_ids


func finish(cancel: bool = false) -> bool:
	if not active: return false
	active = false
	var applied := changed and not cancel
	if changed:
		if cancel: doc.records = before.duplicate(true)
		else: doc.commit_change(before)
	before.clear()
	index.clear()
	touched.clear()
	last = null
	return applied


static func _line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [from]
	var at := from
	var dx := absi(to.x - from.x)
	var dz := absi(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sz := 1 if to.y > from.y else -1
	var error := dx - dz
	while at != to:
		var twice := error * 2
		if twice > -dz:
			error -= dz
			at.x += sx
			result.append(at)
		if twice < dx:
			error += dx
			at.y += sz
			result.append(at)
	return result
