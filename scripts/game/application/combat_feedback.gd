extends RefCounted
## Application layer: combat feedback (crit shake, camera frame offset, shake tick).

const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const CameraShake = preload("res://scripts/game/camera_shake.gd")
const CombatCamera = preload("res://scripts/game/combat_camera.gd")

static func _trigger_crit_shake(ctrl) -> void:
	## Brief Camera2D.offset jitter on crit; gated by GameSettings.screen_shake.
	if not GameSettingsScript.flag("screen_shake", true):
		return
	if ctrl._camera_shake == null:
		ctrl._camera_shake = CameraShake.new()
	ctrl._camera_shake.trigger()

static func _desired_combat_frame_offset(ctrl) -> Vector2:
	## Soft bias toward selected hostile; ZERO when off / no hostile / invalid.
	if not GameSettingsScript.flag("combat_camera_frame", true):
		return Vector2.ZERO
	if ctrl.player == null or not is_instance_valid(ctrl.player):
		return Vector2.ZERO
	if ctrl._selected_npc_id.is_empty():
		return Vector2.ZERO
	var npc = ctrl._find_npc_by_id(ctrl._selected_npc_id)
	if npc == null or not is_instance_valid(npc):
		return Vector2.ZERO
	if not ("hostile" in npc and bool(npc.hostile)):
		return Vector2.ZERO
	return CombatCamera.compute_frame_offset(ctrl.player.global_position, npc.global_position)

static func _tick_camera_shake(ctrl, delta: float) -> void:
	## Lerp combat frame offset, then apply shake additively on Camera2D.offset.
	var desired: Vector2 = ctrl._desired_combat_frame_offset()
	ctrl._combat_cam_offset = CombatCamera.lerp_offset(ctrl._combat_cam_offset, desired, delta)
	if ctrl._camera_shake != null:
		ctrl._camera_shake.tick(delta)
	if ctrl.player == null or not is_instance_valid(ctrl.player):
		return
	var cam := ctrl.player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if ctrl._camera_shake != null:
		ctrl._camera_shake.apply_to(cam, ctrl._combat_cam_offset)
	else:
		cam.offset = ctrl._combat_cam_offset

