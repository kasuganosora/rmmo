extends Label
## The discreet page number doubles as the bar's drag handle and settings entry.
signal settings_requested(point: Vector2)
var panel: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			settings_requested.emit(get_global_transform_with_canvas() * event.position)
		accept_event()
		return
	if panel != null:
		# Reuse HUD pointer capture, snapping and persistence without a visible title bar.
		var forwarded: InputEvent = event.duplicate()
		if event is InputEventMouse:
			forwarded.position = panel.get_global_transform().affine_inverse() * (get_global_transform() * event.position)
		panel._gui_input(forwarded)
