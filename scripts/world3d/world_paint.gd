extends RefCounted
## One ground stroke is one undo step. Cells are 4 m and stored at their centers.

const CELL_M := 4.0

var _open := false
var _cells := {}


static func cell_for(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL_M)), int(floor(point.z / CELL_M)))


static func cell_center(cell: Vector2i, top_y: float) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * CELL_M, top_y, (float(cell.y) + 0.5) * CELL_M)


func begin(doc) -> void:
	doc.begin_change()
	_open = true
	_cells = {}


func add(doc, point: Vector3, module: Dictionary) -> String:
	if not _open:
		begin(doc)
	var cell := cell_for(point)
	if _cells.has(cell):
		return ""
	_cells[cell] = true
	var size: Vector3 = module.get("size", Vector3(CELL_M, 0.2, CELL_M))
	var rotation: Vector3 = module.get("rotation", Vector3.ZERO)
	var top_y := point.y
	var center := cell_center(cell, top_y - size.y * 0.5)
	return doc.add_box_silent(str(module.get("surface_id", "ground")), center, size, rotation)


func end() -> int:
	var count := _cells.size()
	_open = false
	_cells = {}
	return count
