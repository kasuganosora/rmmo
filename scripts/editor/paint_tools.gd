extends RefCounted
## Pencil / rect / fill / eyedropper against a MapDocument.

const TileId = preload("res://scripts/map/tile_id.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")

enum Tool { PENCIL, RECT, FILL, EYEDROP, ERASE }

var tool: int = Tool.PENCIL
var layer_z: int = 0 ## 0-5 MV; -1 means ext
var ext_layer: String = ""
var tile_id: int = 0
var rect_start: Vector2i = Vector2i(-1, -1)
var exact_autotile: bool = false


func begin_stroke() -> void:
	rect_start = Vector2i(-1, -1)


func apply_cell(doc: RefCounted, cell: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null:
		return dirty
	var id := 0 if erase or tool == Tool.ERASE else _normalized_paint_id()
	if tool == Tool.EYEDROP:
		tile_id = _read_cell(doc, cell)
		return dirty
	if tool == Tool.FILL:
		return _fill(doc, cell, id)
	_begin_batch(doc)
	_write_cell(doc, cell, id)
	dirty.append(cell)
	if not exact_autotile:
		_refresh_autotiles(doc, [cell], dirty)
	_end_batch(doc)
	return dirty


func apply_rect(doc: RefCounted, a: Vector2i, b: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	var id := 0 if erase else _normalized_paint_id()
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	_begin_batch(doc)
	var seeds: Array[Vector2i] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			_write_cell(doc, c, id)
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
	var id: int = _read_cell(doc, cell)
	if not TileId.is_autotile(id):
		return
	var kind := TileId.autotile_kind(id)
	var shape := _shape_for(doc, cell, kind, id)
	var new_id: int = TileId.make_autotile_id(kind, shape)
	if new_id == id:
		return
	_write_cell(doc, cell, new_id)
	if not dirty.has(cell):
		dirty.append(cell)


func _shape_for(doc: RefCounted, cell: Vector2i, kind: int, id: int) -> int:
	if TileId.is_waterfall_kind(kind):
		return TileId.waterfall_shape(_is_edge(doc, cell + Vector2i(-1, 0), kind), _is_edge(doc, cell + Vector2i(1, 0), kind))
	if TileId.is_wall_autotile(id):
		return TileId.wall_shape(
			_is_edge(doc, cell + Vector2i(-1, 0), kind),
			_is_edge(doc, cell + Vector2i(0, -1), kind),
			_is_edge(doc, cell + Vector2i(1, 0), kind),
			_is_edge(doc, cell + Vector2i(0, 1), kind)
		)
	return TileId.floor_shape(
		_is_edge(doc, cell + Vector2i(-1, 0), kind),
		_is_edge(doc, cell + Vector2i(0, -1), kind),
		_is_edge(doc, cell + Vector2i(1, 0), kind),
		_is_edge(doc, cell + Vector2i(0, 1), kind),
		_is_edge(doc, cell + Vector2i(-1, -1), kind),
		_is_edge(doc, cell + Vector2i(1, -1), kind),
		_is_edge(doc, cell + Vector2i(1, 1), kind),
		_is_edge(doc, cell + Vector2i(-1, 1), kind)
	)


func _is_edge(doc: RefCounted, cell: Vector2i, kind: int) -> bool:
	## True when that neighbor is a border (out of map = same, no edge).
	var w: int = int(doc.width)
	var h: int = int(doc.height)
	if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
		return false
	var nid: int = _read_cell(doc, cell)
	if not TileId.is_autotile(nid):
		return true
	return TileId.autotile_kind(nid) != kind
