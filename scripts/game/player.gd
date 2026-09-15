extends CharacterBody2D
signal transfer_requested(result: Dictionary)
## Emitted after each successful grid step. path_complete when no waypoints remain.
signal arrived_cell(cell: Vector2i, path_complete: bool)
## Emitted when click-path is cancelled (keyboard / failed step / clear_move_path).
signal path_cancelled()
const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const TileId = preload("res://scripts/map/tile_id.gd")
const Net = preload("res://scripts/net/net.gd")
const GridPath = preload("res://scripts/map/grid_path.gd")
const MV = preload("res://scripts/char/mv_generator.gd")

@export var step_duration: float = 0.16
@export var run_duration: float = 0.09

@onready var anim: AnimatedSprite2D = %Anim

var look_id: String = "1"
var gender: String = LookCatalog.GENDER_FEMALE
var _facing: String = "front"

var cell: Vector2i = Vector2i.ZERO
var moving: bool = false
var input_locked: bool = false
var map_field: Node2D = null

## Click-to-move waypoints (cells to visit; excludes current).
var _move_path: Array[Vector2i] = []
var _dest_marker: Polygon2D = null


func setup(p_look_id: String, p_gender: String = LookCatalog.GENDER_FEMALE, p_customization: Dictionary = {}) -> void:
	look_id = p_look_id if p_look_id != "" else "1"
	gender = LookCatalog.normalize_gender(p_gender)
	if anim == null:
		anim = get_node_or_null("%Anim") as AnimatedSprite2D
	if anim == null:
		return
	var cust: Dictionary = p_customization if typeof(p_customization) == TYPE_DICTIONARY else {}
	var sheet := str(cust.get("mv_sheet", ""))
	if sheet != "":
		var frames := MV.load_sheet_frames(sheet)
		if frames != null:
			anim.sprite_frames = frames
			anim.scale = Vector2(1.35, 1.35)  # MV 部件 48px -> 世界约 64px
		else:
			anim.sprite_frames = LookCatalog.build_walk_frames(look_id, gender)
			anim.scale = LookCatalog.world_sprite_scale(gender)
	else:
		anim.sprite_frames = LookCatalog.build_walk_frames(look_id, gender)
		anim.scale = LookCatalog.world_sprite_scale(gender)
	# 配色已在合成阶段烤进 mv_sheet，这里不再叠加色相 shader（否则二次染色）。
	# Feet on the ground line of the cell (sprite is ~64px; scale applied).
	anim.centered = true
	anim.offset = Vector2(0, -32)  # half of 64px frame; feet on cell bottom
	anim.play("idle_front")
	z_index = 5


func place_at_cell(p_cell: Vector2i, field: Node2D = null) -> void:
	if field != null:
		map_field = field
	cell = p_cell
	if map_field != null and map_field.has_method("cell_to_world"):
		global_position = map_field.cell_to_world(cell)
	moving = false
	clear_move_path()
	# Teleport/spawn: kill Camera2D slide from scene default or prior map.
	snap_camera()


## Instantly align Camera2D onto this node (no enter-map slide).
## Re-enables position smoothing next frame so walk follow stays smooth.
func snap_camera() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
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
	get_tree().process_frame.connect(_reenable_camera_smoothing, CONNECT_ONE_SHOT)


func _reenable_camera_smoothing() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null or not is_instance_valid(cam):
		return
	cam.set_meta("_snap_pending", false)
	cam.position_smoothing_enabled = bool(cam.get_meta("_want_smooth", true))
	cam.reset_smoothing()


func clear_move_path() -> void:
	var had: bool = not _move_path.is_empty()
	_move_path.clear()
	_hide_dest_marker()
	if had:
		path_cancelled.emit()


## Begin following a grid path (server-authoritative steps via try_move).
func set_move_path(path: Array[Vector2i]) -> void:
	_move_path = path.duplicate()
	if _move_path.is_empty():
		_hide_dest_marker()
		return
	_show_dest_marker(_move_path[_move_path.size() - 1])
	if not moving:
		_advance_path_step()


func has_move_path() -> bool:
	return not _move_path.is_empty()


## Left-click target cell: snap/pathfind then walk.
func click_move_to(target: Vector2i) -> bool:
	if input_locked:
		return false
	# Prefer authoritative server collision (live NPC/player occupancy + AStar graph).
	var collision = null
	if Net.server() != null and Net.server().get("map_collision") != null:
		collision = Net.server().map_collision
	elif map_field != null and map_field.get("collision") != null:
		collision = map_field.collision
	if collision == null:
		return false
	if target == cell:
		clear_move_path()
		return true
	var path: Array[Vector2i] = GridPath.find_path_near(collision, cell, target, 6)
	if path.is_empty():
		clear_move_path()
		return false
	set_move_path(path)
	return true


func _physics_process(_delta: float) -> void:
	if input_locked:
		return
	var dir_vec := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir_vec.length() >= 0.5:
		# Keyboard cancels / replaces click path (even mid-step).
		if not _move_path.is_empty():
			clear_move_path()
		if moving:
			return
		var d: int = TileId.dir_from_vec(dir_vec)
		if d == 0:
			return
		_set_facing_from_dir(d)
		_try_step(d)
		return
	if moving:
		return
	if not _move_path.is_empty():
		_advance_path_step()
		return
	_play_idle()


func _advance_path_step() -> void:
	if moving:
		return
	while not _move_path.is_empty() and _move_path[0] == cell:
		_move_path.remove_at(0)
	if _move_path.is_empty():
		_hide_dest_marker()
		_play_idle()
		return
	var next: Vector2i = _move_path[0]
	var delta := next - cell
	if maxi(absi(delta.x), absi(delta.y)) != 1:
		# Path desync — abort.
		clear_move_path()
		_play_idle()
		return
	var d: int = TileId.dir_from_vec(Vector2(delta))
	if d == 0:
		clear_move_path()
		return
	_set_facing_from_dir(d)
	_try_step(d)


func _try_step(d: int) -> void:
	if moving:
		return
	var result: Dictionary = Net.server().try_move(cell.x, cell.y, d)
	if not bool(result.get("ok", false)):
		# Server rejected — snap to authoritative cell when resync requested.
		if bool(result.get("resync", false)):
			var rx: int = int(result.get("x", cell.x))
			var ry: int = int(result.get("y", cell.y))
			cell = Vector2i(rx, ry)
			if map_field != null and map_field.has_method("cell_to_world"):
				global_position = map_field.cell_to_world(cell)
			if TileId.is_dir(int(result.get("facing", 0))):
				_set_facing_from_dir(int(result.get("facing")))
			snap_camera()
		clear_move_path()
		_play_idle()
		return
	var nx: int = int(result.get("x", cell.x))
	var ny: int = int(result.get("y", cell.y))
	cell = Vector2i(nx, ny)
	# Prefer server-authored facing from try_move.
	if TileId.is_dir(int(result.get("facing", 0))):
		_set_facing_from_dir(int(result.get("facing")))
	var target: Vector2 = global_position
	if map_field != null and map_field.has_method("cell_to_world"):
		target = map_field.cell_to_world(cell)
	else:
		var ts: float = 48.0
		target = Vector2(float(nx) * ts + ts * 0.5, float(ny) * ts + ts * 0.5)
	moving = true
	_play_walk()
	var dur := step_duration
	if _sprinting() and not bool(result.get("no_dash", false)):
		dur = run_duration
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(self, "global_position", target, dur)
	tw.finished.connect(_on_step_finished, CONNECT_ONE_SHOT)


func _on_step_finished() -> void:
	moving = false
	if not _move_path.is_empty() and _move_path[0] == cell:
		_move_path.remove_at(0)
	# Warp check after arriving on a cell (keyboard or pathfinding).
	if _try_request_transfer():
		return
	var path_done: bool = _move_path.is_empty()
	arrived_cell.emit(cell, path_done)
	if path_done:
		_hide_dest_marker()
		if Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() < 0.5:
			_play_idle()
		return
	# Continue path on next physics frame (or immediately if no keyboard).
	if Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() >= 0.5:
		clear_move_path()
		_play_idle()


func _try_request_transfer() -> bool:
	var srv = Net.server()
	if srv == null or not srv.has_method("try_transfer"):
		return false
	var result: Dictionary = srv.try_transfer(cell.x, cell.y)
	if not bool(result.get("ok", false)):
		return false
	clear_move_path()
	_play_idle()
	input_locked = true
	transfer_requested.emit(result)
	return true


func set_facing_dir(d: int) -> void:
	_set_facing_from_dir(d)
	_play_idle()


func _set_facing_from_dir(d: int) -> void:
	match d:
		4:
			_facing = "left"
		6:
			_facing = "right"
		7, 8, 9:
			_facing = "back"
		_:
			_facing = "front"


func _play_walk() -> void:
	if anim == null or anim.sprite_frames == null:
		return
	var walk := "walk_%s" % _facing
	if anim.animation != walk:
		anim.play(walk)


func _play_idle() -> void:
	if anim == null or anim.sprite_frames == null:
		return
	var idle := "idle_%s" % _facing
	if anim.sprite_frames.has_animation(idle) and anim.animation != idle:
		anim.play(idle)


func _sprinting() -> bool:
	return Input.is_physical_key_pressed(KEY_SHIFT)


func get_facing() -> String:
	return _facing


func facing_angle() -> float:
	# Screen/world angles: +x right, +y down.
	match _facing:
		"front":
			return PI * 0.5
		"back":
			return -PI * 0.5
		"left":
			return PI
		"right":
			return 0.0
		_:
			return PI * 0.5


func _ensure_dest_marker() -> void:
	if _dest_marker != null and is_instance_valid(_dest_marker):
		return
	_dest_marker = Polygon2D.new()
	_dest_marker.name = "DestMarker"
	_dest_marker.z_index = 4
	_dest_marker.z_as_relative = false
	var half := 10.0
	_dest_marker.polygon = PackedVector2Array([
		Vector2(0, -half),
		Vector2(half, 0),
		Vector2(0, half),
		Vector2(-half, 0),
	])
	_dest_marker.color = Color(0.35, 0.85, 1.0, 0.55)
	_dest_marker.visible = false
	# Parent under map so it uses world coords; fall back to self parent.
	var host: Node = map_field if map_field != null else get_parent()
	if host != null:
		host.add_child(_dest_marker)
	else:
		add_child(_dest_marker)


func _show_dest_marker(dest_cell: Vector2i) -> void:
	_ensure_dest_marker()
	if _dest_marker == null:
		return
	var pos := Vector2.ZERO
	if map_field != null and map_field.has_method("cell_to_world"):
		pos = map_field.cell_to_world(dest_cell)
		# cell_to_world is feet/bottom-center; nudge marker to cell center.
		var ts: float = 48.0
		if map_field.get("tile_size") != null:
			ts = float(map_field.tile_size)
		pos.y -= ts * 0.5
	else:
		pos = Vector2(float(dest_cell.x) * 48.0 + 24.0, float(dest_cell.y) * 48.0 + 24.0)
	_dest_marker.global_position = pos
	_dest_marker.visible = true


func _hide_dest_marker() -> void:
	if _dest_marker != null and is_instance_valid(_dest_marker):
		_dest_marker.visible = false

