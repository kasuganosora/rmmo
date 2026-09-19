extends RefCounted
## Application layer: follow-target orchestration.

static func start_follow(ctrl, target_id: String) -> void:
	target_id = target_id.strip_edges()
	if target_id.is_empty():
		return
	ctrl._follow_id = target_id
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("开始跟随。")
	ctrl._tick_follow()

static func stop_follow(ctrl) -> void:
	if ctrl._follow_id.is_empty():
		return
	ctrl._follow_id = ""
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("停止跟随。")

static func is_following(ctrl) -> bool:
	return not ctrl._follow_id.is_empty()

static func get_follow_id(ctrl) -> String:
	return ctrl._follow_id

static func _tick_follow(ctrl) -> void:
	if ctrl._follow_id.is_empty() or ctrl.player == null or ctrl.player.input_locked:
		return
	if ctrl.player.moving:
		return
	var tcell = ctrl._follow_target_cell()
	if tcell.x <= -9990:
		ctrl.stop_follow()
		return
	var pcell: Vector2i = ctrl.player.cell
	var dist: int = maxi(absi(pcell.x - tcell.x), absi(pcell.y - tcell.y))
	if dist <= 1:
		return
	if ctrl.player.has_method("click_move_to"):
		ctrl.player.click_move_to(tcell)

static func _follow_target_cell(ctrl) -> Vector2i:
	if ctrl._remote_markers.has(ctrl._follow_id):
		var mk = ctrl._remote_markers[ctrl._follow_id]
		if mk != null and is_instance_valid(mk) and mk.has_meta("cell"):
			return mk.get_meta("cell")
	var npc = ctrl._find_npc_by_id(ctrl._follow_id)
	if npc != null and "cell" in npc:
		return npc.cell
	return Vector2i(-9999, -9999)

