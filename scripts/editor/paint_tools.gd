extends RefCounted
## Pencil / rect / fill / eyedropper against a MapDocument.

const TileId = preload("res://scripts/map/tile_id.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")

enum Tool { PENCIL, RECT, FILL, EYEDROP, ERASE, SELECT, LINE, POLYLINE, ELLIPSE, RING }

var tool: int = Tool.PENCIL
var layer_z: int = 0 ## 0-5 MV; -1 means ext
var ext_layer: String = ""
var tile_id: int = 0
var rect_start: Vector2i = Vector2i(-1, -1)
var exact_autotile: bool = false
var clipboard: Dictionary = {}
var stamp_w: int = 1
var stamp_h: int = 1
var stamp_tiles: PackedInt32Array = PackedInt32Array()
var _stroke_origin: Vector2i = Vector2i(-1, -1)


func begin_stroke() -> void:
	rect_start = Vector2i(-1, -1)
	_stroke_origin = Vector2i(-1, -1)


func set_stamp(w: int, h: int, tiles: PackedInt32Array) -> void:
	stamp_w = maxi(w, 1)
	stamp_h = maxi(h, 1)
	stamp_tiles = tiles
	if stamp_tiles.size() > 0:
		tile_id = int(stamp_tiles[0])


func has_stamp() -> bool:
	return stamp_w * stamp_h > 1 and stamp_tiles.size() >= stamp_w * stamp_h


func apply_cell(doc: RefCounted, cell: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null or tool == Tool.SELECT:
		return dirty
	var id := 0 if erase or tool == Tool.ERASE else _normalized_paint_id()
	if tool == Tool.EYEDROP:
		tile_id = _read_cell(doc, cell)
		return dirty
	if tool == Tool.FILL:
		return _fill(doc, cell, id)
	if has_stamp() and not erase and tool != Tool.ERASE:
		if _stroke_origin.x < 0:
			_stroke_origin = cell
			return apply_stamp(doc, cell)
		return _stamp_cell(doc, cell, _stroke_origin)
	_begin_batch(doc)
	_write_cell(doc, cell, id)
	dirty.append(cell)
	if not exact_autotile:
		_refresh_autotiles(doc, [cell], dirty)
	_end_batch(doc)
	return dirty


func apply_stamp(doc: RefCounted, origin: Vector2i) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null or not has_stamp():
		return apply_cell(doc, origin)
	_begin_batch(doc)
	var seeds: Array[Vector2i] = []
	for y in range(stamp_h):
		for x in range(stamp_w):
			var cell := Vector2i(origin.x + x, origin.y + y)
			if cell.x < 0 or cell.y < 0 or cell.x >= int(doc.width) or cell.y >= int(doc.height):
				continue
			var idx := y * stamp_w + x
			var id := int(stamp_tiles[idx]) if idx >= 0 and idx < stamp_tiles.size() else 0
			if layer_z >= 0 and TileId.is_autotile(id) and not exact_autotile:
				id = TileId.make_autotile_id(TileId.autotile_kind(id), 0)
			_write_cell(doc, cell, id)
			dirty.append(cell)
			seeds.append(cell)
	if not exact_autotile:
		_refresh_autotiles(doc, seeds, dirty)
	_end_batch(doc)
	return dirty


func _stamp_cell(doc: RefCounted, cell: Vector2i, origin: Vector2i) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null or not has_stamp():
		return dirty
	var lx := posmod(cell.x - origin.x, stamp_w)
	var ly := posmod(cell.y - origin.y, stamp_h)
	var idx := ly * stamp_w + lx
	var id := int(stamp_tiles[idx]) if idx >= 0 and idx < stamp_tiles.size() else 0
	_begin_batch(doc)
	if layer_z >= 0 and TileId.is_autotile(id) and not exact_autotile:
		id = TileId.make_autotile_id(TileId.autotile_kind(id), 0)
	_write_cell(doc, cell, id)
	dirty.append(cell)
	if not exact_autotile:
		_refresh_autotiles(doc, [cell], dirty)
	_end_batch(doc)
	return dirty


func copy_rect(doc: RefCounted, a: Vector2i, b: Vector2i) -> Dictionary:
	clipboard = {}
	if doc == null:
		return clipboard
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	x0 = clampi(x0, 0, int(doc.width) - 1)
	x1 = clampi(x1, 0, int(doc.width) - 1)
	y0 = clampi(y0, 0, int(doc.height) - 1)
	y1 = clampi(y1, 0, int(doc.height) - 1)
	if x1 < x0 or y1 < y0:
		return clipboard
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var tiles := PackedInt32Array()
	tiles.resize(w * h)
	var i := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			tiles[i] = _read_cell(doc, Vector2i(x, y))
			i += 1
	clipboard = {
		"w": w,
		"h": h,
		"tiles": tiles,
		"layer_z": layer_z,
		"ext_layer": ext_layer,
	}
	return clipboard


func paste_at(doc: RefCounted, origin: Vector2i) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null or clipboard.is_empty():
		return dirty
	var w := int(clipboard.get("w", 0))
	var h := int(clipboard.get("h", 0))
	var tiles_v: Variant = clipboard.get("tiles", PackedInt32Array())
	if w <= 0 or h <= 0 or typeof(tiles_v) != TYPE_PACKED_INT32_ARRAY:
		return dirty
	var tiles: PackedInt32Array = tiles_v
	_begin_batch(doc)
	for y in range(h):
		for x in range(w):
			var cell := Vector2i(origin.x + x, origin.y + y)
			if cell.x < 0 or cell.y < 0 or cell.x >= int(doc.width) or cell.y >= int(doc.height):
				continue
			var idx := y * w + x
			var id := int(tiles[idx]) if idx >= 0 and idx < tiles.size() else 0
			_write_cell(doc, cell, id)
			dirty.append(cell)
	# Paste exact ids (including autotile shapes). Neighbors can be refreshed separately.
	_end_batch(doc)
	return dirty


func cut_rect(doc: RefCounted, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	copy_rect(doc, a, b)
	return apply_rect(doc, a, b, true)


func rotate_clipboard(cw: bool = true) -> Dictionary:
	if clipboard.is_empty():
		return clipboard
	var w := int(clipboard.get("w", 0))
	var h := int(clipboard.get("h", 0))
	var src_v: Variant = clipboard.get("tiles", PackedInt32Array())
	if w <= 0 or h <= 0 or typeof(src_v) != TYPE_PACKED_INT32_ARRAY:
		return clipboard
	var src: PackedInt32Array = src_v
	var dst := PackedInt32Array()
	dst.resize(w * h)
	for y in range(h):
		for x in range(w):
			var id := int(src[y * w + x]) if (y * w + x) < src.size() else 0
			var nx: int
			var ny: int
			if cw:
				nx = h - 1 - y
				ny = x
			else:
				nx = y
				ny = w - 1 - x
			dst[ny * h + nx] = id
	clipboard["w"] = h
	clipboard["h"] = w
	clipboard["tiles"] = dst
	return clipboard


func flip_clipboard(horizontal: bool = true) -> Dictionary:
	if clipboard.is_empty():
		return clipboard
	var w := int(clipboard.get("w", 0))
	var h := int(clipboard.get("h", 0))
	var src_v: Variant = clipboard.get("tiles", PackedInt32Array())
	if w <= 0 or h <= 0 or typeof(src_v) != TYPE_PACKED_INT32_ARRAY:
		return clipboard
	var src: PackedInt32Array = src_v
	var dst := PackedInt32Array()
	dst.resize(w * h)
	for y in range(h):
		for x in range(w):
			var id := int(src[y * w + x]) if (y * w + x) < src.size() else 0
			var nx := (w - 1 - x) if horizontal else x
			var ny := y if horizontal else (h - 1 - y)
			dst[ny * w + nx] = id
	clipboard["tiles"] = dst
	return clipboard


func replace_id(doc: RefCounted, old_id: int, new_id: int, kind_match: bool = true) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null:
		return dirty
	_begin_batch(doc)
	var seeds: Array[Vector2i] = []
	for y in range(int(doc.height)):
		for x in range(int(doc.width)):
			var c := Vector2i(x, y)
			var cur := _read_cell(doc, c)
			var hit := cur == old_id
			if kind_match and TileId.is_autotile(old_id) and TileId.is_autotile(cur):
				hit = TileId.autotile_kind(cur) == TileId.autotile_kind(old_id)
			if not hit:
				continue
			var nid := new_id
			if TileId.is_autotile(nid) and not exact_autotile:
				nid = TileId.make_autotile_id(TileId.autotile_kind(nid), 0)
			_write_cell(doc, c, nid)
			dirty.append(c)
			seeds.append(c)
	if not exact_autotile:
		_refresh_autotiles(doc, seeds, dirty)
	_end_batch(doc)
	return dirty


func apply_cells(doc: RefCounted, cells: Array, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null:
		return dirty
	var id := 0 if erase else _normalized_paint_id()
	_begin_batch(doc)
	var seeds: Array[Vector2i] = []
	for item in cells:
		var c: Vector2i = item
		if c.x < 0 or c.y < 0 or c.x >= int(doc.width) or c.y >= int(doc.height):
			continue
		_write_cell(doc, c, id)
		dirty.append(c)
		seeds.append(c)
	if not exact_autotile:
		_refresh_autotiles(doc, seeds, dirty)
	_end_batch(doc)
	return dirty


func apply_rect(doc: RefCounted, a: Vector2i, b: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	var id := 0 if erase else _normalized_paint_id()
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	var use_stamp := (not erase) and has_stamp()
	_begin_batch(doc)
	var seeds: Array[Vector2i] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			var write_id := id
			if use_stamp:
				var lx := posmod(x - x0, stamp_w)
				var ly := posmod(y - y0, stamp_h)
				var idx := ly * stamp_w + lx
				write_id = int(stamp_tiles[idx]) if idx >= 0 and idx < stamp_tiles.size() else 0
				if layer_z >= 0 and TileId.is_autotile(write_id) and not exact_autotile:
					write_id = TileId.make_autotile_id(TileId.autotile_kind(write_id), 0)
			_write_cell(doc, c, write_id)
			dirty.append(c)
			seeds.append(c)
	if not exact_autotile:
		_refresh_autotiles(doc, seeds, dirty)
	_end_batch(doc)
	return dirty


func _read_cell(doc: RefCounted, cell: Vector2i) -> int:
	if layer_z >= 0:
		return int(doc.tile(cell.x, cell.y, layer_z))
	return int(doc.ext_tile(ext_layer, cell.x, cell.y))


func _write_cell(doc: RefCounted, cell: Vector2i, id: int) -> void:
	if layer_z >= 0:
		doc.set_tile(cell.x, cell.y, layer_z, id)
	else:
		doc.set_ext_tile(ext_layer, cell.x, cell.y, id)


func _normalized_paint_id() -> int:
	if TileId.is_autotile(tile_id) and not exact_autotile:
		return TileId.make_autotile_id(TileId.autotile_kind(tile_id), 0)
	return tile_id


func refresh_autotiles(doc: RefCounted, seeds: Array, dirty: Array[Vector2i]) -> void:
	_refresh_autotiles(doc, seeds, dirty)


func refresh_all_floor_autotiles(doc: RefCounted) -> int:
	if doc == null:
		return 0
	var dirty: Array[Vector2i] = []
	var saved_z: int = layer_z
	_begin_batch(doc)
	var cells: Array[Vector2i] = []
	if doc.has_method("uses_chunks") and bool(doc.uses_chunks()) and doc.has_method("cached_chunk_cells"):
		cells = doc.cached_chunk_cells()
	if cells.is_empty() and not (doc.has_method("uses_chunks") and bool(doc.uses_chunks())):
		for y in range(int(doc.height)):
			for x in range(int(doc.width)):
				cells.append(Vector2i(x, y))
	for z in range(2):
		layer_z = z
		for c in cells:
			_update_autotile_on_z(doc, c, z, dirty)
	layer_z = saved_z
	_end_batch(doc)
	return dirty.size()


func _fill(doc: RefCounted, start: Vector2i, new_id: int) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	var w: int = int(doc.width)
	var h: int = int(doc.height)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h:
		return dirty
	var old := _read_cell(doc, start)
	if _same_fill(old, new_id):
		return dirty
	_begin_batch(doc)
	var stack: Array[Vector2i] = [start]
	var seen := {}
	var seeds: Array[Vector2i] = []
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var key := "%d,%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		if not _same_fill(_read_cell(doc, c), old):
			continue
		_write_cell(doc, c, new_id)
		dirty.append(c)
		seeds.append(c)
		var nbs := [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]
		for n in nbs:
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				stack.append(n)
	_refresh_autotiles(doc, seeds, dirty)
	_end_batch(doc)
	return dirty


func _same_fill(a: int, b: int) -> bool:
	if TileId.is_autotile(a) and TileId.is_autotile(b):
		return TileId.autotile_kind(a) == TileId.autotile_kind(b)
	return a == b


func _begin_batch(doc: RefCounted) -> void:
	if doc != null and doc.has_method("begin_undo_batch"):
		doc.begin_undo_batch()


func _end_batch(doc: RefCounted) -> void:
	if doc != null and doc.has_method("end_undo_batch"):
		doc.end_undo_batch()


func _refresh_autotiles(doc: RefCounted, seeds: Array, dirty: Array[Vector2i]) -> void:
	if layer_z < 0:
		return
	var seen := {}
	for seed in seeds:
		var s: Vector2i = seed
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := Vector2i(s.x + dx, s.y + dy)
				var key := "%d,%d" % [n.x, n.y]
				if seen.has(key):
					continue
				seen[key] = true
				_update_autotile_shape(doc, n, dirty)


func _update_autotile_shape(doc: RefCounted, cell: Vector2i, dirty: Array[Vector2i]) -> void:
	_update_autotile_on_z(doc, cell, layer_z, dirty)
	# A1/A2 floors on z0/z1 overlay each other; refresh the other ground layer too
	# so sand next to sand on the other z does not keep a grass fringe.
	if layer_z == 0 or layer_z == 1:
		var other: int = 1 - layer_z
		var oid: int = _read_id_z(doc, cell, other)
		if TileId.is_tile_a1(oid) or TileId.is_tile_a2(oid):
			_update_autotile_on_z(doc, cell, other, dirty)


func _update_autotile_on_z(doc: RefCounted, cell: Vector2i, z: int, dirty: Array[Vector2i]) -> void:
	var id: int = _read_id_z(doc, cell, z)
	if not TileId.is_autotile(id):
		return
	var kind: int = TileId.autotile_kind(id)
	var shape: int = _shape_for(doc, cell, kind, id)
	var new_id: int = TileId.make_autotile_id(kind, shape)
	if new_id == id:
		return
	_write_id_z(doc, cell, z, new_id)
	if not dirty.has(cell):
		dirty.append(cell)


func _read_id_z(doc: RefCounted, cell: Vector2i, z: int) -> int:
	if z < 0:
		return int(doc.ext_tile(ext_layer, cell.x, cell.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= int(doc.width) or cell.y >= int(doc.height):
		return 0
	return int(doc.tile(cell.x, cell.y, z))


func _write_id_z(doc: RefCounted, cell: Vector2i, z: int, id: int) -> void:
	if z < 0:
		doc.set_ext_tile(ext_layer, cell.x, cell.y, id)
	else:
		doc.set_tile(cell.x, cell.y, z, id)


func _shape_for(doc: RefCounted, cell: Vector2i, kind: int, id: int) -> int:
	if TileId.is_waterfall_kind(kind):
		return TileId.waterfall_shape(_is_edge(doc, cell + Vector2i(-1, 0), kind, id), _is_edge(doc, cell + Vector2i(1, 0), kind, id))
	if TileId.is_wall_autotile(id):
		return TileId.wall_shape(
			_is_edge(doc, cell + Vector2i(-1, 0), kind, id),
			_is_edge(doc, cell + Vector2i(0, -1), kind, id),
			_is_edge(doc, cell + Vector2i(1, 0), kind, id),
			_is_edge(doc, cell + Vector2i(0, 1), kind, id)
		)
	return TileId.floor_shape(
		_is_edge(doc, cell + Vector2i(-1, 0), kind, id),
		_is_edge(doc, cell + Vector2i(0, -1), kind, id),
		_is_edge(doc, cell + Vector2i(1, 0), kind, id),
		_is_edge(doc, cell + Vector2i(0, 1), kind, id),
		_is_edge(doc, cell + Vector2i(-1, -1), kind, id),
		_is_edge(doc, cell + Vector2i(1, -1), kind, id),
		_is_edge(doc, cell + Vector2i(1, 1), kind, id),
		_is_edge(doc, cell + Vector2i(-1, 1), kind, id)
	)


func _is_edge(doc: RefCounted, cell: Vector2i, kind: int, sample_id: int = 0) -> bool:
	## True when that neighbor is a border (out of map = same, no edge).
	var w: int = int(doc.width)
	var h: int = int(doc.height)
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return false
	if _same_kind_at(doc, cell, kind, sample_id):
		return false
	return true


func _same_kind_at(doc: RefCounted, cell: Vector2i, kind: int, sample_id: int) -> bool:
	var local_only: bool = TileId.is_waterfall_kind(kind) or TileId.is_wall_autotile(sample_id)
	if local_only:
		var nid: int = _read_cell(doc, cell)
		return TileId.is_autotile(nid) and TileId.autotile_kind(nid) == kind
	# A1/A2 floors: same kind on z0 or z1 counts, so overlay sand joins sand underneath.
	var zs := PackedInt32Array([0, 1])
	if layer_z >= 2:
		zs.append(layer_z)
	for z in zs:
		var idz: int = int(doc.tile(cell.x, cell.y, z))
		if TileId.is_autotile(idz) and TileId.a2_floors_connect(kind, TileId.autotile_kind(idz)):
			return true
	if layer_z < 0:
		var eid: int = int(doc.ext_tile(ext_layer, cell.x, cell.y))
		if TileId.is_autotile(eid) and TileId.a2_floors_connect(kind, TileId.autotile_kind(eid)):
			return true
	return false
