extends Control
## Screen-sized handles projected from the same world axes used by the drag solver.
## Overlay picking stays usable through geometry and never enters saved map data.
const COLORS = [Color("ff706c"), Color("8cde82"), Color("6aaeff")]
const AXES = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const HANDLE_PIXELS := 90.0
var editor: Node3D
var hovered := -1
var active := -1


func setup(owner: Node3D) -> void:
	editor = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true


func _process(_delta: float) -> void:
	visible = editor._mode == 1 and not editor._selection_tools.box_mode and not editor._doc._find(editor._inspector.selection).is_empty()
	if visible:
		hovered = hit_test(get_local_mouse_position())
		queue_redraw()


func pivot() -> Vector3:
	return editor._selection_tools.pivot()


static func vector(record: Dictionary, field: String) -> Vector3:
	var values: Array = record.get(field, [0, 0, 0])
	return Vector3(values[0], values[1], values[2])


func axes_basis() -> Basis:
	if editor._selection_tools.ids.size() > 1: return Basis.IDENTITY
	if editor._local_transform or editor._transform_mode == 2:
		return Basis.from_euler(vector(editor._doc._find(editor._inspector.selection), "rotation") * PI / 180.0)
	return Basis.IDENTITY


func world_length() -> float:
	var camera: Camera3D = editor._camera
	var depth := maxf(0.01, -camera.to_local(pivot()).z)
	# Measure projection using camera-right to avoid FOV/aspect convention assumptions.
	var pixels := camera.unproject_position(pivot()).distance_to(camera.unproject_position(pivot() + camera.global_basis.x * depth))
	return HANDLE_PIXELS * depth / maxf(pixels, 1.0)


func axis_tip(axis: int) -> Vector2:
	return editor._camera.unproject_position(pivot() + axes_basis()[axis] * world_length())


func ring_points(axis: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var basis := axes_basis()
	var center := pivot()
	var radius := world_length() * 0.85
	for index in 65:
		var angle := TAU * index / 64.0
		var point := center + (basis[(axis + 1) % 3] * cos(angle) + basis[(axis + 2) % 3] * sin(angle)) * radius
		if editor._camera.is_position_behind(point): return PackedVector2Array()
		points.append(editor._camera.unproject_position(point))
	return points


func hit_test(screen: Vector2) -> int:
	if editor._selection_tools.whole and editor._transform_mode==2: return -1
	if editor._mode != 1 or editor._doc._find(editor._inspector.selection).is_empty() or editor._camera.is_position_behind(pivot()): return -1
	var center: Vector2 = editor._camera.unproject_position(pivot())
	if editor._transform_mode != 1 and screen.distance_to(center) <= 10.0: return 3
	if editor._transform_mode == 2 and editor._selection_tools.ids.size() > 1: return -1
	var best := 10.0
	var chosen := -1
	for axis in 3:
		if editor._selection_tools.whole and editor._transform_mode==1 and axis!=1: continue
		var distance := INF
		if editor._transform_mode == 1:
			var points := ring_points(axis)
			for index in range(1, points.size()):
				distance = minf(distance, screen.distance_to(Geometry2D.get_closest_point_to_segment(screen, points[index - 1], points[index])))
		else:
			var tip := axis_tip(axis)
			if tip.distance_to(center) < 20.0: continue
			distance = screen.distance_to(Geometry2D.get_closest_point_to_segment(screen, center.lerp(tip, 0.22), tip))
		if distance < best:
			best = distance
			chosen = axis
	return chosen


func _draw() -> void:
	if editor!=null and editor._selection_tools.whole and editor._transform_mode==2: return
	if editor == null or editor._doc._find(editor._inspector.selection).is_empty() or editor._camera.is_position_behind(pivot()): return
	var center: Vector2 = editor._camera.unproject_position(pivot())
	for axis in 3:
		if editor._selection_tools.whole and editor._transform_mode==1 and axis!=1: continue
		if editor._transform_mode == 2 and editor._selection_tools.ids.size() > 1: break
		var color: Color = Color("ffe29a") if axis == active or (active < 0 and axis == hovered) else COLORS[axis]
		if editor._transform_mode == 1:
			var points := ring_points(axis)
			if points.size() > 1:
				draw_polyline(points, Color(0.05, 0.06, 0.08, 0.8), 6.0, true)
				draw_polyline(points, color, 2.5, true)
				draw_string(ThemeDB.fallback_font, points[8 + axis * 7] + Vector2(5, -5), ["X", "Y", "Z"][axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
			continue
		var tip := axis_tip(axis)
		if tip.distance_to(center) < 20.0: continue
		var direction := (tip - center).normalized()
		var normal := direction.orthogonal()
		draw_line(center, tip, Color(0.05, 0.06, 0.08, 0.85), 6, true)
		draw_line(center, tip, color, 3, true)
		if editor._transform_mode == 0:
			draw_colored_polygon(PackedVector2Array([tip + direction * 3, tip - direction * 13 + normal * 6, tip - direction * 13 - normal * 6]), color)
		else:
			draw_rect(Rect2(tip - Vector2(6, 6), Vector2(12, 12)), color)
		draw_string(ThemeDB.fallback_font, tip + direction * 14 + Vector2(-5, 5), ["X", "Y", "Z"][axis], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
	if editor._transform_mode != 1:
		var color := Color("ffe29a") if active == 3 or (active < 0 and hovered == 3) else Color("f1f3f5")
		draw_rect(Rect2(center - Vector2(7, 7), Vector2(14, 14)), Color("252932"))
		draw_rect(Rect2(center - Vector2(7, 7), Vector2(14, 14)), color, false, 2.0)
