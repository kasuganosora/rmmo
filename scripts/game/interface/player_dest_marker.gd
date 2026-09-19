extends RefCounted
## Interface layer: destination marker shown at path end.

static func _ensure_dest_marker(ctrl) -> void:
	if ctrl._dest_marker != null and is_instance_valid(ctrl._dest_marker):
		return
	ctrl._dest_marker = Polygon2D.new()
	ctrl._dest_marker.name = "DestMarker"
	ctrl._dest_marker.z_index = 4
	ctrl._dest_marker.z_as_relative = false
	var half = 10.0
	ctrl._dest_marker.polygon = PackedVector2Array([
		Vector2(0, -half),
		Vector2(half, 0),
		Vector2(0, half),
		Vector2(-half, 0),
	])
	ctrl._dest_marker.color = Color(0.35, 0.85, 1.0, 0.55)
	ctrl._dest_marker.visible = false
	# Parent under map so it uses world coords; fall back to self parent.
	var host: Node = ctrl.map_field if ctrl.map_field != null else ctrl.get_parent()
	if host != null:
		host.add_child(ctrl._dest_marker)
	else:
		ctrl.add_child(ctrl._dest_marker)

static func _show_dest_marker(ctrl, dest_cell: Vector2i) -> void:
	ctrl._ensure_dest_marker()
	if ctrl._dest_marker == null:
		return
	var pos = Vector2.ZERO
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		pos = ctrl.map_field.cell_to_world(dest_cell)
		# cell_to_world is feet/bottom-center; nudge marker to cell center.
		var ts: float = 48.0
		if ctrl.map_field.get("tile_size") != null:
			ts = float(ctrl.map_field.tile_size)
		pos.y -= ts * 0.5
	else:
		pos = Vector2(float(dest_cell.x) * 48.0 + 24.0, float(dest_cell.y) * 48.0 + 24.0)
	ctrl._dest_marker.global_position = pos
	ctrl._dest_marker.visible = true

static func _hide_dest_marker(ctrl) -> void:
	if ctrl._dest_marker != null and is_instance_valid(ctrl._dest_marker):
		ctrl._dest_marker.visible = false

