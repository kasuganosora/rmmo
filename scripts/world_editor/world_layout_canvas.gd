extends Control
## Read-only XZ overview. Screen conversion subtracts the double-precision origin first.
signal placement_selected(placement_id: String)
var space: Dictionary = {}
var diagnostic: Dictionary = {}
var selected_placement := ""
var selected_seam := ""
var _bounds: Array = [0.0, 0.0, 1.0, 1.0]
var _scale := 1.0
var _padding := Vector2(24, 24)
var _hit_rects: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(320, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)
	tooltip_text = "XZ 俯视图：点击矩形选择地图放置。橙色为所选接缝，红色为诊断定位。仅显示布局，不加载邻图。"


func set_view(value: Dictionary, placement_id: String = "", seam_id: String = "", issue: Dictionary = {}) -> void:
	space = value.duplicate(true)
	selected_placement = placement_id
	selected_seam = seam_id
	diagnostic = issue.duplicate(true)
	queue_redraw()


func _placement_rect(placement: Dictionary) -> Array:
	var origin: Array = placement.get("origin_m", [])
	var bounds: Array = placement.get("ownership_xz_m", [])
	if origin.size() != 3 or bounds.size() != 4:
		return []
	return [float(origin[0]) + float(bounds[0]), float(origin[2]) + float(bounds[1]), float(origin[0]) + float(bounds[2]), float(origin[2]) + float(bounds[3])]


func _point(x: float, z: float) -> Vector2:
	return _padding + Vector2((x - float(_bounds[0])) * _scale, (z - float(_bounds[1])) * _scale)


func _fit() -> void:
	var found := false
	for placement: Dictionary in space.get("placements", []):
		var rect := _placement_rect(placement)
		if rect.is_empty(): continue
		if not found:
			_bounds = rect.duplicate()
			found = true
		else:
			_bounds = [minf(_bounds[0], rect[0]), minf(_bounds[1], rect[1]), maxf(_bounds[2], rect[2]), maxf(_bounds[3], rect[3])]
	if not found: _bounds = [0.0, 0.0, 1.0, 1.0]
	var width := maxf(1.0, float(_bounds[2]) - float(_bounds[0]))
	var depth := maxf(1.0, float(_bounds[3]) - float(_bounds[1]))
	_scale = minf(maxf(1.0, size.x - 48.0) / width, maxf(1.0, size.y - 60.0) / depth)
	_padding = Vector2((size.x - width * _scale) * 0.5, (size.y - 20.0 - depth * _scale) * 0.5)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("18212b"))
	_hit_rects.clear()
	_fit()
	var font := ThemeDB.fallback_font
	if space.get("placements", []).is_empty():
		draw_string(font, Vector2(18, 34), "添加地图放置后显示范围与接缝", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("c1cbd6"))
		return
	for placement: Dictionary in space.get("placements", []):
		var bounds := _placement_rect(placement)
		if bounds.is_empty(): continue
		var id := str(placement.get("id", ""))
		var rect := Rect2(_point(bounds[0], bounds[1]), _point(bounds[2], bounds[3]) - _point(bounds[0], bounds[1])).abs()
		_hit_rects[id] = rect
		var highlight := id == selected_placement or _diagnostic_has_placement(id)
		var tint := Color("4b9ba3") if not highlight else Color("e4b55e")
		draw_rect(rect, Color(tint, 0.16))
		draw_rect(rect, tint, false, 3.0 if highlight else 1.5)
		draw_string(font, rect.position + Vector2(6, 18), id, HORIZONTAL_ALIGNMENT_LEFT, maxf(0, rect.size.x - 12), 14, Color("edf0f4"))
	for seam: Dictionary in space.get("seams", []):
		var highlighted := str(seam.get("id", "")) == selected_seam or str(seam.get("id", "")) == str(diagnostic.get("seam_id", ""))
		var color := Color("ffbb60") if highlighted else Color("80ca91")
		for side_name in ["a", "b"]:
			var segment := _seam_segment(seam.get(side_name, {}))
			if segment.size() != 2: continue
			draw_line(segment[0], segment[1], color, 4.0 if highlighted else 2.0)
			if highlighted:
				draw_circle(segment[0], 4, color)
				draw_circle(segment[1], 4, color)
	for position in _diagnostic_points():
		if position is Array and position.size() == 3:
			var p := _point(float(position[0]), float(position[2]))
			draw_circle(p, 6.0, Color("f06c68"))
			draw_line(p - Vector2(9, 0), p + Vector2(9, 0), Color.WHITE, 1.0)
			draw_line(p - Vector2(0, 9), p + Vector2(0, 9), Color.WHITE, 1.0)
	var overlap: Array = diagnostic.get("overlap_xz_m", [])
	if overlap.size() == 4:
		var overlap_rect := Rect2(_point(overlap[0], overlap[1]), _point(overlap[2], overlap[3]) - _point(overlap[0], overlap[1])).abs()
		draw_rect(overlap_rect, Color(0.95, 0.2, 0.2, 0.3))
		draw_rect(overlap_rect, Color("f06c68"), false, 2.0)
	draw_string(font, Vector2(12, size.y - 8), "+X →  +Z ↓  · 米 · 归属范围，非通行证明", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, Color("bdc9d5"))


func _seam_segment(side: Dictionary) -> Array:
	var placement: Dictionary = {}
	for item: Dictionary in space.get("placements", []):
		if item.get("id", "") == side.get("placement_id", ""):
			placement = item
			break
	var bounds: Array = placement.get("ownership_xz_m", [])
	var origin: Array = placement.get("origin_m", [])
	var interval: Array = side.get("interval_m", [])
	if bounds.size() != 4 or origin.size() != 3 or interval.size() != 2: return []
	var edge := str(side.get("edge", ""))
	if edge in ["x_min", "x_max"]:
		var x: float = float(origin[0]) + float(bounds[0 if edge == "x_min" else 2])
		return [_point(x, float(origin[2]) + float(interval[0])), _point(x, float(origin[2]) + float(interval[1]))]
	if edge in ["z_min", "z_max"]:
		var z: float = float(origin[2]) + float(bounds[1 if edge == "z_min" else 3])
		return [_point(float(origin[0]) + float(interval[0]), z), _point(float(origin[0]) + float(interval[1]), z)]
	return []


func _diagnostic_has_placement(id: String) -> bool:
	if diagnostic.get("placement_id", "") == id: return true
	if id in diagnostic.get("placement_ids", []): return true
	for side_name in ["a", "b"]:
		var side: Variant = diagnostic.get(side_name, {})
		if side is Dictionary and side.get("placement_id", "") == id: return true
	return false


func _diagnostic_points() -> Array:
	var points: Array = []
	for key in ["space_position_m", "position_m", "space_a_m", "space_b_m"]:
		if diagnostic.get(key) is Array: points.append(diagnostic[key])
	for key in ["space_segment_a_m", "space_segment_b_m"]:
		for point in diagnostic.get(key, []): points.append(point)
	for point in diagnostic.get("space_points_m", []): points.append(point)
	for side_name in ["a", "b"]:
		var side: Variant = diagnostic.get(side_name, {})
		if side is Dictionary and side.get("space_position_m") is Array:
			points.append(side.space_position_m)
	return points


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for id: String in _hit_rects:
			if _hit_rects[id].has_point(event.position):
				placement_selected.emit(id)
				accept_event()
				return
