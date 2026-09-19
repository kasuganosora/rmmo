extends RefCounted
## Domain module: movement (player cell/move/mount/autorun, respawn/recall, npc respawn).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")

func set_player_cell(x: int, y: int) -> void:
	if ctrl.map_collision != null:
		if ctrl.player_cell.x > -9990:
			ctrl.map_collision.set_extra_blocked(ctrl.player_cell.x, ctrl.player_cell.y, false)
		ctrl.map_collision.set_extra_blocked(x, y, true)
	ctrl.player_cell = Vector2i(x, y)



func player_move_speed_mul() -> float:
	if ctrl.combat_stats == null or ctrl.combat_stats.statuses == null:
		return 1.0
	if ctrl.combat_stats.statuses.has_method("move_speed_mul"):
		return float(ctrl.combat_stats.statuses.move_speed_mul("player"))
	var m: Dictionary = ctrl.combat_stats.statuses.get_mods("player") if ctrl.combat_stats.statuses.has_method("get_mods") else {}
	var v: float = float(m.get("move_speed_mul", 1.0))
	if v < 0.25:
		return 0.25
	if v > 3.0:
		return 3.0
	return v



func player_is_mounted() -> bool:
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("player_is_mounted"):
		return bool(ctrl.combat_engine.player_is_mounted())
	if ctrl.combat_stats == null or ctrl.combat_stats.statuses == null:
		return false
	return ctrl.combat_stats.statuses.has_status("player", "mounted")



func try_mount() -> Dictionary:
	return ctrl.try_use_skill("mount", "", ctrl.player_cell.x, ctrl.player_cell.y)



func try_move(from_x: int, from_y: int, dir: int) -> Dictionary:
	if ctrl.map_collision == null:
		return {"ok": false, "x": from_x, "y": from_y}
	ctrl._ingest_stream_around(Vector2i(from_x, from_y))
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "x": ctrl.player_cell.x, "y": ctrl.player_cell.y}
	# Anti-desync / spoof: client from must match server occupancy.
	if ctrl.player_cell.x > -9990:
		if from_x != ctrl.player_cell.x or from_y != ctrl.player_cell.y:
			return {
				"ok": false,
				"x": ctrl.player_cell.x,
				"y": ctrl.player_cell.y,
				"resync": true,
			}
		from_x = ctrl.player_cell.x
		from_y = ctrl.player_cell.y
	if not TileId.is_dir(dir):
		return {"ok": false, "x": from_x, "y": from_y}
	if not ctrl.map_collision.can_pass(from_x, from_y, dir):
		return {"ok": false, "x": from_x, "y": from_y}
	# v1: player move interrupts cast/channel (still allows the step).
	var interrupt_actions: Array = []
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("is_casting") and ctrl.combat_engine.is_casting():
		if ctrl.combat_engine.cast == null or ctrl.combat_engine.cast.should_interrupt_on_move():
			interrupt_actions = ctrl.combat_engine.interrupt_cast("move")
	var delta: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta.x
	var ny: int = from_y + delta.y
	set_player_cell(nx, ny)
	ctrl._maybe_mark_safe_cell(nx, ny)
	var out = {"ok": true, "x": nx, "y": ny, "facing": dir, "move_speed_mul": player_move_speed_mul()}
	if ctrl.map_collision.has_method("no_dash_at") and ctrl.map_collision.no_dash_at(nx, ny):
		out["no_dash"] = true
	var all_actions: Array = []
	if ctrl.sitting:
		ctrl._stand_if_sitting(all_actions)
	if not interrupt_actions.is_empty():
		all_actions.append_array(interrupt_actions)
	var touch_actions: Array = ctrl._try_player_touch_events(nx, ny)
	if not touch_actions.is_empty():
		all_actions.append_array(touch_actions)
	var sz_actions: Array = ctrl._safe_zone_transition_actions()
	if not sz_actions.is_empty():
		all_actions.append_array(sz_actions)
	if not all_actions.is_empty():
		out["actions"] = all_actions
		# Also buffer for poll_combat_tick consumers that ignore try_move actions.
		ctrl._pending_tick_actions.append_array(all_actions)
	return out



func collect_autorun() -> Array:
	return _collect_autorun()



func _collect_autorun() -> Array:
	if ctrl.event_runtime == null or not ctrl.event_runtime.has_method("collect_autorun"):
		return []
	var acts: Array = ctrl.event_runtime.collect_autorun(ctrl._event_server_ctx())
	if not acts.is_empty():
		ctrl._pending_tick_actions.append_array(acts)
	return acts



func _apply_player_move_actions(result: Dictionary) -> void:
	if result.is_empty() or not bool(result.get("ok", false)):
		return
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	for a in acts_v:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("type", "")) != "player_move":
			continue
		var cell_v: Variant = a.get("cell", {})
		var nx = int(a.get("x", -9999))
		var ny = int(a.get("y", -9999))
		if typeof(cell_v) == TYPE_DICTIONARY:
			nx = int(cell_v.get("x", nx))
			ny = int(cell_v.get("y", ny))
		if nx > -9990 and ny > -9990:
			set_player_cell(nx, ny)




func _gate_recall_item_use() -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var dest: Vector2i = ctrl._town_dest()
	if ctrl.player_cell == dest:
		actions.append({"type": "system_message", "text": "你已在安全点。"})
		return {"ok": false, "reason": "already_safe", "actions": actions}
	return {"ok": true, "actions": []}



func _bind_recall_actions(result: Dictionary) -> void:
	var acts_v: Variant = result.get("actions", [])
	if typeof(acts_v) != TYPE_ARRAY:
		return
	var acts: Array = acts_v
	var dest = ctrl._town_dest()
	var bound = false
	for i in range(acts.size()):
		var a: Variant = acts[i]
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str((a as Dictionary).get("type", "")) != "recall":
			continue
		var rec: Dictionary = a
		if dest.x > -9990:
			rec["cell"] = {"x": dest.x, "y": dest.y}
			set_player_cell(dest.x, dest.y)
		acts[i] = rec
		bound = true
	if bound:
		if ctrl.sitting:
			ctrl._stand_if_sitting(acts)
		ctrl.sitting = false
		ctrl._sit_acc = 0.0
		ctrl._sit_regen_acc = 0.0
	result["actions"] = acts



func _append_respawn_actions(actions: Array, where: String = "town") -> void:
	if ctrl.combat_stats == null:
		return
	# Avoid double-append if already respawned in this action list.
	if ctrl._actions_has_type(actions, "respawn"):
		return
	where = where.strip_edges().to_lower()
	var dest: Vector2i = ctrl.respawn_cell
	var here = where == "here" or where == "place"
	if here and ctrl.death_cell.x > -9990:
		dest = ctrl.death_cell
	elif dest.x <= -9990:
		dest = ctrl.last_safe_cell
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_landable"):
		if not ctrl.map_collision.is_landable(dest.x, dest.y) and ctrl.map_collision.has_method("find_spawn_near"):
			dest = ctrl.map_collision.find_spawn_near(dest.x, dest.y)
	elif ctrl.map_collision != null and ctrl.map_collision.has_method("find_spawn_near") and (dest.x <= -9990):
		dest = ctrl.map_collision.find_spawn_near()
	ctrl._clear_pending_loot_on_death(actions)
	ctrl.combat_stats.restore_after_death(here)
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("clear_cast"):
		ctrl.combat_engine.clear_cast()
	set_player_cell(dest.x, dest.y)
	ctrl.last_safe_cell = dest
	ctrl.sitting = false
	var p: Dictionary = ctrl.combat_stats.player
	actions.append({
		"type": "status_update",
		"target": "player",
		"statuses": [],
	})
	actions.append({
		"type": "respawn",
		"cell": {"x": dest.x, "y": dest.y},
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
		"input_lock_sec": 1.2,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(p.get("hp", 0)),
		"hp_max": int(p.get("hp_max", 0)),
		"mp": int(p.get("mp", 0)),
		"mp_max": int(p.get("mp_max", 0)),
	})
	if here:
		actions.append({"type": "system_message", "text": "你就地复活了。"})
	else:
		actions.append({"type": "system_message", "text": "你已在安全点复活。"})
	ctrl.awaiting_respawn = false



func try_respawn(where: String = "town") -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats != null and ctrl.combat_stats.player_alive() and not ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你还活着。"})
		return {"ok": false, "reason": "alive", "actions": actions}
	ctrl.awaiting_respawn = true
	_append_respawn_actions(actions, where)
	return {"ok": true, "actions": actions}



func try_recall() -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var dest: Vector2i = ctrl._town_dest()
	if ctrl.sitting:
		ctrl._stand_if_sitting(actions)
	ctrl.sitting = false
	ctrl._sit_acc = 0.0
	ctrl._sit_regen_acc = 0.0
	set_player_cell(dest.x, dest.y)
	actions.append({
		"type": "recall",
		"cell": {"x": dest.x, "y": dest.y},
	})
	actions.append({"type": "system_message", "text": "你回到了安全点。"})
	return {"ok": true, "actions": actions}



func _schedule_npc_respawn(npc_id: String) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.combat_stats == null:
		return
	if not ctrl.npc_spawn_templates.has(npc_id):
		return
	var tmpl: Dictionary = ctrl.npc_spawn_templates[npc_id]
	var sec: float = float(tmpl.get("respawn_sec", MobAI.DEFAULT_RESPAWN_SEC))
	if sec < 0.0:
		return  # disabled
	ctrl._npc_respawn_at[npc_id] = ctrl.combat_stats.now_sec() + sec



func _tick_npc_respawns() -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null or ctrl._npc_respawn_at.is_empty():
		return actions
	var now: float = ctrl.combat_stats.now_sec()
	var due: Array = []
	for nid_v in ctrl._npc_respawn_at.keys():
		var nid: String = str(nid_v)
		if now >= float(ctrl._npc_respawn_at[nid]):
			due.append(nid)
	for nid2 in due:
		ctrl._npc_respawn_at.erase(nid2)
		var spawned: Dictionary = _respawn_npc_from_template(str(nid2))
		if not spawned.is_empty():
			actions.append(spawned)
	return actions



func _respawn_npc_from_template(npc_id: String) -> Dictionary:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or not ctrl.npc_spawn_templates.has(npc_id):
		return {}
	# Already alive (e.g. map re-register) → skip.
	if ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(npc_id):
		return {}
	var tmpl: Dictionary = ctrl.npc_spawn_templates[npc_id].duplicate(true)
	var home = Vector2i(0, 0)
	var hv: Variant = tmpl.get("home_cell", tmpl.get("cell", {}))
	if typeof(hv) == TYPE_VECTOR2I:
		home = hv
	elif typeof(hv) == TYPE_DICTIONARY:
		home = Vector2i(int(hv.get("x", 0)), int(hv.get("y", 0)))
	var spawn_cell = home
	if ctrl.map_collision != null:
		var free = true
		if ctrl.map_collision.has_method("is_landable"):
			free = bool(ctrl.map_collision.is_landable(home.x, home.y))
		elif ctrl.map_collision.has_method("is_extra_blocked"):
			free = not bool(ctrl.map_collision.is_extra_blocked(home.x, home.y))
		if not free and ctrl.map_collision.has_method("find_spawn_near"):
			spawn_cell = ctrl.map_collision.find_spawn_near(home.x, home.y)
		# Occupy spawn cell.
		if ctrl.map_collision.has_method("set_extra_blocked"):
			ctrl.map_collision.set_extra_blocked(spawn_cell.x, spawn_cell.y, true)
	var facing: int = int(tmpl.get("direction", 2))
	if not TileId.is_dir(facing):
		facing = 2
	var aggressive: bool = bool(tmpl.get("aggressive", false))
	var wander_r: int = maxi(int(tmpl.get("wander_radius", 0)), 0)
	var gid: int = int(tmpl.get("group_id", 0))
	ctrl.register_npc(
		npc_id,
		spawn_cell.x,
		spawn_cell.y,
		true,
		aggressive,
		facing,
		wander_r,
		gid,
		tmpl,
		home
	)
	# Restore snapshotted combat stats if present.
	if ctrl.combat_stats != null and ctrl.combat_stats.npcs.has(npc_id) and tmpl.has("stats"):
		var st: Dictionary = ctrl.combat_stats.npcs[npc_id]
		var snap_v: Variant = tmpl.get("stats", {})
		if typeof(snap_v) == TYPE_DICTIONARY:
			var snap: Dictionary = snap_v
			var hp_max: int = int(snap.get("hp_max", st.get("hp_max", 30)))
			st["hp_max"] = hp_max
			st["hp"] = hp_max
			var mp_max: int = int(snap.get("mp_max", st.get("mp_max", 0)))
			if mp_max <= 0:
				mp_max = ctrl.combat_stats.npc_mp_max_for(int(st.get("level", 1)), hp_max)
			st["mp_max"] = mp_max
			st["mp"] = mp_max
			if snap.has("atk"):
				st["atk"] = int(snap.get("atk"))
			if snap.has("def"):
				st["def"] = int(snap.get("def"))
			ctrl.combat_stats.npcs[npc_id] = st
	tmpl["cell"] = {"x": spawn_cell.x, "y": spawn_cell.y}
	tmpl["direction"] = facing
	return {"type": "spawn_npc", "npc": tmpl}


