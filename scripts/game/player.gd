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
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const Customization = preload("res://scripts/char/customization.gd")
const HurtFlash = preload("res://scripts/game/hurt_flash.gd")
const PlayerMovement = preload("res://scripts/game/application/player_movement.gd")
const PlayerAppearance = preload("res://scripts/game/application/player_appearance.gd")
const PlayerCamera = preload("res://scripts/game/application/player_camera.gd")
const PlayerDestMarker = preload("res://scripts/game/interface/player_dest_marker.gd")
const PlayerFacing = preload("res://scripts/game/application/player_facing.gd")

@export var step_duration: float = 0.16
@export var run_duration: float = 0.09

@onready var anim: AnimatedSprite2D = %Anim

var look_id: String = "1"
var gender: String = LookCatalog.GENDER_FEMALE
var _facing: String = "front"

var cell: Vector2i = Vector2i.ZERO
var moving: bool = false
var input_locked: bool = false
var sitting: bool = false
var map_field: Node2D = null

## Click-to-move waypoints (cells to visit; excludes current).
var _move_path: Array[Vector2i] = []
var _dest_marker: Polygon2D = null
var _weapon_spr: Sprite2D = null
var _hurt_flash = HurtFlash.new()

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

## Incoming-damage feedback. World calls this only for target == "player".
func flash_hurt() -> void:
	if anim == null:
		anim = get_node_or_null("%Anim") as AnimatedSprite2D
	_hurt_flash.trigger(anim)

func is_hurt_flashing() -> bool:
	return _hurt_flash.is_active()

func apply_gear_look(ch: Dictionary, equipment: Array, catalog = null) -> void:
	PlayerAppearance.apply_gear_look(self, ch, equipment, catalog)
func _sync_weapon_overlay(equipment: Array) -> void:
	PlayerAppearance._sync_weapon_overlay(self, equipment)
func _place_weapon_overlay() -> void:
	PlayerAppearance._place_weapon_overlay(self, )
func _load_equip_tex(item_id: String) -> Texture2D:
	return PlayerAppearance._load_equip_tex(self, item_id)
func apply_camera_zoom(z: float) -> void:
	PlayerCamera.apply_camera_zoom(self, z)
func place_at_cell(p_cell: Vector2i, field: Node2D = null) -> void:
	PlayerMovement.place_at_cell(self, p_cell, field)
## Instantly align Camera2D onto this node (no enter-map slide).
## Re-enables position smoothing next frame so walk follow stays smooth.
func snap_camera() -> void:
	PlayerCamera.snap_camera(self, )
func _reenable_camera_smoothing() -> void:
	PlayerCamera._reenable_camera_smoothing(self, )
func set_sitting(on: bool) -> void:
	sitting = on
	if on:
		clear_move_path()
		_play_idle()

func clear_move_path() -> void:
	PlayerMovement.clear_move_path(self, )
## Begin following a grid path (server-authoritative steps via try_move).
func set_move_path(path: Array[Vector2i]) -> void:
	PlayerMovement.set_move_path(self, path)
func has_move_path() -> bool:
	return PlayerMovement.has_move_path(self, )
## Left-click target cell: snap/pathfind then walk.
func click_move_to(target: Vector2i) -> bool:
	return PlayerMovement.click_move_to(self, target)
func _physics_process(delta: float) -> void:
	_hurt_flash.tick(delta)
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
	PlayerMovement._advance_path_step(self, )
func _try_step(d: int) -> void:
	PlayerMovement._try_step(self, d)
func _on_step_finished() -> void:
	PlayerMovement._on_step_finished(self, )
func _try_request_transfer() -> bool:
	return PlayerMovement._try_request_transfer(self, )
func set_facing_dir(d: int) -> void:
	PlayerFacing.set_facing_dir(self, d)
func _set_facing_from_dir(d: int) -> void:
	PlayerFacing._set_facing_from_dir(self, d)
func _play_walk() -> void:
	PlayerFacing._play_walk(self, )
func _play_idle() -> void:
	PlayerFacing._play_idle(self, )
## Effective step tween duration after move_speed_mul (for tests / tooling).
func step_duration_with_mul(base_duration: float, move_speed_mul: float = 1.0) -> float:
	return PlayerMovement.step_duration_with_mul(self, base_duration, move_speed_mul)
func _sprinting() -> bool:
	return PlayerMovement._sprinting(self, )
func get_facing() -> String:
	return _facing

func facing_angle() -> float:
	return PlayerFacing.facing_angle(self, )
func _ensure_dest_marker() -> void:
	PlayerDestMarker._ensure_dest_marker(self, )
func _show_dest_marker(dest_cell: Vector2i) -> void:
	PlayerDestMarker._show_dest_marker(self, dest_cell)
func _hide_dest_marker() -> void:
	PlayerDestMarker._hide_dest_marker(self, )