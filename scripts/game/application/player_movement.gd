extends RefCounted
## Application layer: grid movement, pathfinding, server-authoritative steps.

const TileId = preload("res://scripts/map/tile_id.gd")
const Net = preload("res://scripts/net/net.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

static func place_at_cell(ctrl, p_cell: Vector2i, field: Node2D = null) -> void:
	if field != null:
		ctrl.map_field = field
	ctrl.cell = p_cell
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		ctrl.global_position = ctrl.map_field.cell_to_world(ctrl.cell)
	ctrl.moving = false
	ctrl.clear_move_path()
	# Teleport/spawn: kill Camera2D slide from scene default or prior map.
	ctrl.snap_camera()

static func clear_move_path(ctrl) -> void:
	var had: bool = not ctrl._move_path.is_empty()
	ctrl._move_path.clear()
	ctrl._hide_dest_marker()
	if had:
		ctrl.path_cancelled.emit()

static func set_move_path(ctrl, path: Array[Vector2i]) -> void:
	ctrl._move_path = path.duplicate()
	if ctrl._move_path.is_empty():
		ctrl._hide_dest_marker()
		return
	ctrl._show_dest_marker(ctrl._move_path[ctrl._move_path.size() - 1])
	if not ctrl.moving:
		ctrl._advance_path_step()

static func has_move_path(ctrl) -> bool:
	return not ctrl._move_path.is_empty()

static func click_move_to(ctrl, target: Vector2i) -> bool:
	if ctrl.input_locked:
		return false
	# Prefer authoritative server collision (live NPC/player occupancy + AStar graph).
	var collision = null
	if Net.server() != null and Net.server().get("map_collision") != null:
		collision = Net.server().map_collision
	elif ctrl.map_field != null and ctrl.map_field.get("collision") != null:
		collision = ctrl.map_field.collision
	if collision == null:
		return false
	if target == ctrl.cell:
		ctrl.clear_move_path()
		return true
	var path: Array[Vector2i] = GridPath.find_path_near(collision, ctrl.cell, target, 6)
	if path.is_empty():
		ctrl.clear_move_path()
		return false
	ctrl.set_move_path(path)
	return true

static func _advance_path_step(ctrl) -> void:
	if ctrl.moving:
		return
	while not ctrl._move_path.is_empty() and ctrl._move_path[0] == ctrl.cell:
		ctrl._move_path.remove_at(0)
	if ctrl._move_path.is_empty():
		ctrl._hide_dest_marker()
		ctrl._play_idle()
		return
	var next: Vector2i = ctrl._move_path[0]
	var delta = next - ctrl.cell
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		# Path desync — abort.
		ctrl.clear_move_path()
		ctrl._play_idle()
		return
	var d: int = TileId.dir_from_vec(Vector2(delta))
	if d == 0:
		ctrl.clear_move_path()
		return
	ctrl._set_facing_from_dir(d)
	ctrl._try_step(d)

static func _try_step(ctrl, d: int) -> void:
	if ctrl.moving:
		return
	var result: Dictionary = Net.server().try_move(ctrl.cell.x, ctrl.cell.y, d)
	if not bool(result.get("ok", false)):
		# Server rejected — snap to authoritative cell when resync requested.
		if bool(result.get("resync", false)):
			var rx: int = int(result.get("x", ctrl.cell.x))
			var ry: int = int(result.get("y", ctrl.cell.y))
			ctrl.cell = Vector2i(rx, ry)
			if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
				ctrl.global_position = ctrl.map_field.cell_to_world(ctrl.cell)
			if TileId.is_dir(int(result.get("facing", 0))):
				ctrl._set_facing_from_dir(int(result.get("facing")))
			ctrl.snap_camera()
		ctrl.clear_move_path()
		ctrl._play_idle()
		return
	var nx: int = int(result.get("x", ctrl.cell.x))
	var ny: int = int(result.get("y", ctrl.cell.y))
	ctrl.cell = Vector2i(nx, ny)
	# Prefer server-authored facing from try_move.
	if TileId.is_dir(int(result.get("facing", 0))):
		ctrl._set_facing_from_dir(int(result.get("facing")))
	var target: Vector2 = ctrl.global_position
	if ctrl.map_field != null and ctrl.map_field.has_method("cell_to_world"):
		target = ctrl.map_field.cell_to_world(ctrl.cell)
	else:
		var ts: float = 48.0
		target = Vector2(float(nx) * ts + ts * 0.5, float(ny) * ts + ts * 0.5)
	ctrl.moving = true
	ctrl._play_walk()
	var dur = ctrl.step_duration
	if ctrl._sprinting() and not bool(result.get("no_dash", false)):
		dur = ctrl.run_duration
	var mul = float(result.get("move_speed_mul", 1.0))
	if mul < 0.25:
		mul = 0.25
	elif mul > 3.0:
		mul = 3.0
	if mul != 1.0:
		dur = dur / mul
	var tw = ctrl.create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(ctrl, "global_position", target, dur)
	tw.finished.connect(ctrl._on_step_finished, CONNECT_ONE_SHOT)

static func _on_step_finished(ctrl) -> void:
	ctrl.moving = false
	if not ctrl._move_path.is_empty() and ctrl._move_path[0] == ctrl.cell:
		ctrl._move_path.remove_at(0)
	# Warp check after arriving on a cell (keyboard or pathfinding).
	if ctrl._try_request_transfer():
		return
	var path_done: bool = ctrl._move_path.is_empty()
	ctrl.arrived_cell.emit(ctrl.cell, path_done)
	if path_done:
		ctrl._hide_dest_marker()
		if Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() < 0.5:
			ctrl._play_idle()
		return
	# Continue path on next physics frame (or immediately if no keyboard).
	if Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() >= 0.5:
		ctrl.clear_move_path()
		ctrl._play_idle()

static func _try_request_transfer(ctrl) -> bool:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_transfer"):
		return false
	var result: Dictionary = srv.try_transfer(ctrl.cell.x, ctrl.cell.y)
	if not bool(result.get("ok", false)):
		return false
	ctrl.clear_move_path()
	ctrl._play_idle()
	ctrl.input_locked = true
	ctrl.transfer_requested.emit(result)
	return true

static func step_duration_with_mul(ctrl, base_duration: float, move_speed_mul: float = 1.0) -> float:
	var mul = float(move_speed_mul)
	if mul < 0.25:
		mul = 0.25
	elif mul > 3.0:
		mul = 3.0
	if mul == 0.0:
		mul = 1.0
	return float(base_duration) / mul

static func _sprinting(ctrl) -> bool:
	if GameSettingsScript.flag("always_run", false):
		return true
	return Input.is_physical_key_pressed(KEY_SHIFT)

