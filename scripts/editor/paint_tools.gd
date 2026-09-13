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


func begin_stroke() -> void:
	rect_start = Vector2i(-1, -1)


func apply_cell(doc: RefCounted, cell: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	if doc == null:
		return dirty
	var id := 0 if erase or tool == Tool.ERASE else tile_id
	if tool == Tool.EYEDROP:
		tile_id = _read_cell(doc, cell)
		return dirty
	if tool == Tool.FILL:
		return _fill(doc, cell, id)
	_write_cell(doc, cell, id)
	dirty.append(cell)
	if not erase and TileId.is_autotile(id):
		_fix_autotile(doc, cell, dirty)
	return dirty


func apply_rect(doc: RefCounted, a: Vector2i, b: Vector2i, erase: bool = false) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	var id := 0 if erase else tile_id
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			_write_cell(doc, c, id)
			dirty.append(c)
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


func _fill(doc: RefCounted, start: Vector2i, new_id: int) -> Array[Vector2i]:
	var dirty: Array[Vector2i] = []
	var w: int = int(doc.width)
	var h: int = int(doc.height)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h:
		return dirty
	var old := _read_cell(doc, start)
	if old == new_id:
		return dirty
	var stack: Array[Vector2i] = [start]
	var seen := {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var key := "%d,%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		if _read_cell(doc, c) != old:
			continue
		_write_cell(doc, c, new_id)
		dirty.append(c)
		var nbs := [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]
		for n in nbs:
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				stack.append(n)
	return dirty


func _fix_autotile(doc: RefCounted, cell: Vector2i, dirty: Array[Vector2i]) -> void:
	## Place same autotile kind; shape 0 if all 4-neighbors same kind, else keep selected id.
	if layer_z < 0:
		return
	var id: int = _read_cell(doc, cell)
	if not TileId.is_autotile(id):
		return
	var kind := TileId.autotile_kind(id)
	var same := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		var nid: int = _read_cell(doc, n)
		if TileId.is_autotile(nid) and TileId.autotile_kind(nid) == kind:
			same += 1
	if same == 4:
		var shaped: int = TileId.TILE_ID_A1 + kind * 48
		_write_cell(doc, cell, shaped)
		if not dirty.has(cell):
			dirty.append(cell)
