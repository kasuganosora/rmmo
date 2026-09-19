extends RefCounted
## Application layer: auto attack toggling, hostile target cycling, attack tick.

const Net = preload("res://scripts/net/net.gd")

static func cycle_hostile_target(ctrl, dir: int = 1) -> void:
	var hostiles: Array = []
	for npc in ctrl._npcs:
		if npc == null or not is_instance_valid(npc):
			continue
		if not ("hostile" in npc and bool(npc.hostile)):
			continue
		hostiles.append(npc)
	if hostiles.is_empty():
		if ctrl.hud != null and ctrl.hud.has_method("append_system"):
			ctrl.hud.append_system("附近没有敌人。")
		return
	if dir == 0:
		dir = 1
	var n: int = hostiles.size()
	var cur = -1
	for i in range(n):
		var npc = hostiles[i]
		var nid = str(npc.npc_id).strip_edges() if "npc_id" in npc else ""
		if nid != "" and nid == ctrl._selected_npc_id:
			cur = i
			break
	if cur < 0:
		ctrl._cycle_index = 0 if dir > 0 else n - 1
	else:
		ctrl._cycle_index = (cur + dir) % n
		if ctrl._cycle_index < 0:
			ctrl._cycle_index += n
	ctrl._select_npc(hostiles[ctrl._cycle_index])

static func toggle_auto_attack(ctrl) -> void:
	ctrl._auto_attack = not ctrl._auto_attack
	if ctrl.hud != null and ctrl.hud.has_method("append_system"):
		ctrl.hud.append_system("自动攻击：%s" % ("开" if ctrl._auto_attack else "关"))

static func is_auto_attack(ctrl) -> bool:
	return ctrl._auto_attack

static func _tick_auto_attack(ctrl, delta: float) -> void:
	if not ctrl._auto_attack or ctrl.player == null or ctrl.player.input_locked:
		return
	if not ctrl._pending_skill_id.is_empty():
		return
	ctrl._auto_attack_cd = maxf(0.0, ctrl._auto_attack_cd - delta)
	if ctrl._auto_attack_cd > 0.0:
		return
	# Duel shell: swing at selected remote opponent when adjacent.
	if not ctrl._selected_remote_id.is_empty():
		var dsrv = Net.server()
		if dsrv != null and dsrv.has_method("in_duel") and dsrv.in_duel():
			var dsnap: Dictionary = dsrv.snapshot_duel() if dsrv.has_method("snapshot_duel") else {}
			if str(dsnap.get("opponent_id", "")) == ctrl._selected_remote_id and dsrv.has_method("try_attack"):
				var mk = ctrl._remote_markers.get(ctrl._selected_remote_id, null)
				var beside = true
				if mk != null and is_instance_valid(mk):
					var cv: Variant = mk.get_meta("cell", Vector2i.ZERO)
					var rcell = Vector2i.ZERO
					if typeof(cv) == TYPE_VECTOR2I:
						rcell = cv
					elif typeof(cv) == TYPE_DICTIONARY:
						rcell = Vector2i(int(cv.get("x", 0)), int(cv.get("y", 0)))
					var pcell: Vector2i = ctrl.player.cell
					beside = maxi(absi(pcell.x - rcell.x), absi(pcell.y - rcell.y)) <= 1
				if beside:
					ctrl._auto_attack_cd = 0.85
					var result: Dictionary = dsrv.try_attack(ctrl._selected_remote_id, ctrl.player.cell.x, ctrl.player.cell.y)
					var acts_v: Variant = result.get("actions", [])
					if typeof(acts_v) == TYPE_ARRAY:
						ctrl._apply_server_actions(acts_v)
				else:
					ctrl._auto_attack_cd = 0.4
				return
	if ctrl._selected_npc_id.is_empty():
		return
	var npc = ctrl._find_npc_by_id(ctrl._selected_npc_id)
	if npc == null or not ("hostile" in npc and bool(npc.hostile)):
		return
	var pcell2: Vector2i = ctrl.player.cell
	if ctrl._player_beside_npc(npc, pcell2):
		ctrl._auto_attack_cd = 0.85
		ctrl._face_toward_cell(ctrl._npc_target_cell(npc))
		ctrl._try_attack_npc(npc)
	elif ctrl.player.has_method("click_move_to") and not ctrl.player.moving:
		ctrl._auto_attack_cd = 0.4
		ctrl._path_to_npc_range(npc, 1)

