extends RefCounted
## Application layer: combat feedback (crit shake, camera frame offset, shake tick).

const GameSettingsScript = preload("res://scripts/game/game_settings.gd")
const CameraShake = preload("res://scripts/game/camera_shake.gd")
const CombatCamera = preload("res://scripts/game/combat_camera.gd")

const Net = preload("res://scripts/net/net.gd")
const CombatFloater = preload("res://scripts/game/combat_floater.gd")

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
	var cam = ctrl.player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if ctrl._camera_shake != null:
		ctrl._camera_shake.apply_to(cam, ctrl._combat_cam_offset)
	else:
		cam.offset = ctrl._combat_cam_offset

static func _spawn_combat_floater(ctrl, 
	world_pos: Vector2,
	text: String,
	_color: Color = Color(),
	kind: String = "damage",
	target_key: String = "default",
	crit: bool = false
) -> Label:
	## Rising Label over target; capped per target_key via CombatFloater.
	if not GameSettingsScript.flag("show_damage_numbers", true):
		return null
	return CombatFloater.spawn(ctrl, world_pos, text, kind, target_key, crit)

static func _resolve_emote_host(ctrl, actor_id: String) -> Node2D:
	## Local player, remote marker, or NPC — whichever matches actor_id.
	actor_id = str(actor_id).strip_edges()
	if actor_id.is_empty() or actor_id == "player":
		return ctrl.player
	var srv = Net.server()
	if srv != null and srv.has_method("_party_self_id"):
		if actor_id == str(srv._party_self_id()):
			return ctrl.player
	if ctrl._remote_markers.has(actor_id):
		var mk = ctrl._remote_markers[actor_id]
		if mk != null and is_instance_valid(mk):
			return mk
	var npc = ctrl._find_npc_by_id(actor_id)
	if npc != null and is_instance_valid(npc):
		return npc
	# Fallback: treat unknown as local self (client-originated emote).
	return ctrl.player

