extends RefCounted
## Application layer: engage orchestration (click to attack/interact, pathing, range checks).

const Net = preload("res://scripts/net/net.gd")
const GameSettingsScript = preload("res://scripts/game/game_settings.gd")

static func _player_in_skill_range(ctrl, npc, range_cells: int, pcell: Vector2i) -> bool:
	if npc == null:
		return false
	if range_cells <= 1:
		return ctrl._player_beside_npc(npc, pcell)
	var tcell = ctrl._npc_target_cell(npc)
	if tcell.x <= -9990:
		return false
	return ctrl._cheb(pcell, tcell) <= maxi(range_cells, 1)

static func _skill_chase_range(ctrl, def: Dictionary) -> int:
	if def.is_empty():
		return 1
	var tmode = str(def.get("target_mode", "")).strip_edges().to_lower()
	if tmode.is_empty() and bool(def.get("requires_target", false)):
		tmode = "unit"
	var req = bool(def.get("requires_target", false))
	var rng: int = int(def.get("range", 0))
	var effect = str(def.get("effect", "")).strip_edges()
	if effect == "heal" or effect == "recall" or effect == "teleport_home":
		if not req and tmode != "ground" and tmode != "unit":
			return -1
	if tmode == "none" and not req and rng <= 0:
		return -1
	if not req and tmode != "ground" and tmode != "unit" and rng <= 0:
		return -1
	return maxi(rng, 1)

static func _path_to_npc_range(ctrl, npc, range_cells: int) -> bool:
	if npc == null or ctrl.player == null or not ctrl.player.has_method("click_move_to"):
		return false
	var pcell: Vector2i = ctrl.player.cell
	var tcell = ctrl._npc_target_cell(npc)
	if tcell.x <= -9990:
		return false
	var dest: Vector2i = ctrl._approach_cell(pcell, tcell, range_cells)
	if dest == pcell:
		return true
	return bool(ctrl.player.click_move_to(dest))

static func _request_npc_engage(ctrl, npc) -> void:
	if npc == null or ctrl.player == null:
		return
	if ctrl.player.input_locked:
		return
	var pcell: Vector2i = ctrl.player.cell if "cell" in ctrl.player else Vector2i.ZERO
	var is_hostile = bool(npc.hostile) if "hostile" in npc else false
	if is_hostile:
		ctrl.stop_follow()
		if not ctrl._auto_attack:
			ctrl._auto_attack = true
			if ctrl.hud != null and ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system("自动攻击：开")
		ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
		if ctrl._player_beside_npc(npc, pcell):
			ctrl._clear_pending_engage()
			ctrl._try_attack_npc(npc)
			return
		ctrl._set_pending_engage(npc, "", 1)
		if not ctrl._path_to_npc_range(npc, 1):
			ctrl._clear_pending_engage()
			if ctrl.hud != null and ctrl.hud.has_method("append_system"):
				ctrl.hud.append_system("无法到达该位置")
		return
	if ctrl._player_beside_npc(npc, pcell):
		ctrl._clear_pending_engage()
		ctrl._engage_npc(npc)
		return
	ctrl._set_pending_engage(npc)
	if not ctrl._path_to_npc_range(npc, 1):
		ctrl._clear_pending_engage()
		if ctrl.hud != null and ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system("无法到达该位置")

static func _on_player_path_cancelled(ctrl) -> void:
	# Keyboard / failed step: drop click-to-engage intent.
	ctrl._clear_pending_engage()
	if not ctrl._follow_id.is_empty() and ctrl.player != null:
		var dir_vec = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if dir_vec.length() >= 0.5:
			ctrl.stop_follow()

static func _on_player_arrived_cell(ctrl, cell: Vector2i, path_complete: bool) -> void:
	ctrl._sync_map_observer()
	ctrl._play_footstep()
	ctrl._refresh_npc_nameplates()
	ctrl._refresh_remote_nameplates()
	if GameSettingsScript.flag("auto_pickup", false):
		ctrl._try_auto_pickup_at(cell)
	if ctrl._pending_engage_npc_id.is_empty():
		return
	if ctrl.player != null and ctrl.player.input_locked:
		return
	var npc = ctrl._find_npc_by_id(ctrl._pending_engage_npc_id)
	if npc == null:
		ctrl._clear_pending_engage()
		return
	var sid = ctrl._pending_skill_id
	var rng: int = ctrl._pending_skill_range
	if not sid.is_empty():
		if ctrl._player_in_skill_range(npc, rng, cell):
			ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
			ctrl._pending_skill_id = ""
			ctrl._pending_engage_npc_id = ""
			ctrl._pending_skill_range = 1
			if ctrl.player != null and ctrl.player.has_method("clear_move_path"):
				ctrl.player.clear_move_path()
			ctrl.request_use_skill(sid)
		elif path_complete:
			if not ctrl._path_to_npc_range(npc, rng):
				ctrl._clear_pending_engage()
		return
	var beside = ctrl._player_beside_npc(npc, cell)
	if not beside:
		if path_complete:
			if not ctrl._path_to_npc_range(npc, 1):
				ctrl._clear_pending_engage()
		return
	ctrl._clear_pending_engage()
	if ctrl.player != null and ctrl.player.has_method("clear_move_path"):
		ctrl.player.clear_move_path()
	ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
	ctrl._engage_npc(npc)

static func _engage_npc(ctrl, npc) -> bool:
	## Hostile -> MockServer.try_attack; friendly/script -> try_interact.
	if npc == null:
		return false
	if ctrl.player != null and ctrl.player.input_locked:
		return false
	var is_hostile = bool(npc.hostile) if "hostile" in npc else false
	if is_hostile:
		return ctrl._try_attack_npc(npc)
	return ctrl._try_interact_npc(npc)

static func _try_attack_npc(ctrl, npc) -> bool:
	if npc == null or ctrl.player == null:
		return false
	ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
	# Local FX only (face toward player).
	if npc.has_method("try_interact"):
		npc.try_interact(ctrl.player.cell)
	var srv = Net.server()
	if srv == null or not srv.has_method("try_attack"):
		return true
	var npc_id = str(npc.npc_id) if "npc_id" in npc else ""
	var result: Dictionary = srv.try_attack(npc_id, ctrl.player.cell.x, ctrl.player.cell.y)
	if not bool(result.get("ok", false)):
		return true
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, npc)
	return true

static func _try_interact_npc(ctrl, npc) -> bool:
	if npc == null or ctrl.player == null:
		return false
	# Local FX only (face toward player). Do NOT open Chat from interact_text.
	if npc.has_method("try_interact"):
		npc.try_interact(ctrl.player.cell)
	var srv = Net.server()
	if srv == null or not srv.has_method("try_interact"):
		return true
	var npc_id = str(npc.npc_id) if "npc_id" in npc else ""
	var result: Dictionary = srv.try_interact(npc_id, ctrl.player.cell.x, ctrl.player.cell.y)
	if not bool(result.get("ok", false)):
		return true
	var actions_v: Variant = result.get("actions", [])
	var actions: Array = actions_v if typeof(actions_v) == TYPE_ARRAY else []
	ctrl._apply_server_actions(actions, npc)
	return true

