extends Node2D
## Ground-target preview: filled cells for the pending skill AoE.

var _cells: Array[Vector2i] = []
var _center: Vector2i = Vector2i(-9999, -9999)
var _map_field: Node2D = null
var _ok: bool = true


func setup(map_field: Node2D) -> void:
	_map_field = map_field
	z_index = 8
	queue_redraw()


func set_preview(center: Vector2i, cells: Array[Vector2i], in_range: bool) -> void:
	_center = center
	_cells = cells
	_ok = in_range
	queue_redraw()


func clear_preview() -> void:
	_cells.clear()
	_center = Vector2i(-9999, -9999)
	queue_redraw()


func _tile_size() -> float:
	if _map_field != null and "tile_size" in _map_field:
		return float(maxi(int(_map_field.tile_size), 1))
	return 48.0


func _cell_center(cell: Vector2i) -> Vector2:
	if _map_field != null and _map_field.has_method("cell_to_world"):
		var p: Vector2 = _map_field.cell_to_world(cell)
		var ts := _tile_size()
		p.y -= ts * 0.5
		return p
	var ts2 := _tile_size()
	return Vector2(float(cell.x) * ts2 + ts2 * 0.5, float(cell.y) * ts2 + ts2 * 0.5)


func _draw() -> void:
	if _cells.is_empty():
		return
	var ts := _tile_size()
	var fill := Color(0.95, 0.55, 0.15, 0.28) if _ok else Color(0.85, 0.2, 0.15, 0.28)
	var edge := Color(0.98, 0.82, 0.25, 0.85) if _ok else Color(0.95, 0.3, 0.2, 0.85)
	var half := ts * 0.46
	for cell in _cells:
		var c := _cell_center(cell)
		var pts := PackedVector2Array([
			c + Vector2(0, -half),
			c + Vector2(half, 0),
			c + Vector2(0, half),
			c + Vector2(-half, 0),
		])
		draw_colored_polygon(pts, fill)
		draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.5, true)
	if _center.x > -9990:
		var cc := _cell_center(_center)
		draw_arc(cc, ts * 0.22, 0.0, TAU, 20, edge, 2.0, true)
