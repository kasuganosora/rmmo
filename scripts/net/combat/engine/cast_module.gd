extends RefCounted
## Domain module: cast/channel runtime (player + npc, spend MP+CD at start, interrupt wastes MP).

var ctrl
func _init(c):
	ctrl = c

func is_casting() -> bool:
	return ctrl.cast != null and ctrl.cast.is_busy()



func clear_cast() -> void:
	if ctrl.cast != null:
		ctrl.cast.clear()



func interrupt_cast(reason: String = "move") -> Array:
	if ctrl.cast == null or not ctrl.cast.is_busy():
		return []
	return ctrl.cast.interrupt(reason)



func tick_cast(delta: float) -> Array:
	var actions: Array = []
	if ctrl.cast == null or not ctrl.cast.is_busy():
		return actions
	var tick_r: Dictionary = ctrl.cast.tick(delta)
	actions.append_array(tick_r.get("actions", []))
	if not bool(tick_r.get("finished", false)):
		return actions
	# Snapshot then clear before resolve so nested casts are impossible.
	var snap: Dictionary = ctrl.cast.snapshot()
	ctrl.cast.clear()
	var skill_id = str(snap.get("skill_id", ""))
	var target_id = str(snap.get("target_id", ""))
	var px: int = int(snap.get("player_x", 0))
	var py: int = int(snap.get("player_y", 0))
	var gx: int = int(snap.get("ground_x", -9999))
	var gy: int = int(snap.get("ground_y", -9999))
	var def_v: Variant = snap.get("def", {})
	var def: Dictionary = def_v if typeof(def_v) == TYPE_DICTIONARY else {}
	var mode = str(snap.get("mode", "cast"))
	var sname = str(snap.get("name", skill_id))
	if def.is_empty() and ctrl.skills != null:
		def = ctrl.skills.get_skill(skill_id)
	if def.is_empty() or not ctrl.stats.player_alive():
		actions.append({
			"type": "cast_end",
			"skill_id": skill_id,
			"name": sname,
			"mode": mode,
			"ok": false,
			"cancelled": false,
		})
		return actions
	# Re-validate target at finish (move interrupt should have fired if moved).
	var needs_target: bool = bool(def.get("requires_target", false))
	var tmode = ctrl.skill_target_mode(def)
	var range_cells: int = int(def.get("range", 1))
	if tmode == "ground":
		var gcell: Vector2i = ctrl._resolve_ground_cell(def, target_id, px, py, gx, gy)
		if gcell.x <= -9990:
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "需要选择地点。"})
			actions.append_array(ctrl._player_stat_actions())
			return actions
		if not ctrl._cell_in_range(Vector2i(px, py), gcell, range_cells):
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "地点太远。"})
			actions.append_array(ctrl._player_stat_actions())
			return actions
		gx = gcell.x
		gy = gcell.y
	elif needs_target:
		if target_id.is_empty() or not ctrl.stats.npcs.has(target_id) or int(ctrl.stats.npcs[target_id].get("hp", 0)) <= 0:
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "目标已失效。"})
			actions.append_array(ctrl._player_stat_actions())
			return actions
		if not ctrl._in_range(target_id, px, py, range_cells):
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
			})
			actions.append({"type": "system_message", "text": "目标太远。"})
			actions.append_array(ctrl._player_stat_actions())
			return actions
	var resolve_actions: Array = []
	ctrl._resolve_skill_effect(def, skill_id, target_id, px, py, resolve_actions, gx, gy, "player")
	actions.append_array(resolve_actions)
	actions.append({
		"type": "cast_end",
		"skill_id": skill_id,
		"name": sname,
		"mode": mode,
		"ok": true,
		"cancelled": false,
	})
	return actions



func is_npc_casting(npc_id: String) -> bool:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not ctrl.npc_casts.has(npc_id):
		return false
	var cs = ctrl.npc_casts[npc_id]
	return cs != null and cs.is_busy()



func cancel_npc_cast(npc_id: String, reason: String = "interrupt") -> Array:
	npc_id = npc_id.strip_edges()
	var actions: Array = []
	if npc_id.is_empty() or not ctrl.npc_casts.has(npc_id):
		return actions
	var cs = ctrl.npc_casts[npc_id]
	ctrl.npc_casts.erase(npc_id)
	if cs == null or not cs.is_busy():
		if cs != null:
			cs.clear()
		return actions
	var snap: Dictionary = cs.snapshot()
	cs.clear()
	var sid = str(snap.get("skill_id", ""))
	var sname = str(snap.get("name", sid))
	var mode = str(snap.get("mode", "cast"))
	actions.append({
		"type": "cast_end",
		"skill_id": sid,
		"name": sname,
		"mode": mode,
		"ok": false,
		"cancelled": true,
		"reason": reason,
		"npc_id": npc_id,
		"caster": npc_id,
	})
	return actions



func clear_npc_cast(npc_id: String) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty():
		return
	if ctrl.npc_casts.has(npc_id):
		var cs = ctrl.npc_casts[npc_id]
		if cs != null:
			cs.clear()
		ctrl.npc_casts.erase(npc_id)



func tick_npc_casts(delta: float) -> Array:
	var actions: Array = []
	if ctrl.npc_casts.is_empty():
		return actions
	var done: Array = []
	var ids: Array = ctrl.npc_casts.keys()
	for nid_v in ids:
		var npc_id = str(nid_v)
		var cs = ctrl.npc_casts[npc_id]
		if cs == null or not cs.is_busy():
			done.append(npc_id)
			continue
		if ctrl.stats == null or not ctrl.stats.npcs.has(npc_id) or int(ctrl.stats.npcs[npc_id].get("hp", 0)) <= 0:
			actions.append_array(cancel_npc_cast(npc_id, "dead"))
			continue
		var tick_r: Dictionary = cs.tick(delta)
		for a in tick_r.get("actions", []):
			if typeof(a) == TYPE_DICTIONARY:
				a["npc_id"] = npc_id
				a["caster"] = npc_id
				actions.append(a)
		if not bool(tick_r.get("finished", false)):
			continue
		var snap: Dictionary = cs.snapshot()
		cs.clear()
		done.append(npc_id)
		var skill_id = str(snap.get("skill_id", ""))
		var px: int = int(snap.get("player_x", 0))
		var py: int = int(snap.get("player_y", 0))
		var gx: int = int(snap.get("ground_x", -9999))
		var gy: int = int(snap.get("ground_y", -9999))
		var def_v: Variant = snap.get("def", {})
		var def: Dictionary = def_v if typeof(def_v) == TYPE_DICTIONARY else {}
		var mode = str(snap.get("mode", "cast"))
		var sname = str(snap.get("name", skill_id))
		if def.is_empty() and ctrl.skills != null:
			def = ctrl.skills.get_skill(skill_id)
		if def.is_empty() or not ctrl.stats.player_alive():
			actions.append({
				"type": "cast_end",
				"skill_id": skill_id,
				"name": sname,
				"mode": mode,
				"ok": false,
				"cancelled": false,
				"npc_id": npc_id,
				"caster": npc_id,
			})
			continue
		# Refresh caster cell if still tracked.
		if ctrl.stats.has_method("get_npc_cell"):
			var cell: Vector2i = ctrl.stats.get_npc_cell(npc_id)
			if cell.x > -9990:
				px = cell.x
				py = cell.y
		ctrl._resolve_skill_effect(def, skill_id, "", px, py, actions, gx, gy, npc_id)
		actions.append({
			"type": "cast_end",
			"skill_id": skill_id,
			"name": sname,
			"mode": mode,
			"ok": true,
			"cancelled": false,
			"npc_id": npc_id,
			"caster": npc_id,
		})
		actions.append_array(ctrl._npc_stat_actions(npc_id))
	for nid2 in done:
		ctrl.npc_casts.erase(str(nid2))
	return actions


