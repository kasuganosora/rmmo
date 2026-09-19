extends RefCounted
## Domain module: remote-player shells (spawn/despawn/patrol, lookup).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const REMOTE_WANDER_RADIUS := 4
const AUTO_SPAWN_SHELL_REMOTES := true
const SHELL_REMOTE_NAMES := ["旅人甲", "旅人乙", "旅人丙"]

func _target_is_remote_player(target_id: String) -> bool:
	target_id = str(target_id).strip_edges()
	if target_id.is_empty():
		return false
	if ctrl._remote_players.has(target_id):
		return true
	# Name match against spawned remotes.
	for rid in ctrl._remote_players.keys():
		var row: Variant = ctrl._remote_players[rid]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("name", "")).strip_edges() == target_id:
			return true
	return false



func snapshot_remote_players() -> Array:
	var out: Array = []
	for rid in ctrl._remote_players.keys():
		var d: Variant = ctrl._remote_players[rid]
		if typeof(d) == TYPE_DICTIONARY:
			out.append((d as Dictionary).duplicate(true))
	return out



func get_remote_player(remote_id: String) -> Dictionary:
	remote_id = remote_id.strip_edges()
	if remote_id.is_empty() or not ctrl._remote_players.has(remote_id):
		return {}
	return (ctrl._remote_players[remote_id] as Dictionary).duplicate(true)



func find_remote_by_name(remote_name: String) -> String:
	remote_name = remote_name.strip_edges()
	if remote_name.is_empty():
		return ""
	for rid in ctrl._remote_players.keys():
		var d: Variant = ctrl._remote_players[rid]
		if typeof(d) == TYPE_DICTIONARY and str(d.get("name", "")) == remote_name:
			return str(rid)
	# Case-insensitive fallback
	var low = remote_name.to_lower()
	for rid2 in ctrl._remote_players.keys():
		var d2: Variant = ctrl._remote_players[rid2]
		if typeof(d2) == TYPE_DICTIONARY and str(d2.get("name", "")).to_lower() == low:
			return str(rid2)
	return ""



func _remote_spawn_action(remote_id: String) -> Dictionary:
	var d: Dictionary = get_remote_player(remote_id)
	return {"type": "remote_spawn", "player": d}



func _ensure_shell_remotes(want: int = 1) -> void:
	if not AUTO_SPAWN_SHELL_REMOTES:
		return
	want = clampi(want, 0, SHELL_REMOTE_NAMES.size())
	var i = 0
	while ctrl._remote_players.size() < want and i < SHELL_REMOTE_NAMES.size():
		var nm: String = str(SHELL_REMOTE_NAMES[i])
		i += 1
		if find_remote_by_name(nm) != "":
			continue
		var r: Dictionary = try_remote_debug_spawn(nm)
		# Strip chatty system lines from pending — spawn already applied into _remote_players.
		if not bool(r.get("ok", false)):
			continue



func _shell_remote_spawn_actions() -> Array:
	var acts: Array = []
	for rid in ctrl._remote_players.keys():
		acts.append(_remote_spawn_action(str(rid)))
	return acts



func try_remote_debug_spawn(display_name: String = "") -> Dictionary:
	var actions: Array = []
	display_name = str(display_name).strip_edges()
	if display_name.is_empty():
		display_name = "旅人甲"
	# Avoid duplicate names
	if find_remote_by_name(display_name) != "":
		display_name = "%s%d" % [display_name, ctrl._next_remote_seq]
	var rid = "remote_%d" % ctrl._next_remote_seq
	ctrl._next_remote_seq += 1
	var pc = ctrl._player_xy()
	# Prefer a free adjacent cell (right, then down, …).
	var offsets: Array = [
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
		Vector2i(3, 1), Vector2i(-3, 1), Vector2i(1, 3),
	]
	var cell = Vector2i(pc.x + 2, pc.y)
	for off_v in offsets:
		var off: Vector2i = off_v
		var cand = Vector2i(pc.x + off.x, pc.y + off.y)
		var blocked = false
		if ctrl.map_collision != null and ctrl.map_collision.has_method("is_blocked"):
			blocked = bool(ctrl.map_collision.is_blocked(cand.x, cand.y))
		if cand == pc:
			blocked = true
		for other in ctrl._remote_players.values():
			if typeof(other) != TYPE_DICTIONARY:
				continue
			var oc: Variant = other.get("cell", {})
			if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == cand.x and int(oc.get("y", -9999)) == cand.y:
				blocked = true
				break
		if not blocked:
			cell = cand
			break
	var gender = "female" if (ctrl._next_remote_seq % 2) == 1 else "male"
	ctrl._remote_players[rid] = {
		"id": rid,
		"name": display_name,
		"cell": {"x": cell.x, "y": cell.y},
		"home": {"x": cell.x, "y": cell.y},
		"wander_radius": REMOTE_WANDER_RADIUS,
		"idle_wander_acc": 0.0,
		"facing": 2,
		"kind": "player",
		"gender": gender,
		"look_id": "1",
		"level": 1,
		"equipment": [],
	}
	actions.append(_remote_spawn_action(rid))
	actions.append({
		"type": "system_message",
		"text": "调试：假玩家【%s】出现在附近（%d,%d）。" % [display_name, cell.x, cell.y],
	})
	return {"ok": true, "remote_id": rid, "actions": actions}




func _tick_remote_patrol(dt: float) -> Array:
	var actions: Array = []
	if ctrl._remote_players.is_empty():
		return actions
	var pc = ctrl._player_xy()
	for rid in ctrl._remote_players.keys():
		var d: Variant = ctrl._remote_players[rid]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = d
		var wander_r: int = maxi(int(row.get("wander_radius", REMOTE_WANDER_RADIUS)), 0)
		if wander_r <= 0:
			continue
		row["idle_wander_acc"] = float(row.get("idle_wander_acc", 0.0)) + dt
		if float(row.get("idle_wander_acc", 0.0)) < MobAI.IDLE_WANDER_INTERVAL_SEC:
			ctrl._remote_players[rid] = row
			continue
		row["idle_wander_acc"] = 0.0
		var cell_v: Variant = row.get("cell", {})
		if typeof(cell_v) != TYPE_DICTIONARY:
			ctrl._remote_players[rid] = row
			continue
		var cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
		var home_v: Variant = row.get("home", cell_v)
		if typeof(home_v) != TYPE_DICTIONARY:
			home_v = cell_v
		var home = Vector2i(int(home_v.get("x", cell.x)), int(home_v.get("y", cell.y)))
		var wdir: int = MobAI.next_idle_wander_dir(ctrl.map_collision, cell, home, wander_r)
		if wdir == 0:
			ctrl._remote_players[rid] = row
			continue
		var delta: Vector2i = TileId.dir_delta(wdir)
		var next = Vector2i(cell.x + delta.x, cell.y + delta.y)
		if next == pc:
			ctrl._remote_players[rid] = row
			continue
		var stacked = false
		for oid in ctrl._remote_players.keys():
			if str(oid) == str(rid):
				continue
			var od: Variant = ctrl._remote_players[oid]
			if typeof(od) != TYPE_DICTIONARY:
				continue
			var oc: Variant = od.get("cell", {})
			if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == next.x and int(oc.get("y", -9999)) == next.y:
				stacked = true
				break
		if stacked:
			ctrl._remote_players[rid] = row
			continue
		row["cell"] = {"x": next.x, "y": next.y}
		row["facing"] = wdir
		ctrl._remote_players[rid] = row
		actions.append({
			"type": "remote_move",
			"player_id": str(rid),
			"x": next.x,
			"y": next.y,
			"facing": wdir,
		})
	return actions



func try_remote_despawn(remote_id: String = "") -> Dictionary:
	var actions: Array = []
	remote_id = str(remote_id).strip_edges()
	if remote_id.is_empty():
		# Despawn all
		for rid in ctrl._remote_players.keys():
			actions.append({"type": "remote_despawn", "player_id": str(rid)})
		ctrl._remote_players.clear()
		return {"ok": true, "actions": actions}
	if not ctrl._remote_players.has(remote_id):
		return {"ok": false, "reason": "not_found", "actions": actions}
	ctrl._remote_players.erase(remote_id)
	actions.append({"type": "remote_despawn", "player_id": remote_id})
	return {"ok": true, "actions": actions}


