extends RefCounted
## Application layer: camera zoom and snap-to-player smoothing.

static func apply_camera_zoom(ctrl, z: float) -> void:
	var cam = ctrl.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	z = clampf(z, 0.6, 2.0)
	cam.zoom = Vector2(z, z)

static func snap_camera(ctrl) -> void:
	var cam = ctrl.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if not cam.has_meta("_want_smooth"):
		cam.set_meta("_want_smooth", cam.position_smoothing_enabled)
	cam.position_smoothing_enabled = false
	cam.reset_smoothing()
	if cam.has_method("force_update_scroll"):
		cam.force_update_scroll()
	if cam.get_meta("_snap_pending", false):
		return
	cam.set_meta("_snap_pending", true)
	ctrl.get_tree().process_frame.connect(ctrl._reenable_camera_smoothing, CONNECT_ONE_SHOT)

static func _reenable_camera_smoothing(ctrl) -> void:
	var cam = ctrl.get_node_or_null("Camera2D") as Camera2D
	if cam == null or not is_instance_valid(cam):
		return
	cam.set_meta("_snap_pending", false)
	cam.position_smoothing_enabled = bool(cam.get_meta("_want_smooth", true))
	cam.reset_smoothing()

