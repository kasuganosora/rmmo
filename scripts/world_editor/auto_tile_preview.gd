extends Control
## The brush projects onto an explicit elevation, never onto the previous stroke.
var editor: Node3D


func setup(owner: Node3D) -> void:
	editor = owner
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true


func _process(_delta: float) -> void:
	visible = editor._mode == 0 and editor._selected().has("auto_family")
	if visible: queue_redraw()


func _draw() -> void:
	var screen := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(screen): return
	var camera: Camera3D = editor._camera
	var point: Variant = Plane(Vector3.UP, editor._auto_height).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return
	var spacing: float = editor._auto_cell_size
	var cell := preload("res://scripts/world3d/auto_tile_rules.gd").cell_at(point, spacing)
	var corners := PackedVector2Array()
	for offset: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
		var position := Vector3((cell.x + offset.x) * spacing, editor._auto_height, (cell.y + offset.y) * spacing)
		if camera.is_position_behind(position): return
		corners.append(camera.unproject_position(position))
	var color := Color("ff817b") if editor._auto_erase or Input.is_key_pressed(KEY_SHIFT) else Color("f4d482")
	draw_colored_polygon(corners, Color(color, 0.12))
	corners.append(corners[0])
	draw_polyline(corners, color, 2.0, true)
