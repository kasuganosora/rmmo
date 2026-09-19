extends RefCounted
## Domain module: NPC/mob AI (register, wander/chase/return-home steps).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const DEFAULT_FRIENDLY_WANDER_RADIUS := 2

func register_npc(
	npc_id: String,
	x: int,
	y: int,
	hostile: bool = false,
	aggressive: bool = false,
	facing: int = 2,
	wander_radius: int = 0,
	group_id: int = 0,
	spawn_data: Dictionary = {},
	home_override: Vector2i = Vector2i(-9999, -9999)
) -> void:
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.combat_stats == null:
		return
	ctrl.combat_stats.set_npc_cell(npc_id, x, y)
	if not TileId.is_dir(facing):
		facing = 2
	var leash_r: int = MobAI.DEFAULT_LEASH_RADIUS
	var respawn_s: float = MobAI.DEFAULT_RESPAWN_SEC
	if not spawn_data.is_empty():
		if spawn_data.has("leash_radius"):
			leash_r = int(spawn_data.get("leash_radius", leash_r))
		if spawn_data.has("respawn_sec"):
			respawn_s = float(spawn_data.get("respawn_sec", respawn_s))
		if spawn_data.has("wander_radius"):
			wander_radius = maxi(int(spawn_data.get("wander_radius", wander_radius)), 0)
		if spawn_data.has("group_id"):
			group_id = int(spawn_data.get("group_id", group_id))
		if spawn_data.has("aggressive"):
			aggressive = bool(spawn_data.get("aggressive", aggressive))
		if spawn_data.has("hostile"):
			hostile = bool(spawn_data.get("hostile", hostile))
		if spawn_data.has("direction"):
			var fd: int = int(spawn_data.get("direction", facing))
			if TileId.is_dir(fd):
				facing = fd
	var home_cell = Vector2i(x, y)
	if home_override.x > -9990:
		home_cell = home_override
	elif not spawn_data.is_empty():
		var hc_v: Variant = spawn_data.get("home_cell", spawn_data.get("cell", {}))
		if typeof(hc_v) == TYPE_VECTOR2I:
			home_cell = hc_v
		elif typeof(hc_v) == TYPE_DICTIONARY:
			var hcd: Dictionary = hc_v
			if hcd.has("x") and hcd.has("y"):
				home_cell = Vector2i(int(hcd.get("x", x)), int(hcd.get("y", y)))
	# Friendly pack flag wander:true with no radius → default roam radius.
	var want_wander = bool(spawn_data.get("wander", false)) or wander_radius > 0
	if want_wander and wander_radius <= 0:
		wander_radius = DEFAULT_FRIENDLY_WANDER_RADIUS
	if hostile or want_wander:
		ctrl.combat_stats.ensure_npc(npc_id, hostile, aggressive if hostile else false)
		ctrl.combat_stats.ensure_npc_ai(
			npc_id, facing, aggressive if hostile else false, home_cell, wander_radius, group_id, leash_r, respawn_s
		)
		# Keep aggressive flag on combat blob in sync.
		if ctrl.combat_stats.npcs.has(npc_id):
			ctrl.combat_stats.npcs[npc_id]["hostile"] = hostile
			ctrl.combat_stats.npcs[npc_id]["aggressive"] = aggressive if hostile else false
			# Optional combat overrides from npcs.json / spawn_data (world boss etc.).
			ctrl._apply_npc_spawn_combat_overrides(npc_id, spawn_data)
		# Ensure home / wander / group / leash / respawn / state from spawn registration.
		if ctrl.combat_stats.npc_ai.has(npc_id):
			var ai: Dictionary = ctrl.combat_stats.npc_ai[npc_id]
			ai["home_cell"] = home_cell
			ai["wander_radius"] = maxi(wander_radius, 0)
			ai["group_id"] = group_id if hostile else 0
			ai["leash_radius"] = leash_r if hostile else -1
			ai["respawn_sec"] = respawn_s if hostile else -1.0
			ai["facing"] = facing
			ai["ai_state"] = MobAI.AI_IDLE
			ai["idle_wander_acc"] = 0.0
			ai["chase_target"] = ""
			ai["lose_sight_sec"] = 0.0
			ai["seen_target"] = false
			ai["enraged"] = false
			ai["hate_list"] = []
			ai["victim_id"] = ""
			ai["aggressive"] = aggressive if hostile else false
			ai.erase("threat")
			var skills_v: Variant = spawn_data.get("skills", [])
			if typeof(skills_v) == TYPE_ARRAY:
				var sl: Array = []
				for sid_v in skills_v:
					var sid = str(sid_v).strip_edges()
					if sid != "":
						sl.append(sid)
				ai["skills"] = sl
			if not ai.has("skill_ready_at"):
				ai["skill_ready_at"] = {}
			ctrl.combat_stats.npc_ai[npc_id] = ai
		# Cancel any pending respawn for this id (alive again).
		if hostile and ctrl._npc_respawn_at.has(npc_id):
			ctrl._npc_respawn_at.erase(npc_id)
	# Soft meta for interact / shop (friend and hostile).
	var meta = {
		"name": str(spawn_data.get("name", npc_id)),
		"interact_text": str(spawn_data.get("interact_text", "")),
		"shop_id": str(spawn_data.get("shop_id", "")).strip_edges(),
		"inn_rest": bool(spawn_data.get("inn_rest", false)),
		"inn_cost": int(spawn_data.get("inn_cost", 25)),
		"blacksmith": bool(spawn_data.get("blacksmith", spawn_data.get("repair", false))),
		"repair_cost_per_point": int(spawn_data.get("repair_cost_per_point", 1)),
		"world_boss": bool(spawn_data.get("world_boss", spawn_data.get("is_boss", false))),
		"dungeon": bool(spawn_data.get("dungeon", false)),
	}
	ctrl.npc_meta[npc_id] = meta
	# Store / refresh spawn template for dead-mob respawn (hostiles).
	ctrl._store_npc_spawn_template(
		npc_id, x, y, hostile, aggressive, facing, wander_radius, group_id, leash_r, respawn_s, spawn_data, home_cell
	)



func try_npc_move(npc_id: String, from_x: int, from_y: int, dir: int) -> Dictionary:
	if ctrl.map_collision == null:
		return {"ok": false, "x": from_x, "y": from_y}
	if not TileId.is_dir(dir):
		return {"ok": false, "x": from_x, "y": from_y}
	var delta: Vector2i = TileId.dir_delta(dir)
	var nx: int = from_x + delta.x
	var ny: int = from_y + delta.y
	var onto_player = ctrl.player_cell.x > -9990 and nx == ctrl.player_cell.x and ny == ctrl.player_cell.y
	var touch_ev: Dictionary = {}
	if onto_player:
		touch_ev = ctrl._event_touch_event(npc_id, from_x, from_y)
		if touch_ev.is_empty():
			return {"ok": false, "x": from_x, "y": from_y}
		if ctrl.map_collision.has_method("can_pass_tiles") and not ctrl.map_collision.can_pass_tiles(from_x, from_y, dir):
			return {"ok": false, "x": from_x, "y": from_y}
	elif not ctrl.map_collision.can_pass(from_x, from_y, dir):
		return {"ok": false, "x": from_x, "y": from_y}
	ctrl.map_collision.set_extra_blocked(from_x, from_y, false)
	ctrl.map_collision.set_extra_blocked(nx, ny, true)
	if ctrl.combat_stats != null and str(npc_id).strip_edges() != "":
		var nid = str(npc_id).strip_edges()
		ctrl.combat_stats.set_npc_cell(nid, nx, ny)
		if ctrl.combat_stats.npc_ai.has(nid):
			var ai: Dictionary = ctrl.combat_stats.npc_ai[nid]
			ai["facing"] = dir
			ctrl.combat_stats.npc_ai[nid] = ai
	var out = {"ok": true, "x": nx, "y": ny, "npc_id": npc_id, "facing": dir}
	if not touch_ev.is_empty() and ctrl.event_runtime != null:
		var ctx = ctrl._event_server_ctx(str(touch_ev.get("name", touch_ev.get("id", ""))))
		var touch_actions: Array = ctrl.event_runtime.run_event(str(touch_ev.get("id", "")), ctx)
		if not touch_actions.is_empty():
			out["actions"] = touch_actions
			ctrl._pending_tick_actions.append_array(touch_actions)
	return out




func _tick_mob_ai(dt: float) -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null:
		return actions
	if not ctrl.combat_stats.player_alive():
		# Drop chase when player is dead → evade / return home.
		for nid in ctrl.combat_stats.npc_ai.keys():
			var aid: Dictionary = ctrl.combat_stats.npc_ai[nid]
			if str(aid.get("chase_target", "")) != "" or str(aid.get("ai_state", "")) == MobAI.AI_CHASE:
				actions.append_array(ctrl._evade_npc(str(nid)))
		# Still process return_home / idle below? Player dead — continue for return/idle.
	var px: int = ctrl.player_cell.x
	var py: int = ctrl.player_cell.y
	var player_ok: bool = ctrl.combat_stats.player_alive() and px > -9990
	# Snapshot keys — AI may erase on death elsewhere.
	var ids: Array = ctrl.combat_stats.npc_ai.keys()
	for npc_id_v in ids:
		var npc_id: String = str(npc_id_v)
		if not ctrl.combat_stats.npcs.has(npc_id):
			continue
		var st: Dictionary = ctrl.combat_stats.npcs[npc_id]
		if int(st.get("hp", 0)) <= 0:
			continue
		# Non-hostile (friendly wanderers): idle roam only — no chase / leash / vision.
		if not bool(st.get("hostile", false)):
			actions.append_array(_mob_ai_idle_wander_step(npc_id, dt))
			continue
		var ai: Dictionary = ctrl.combat_stats.npc_ai[npc_id]
		var cell: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
		if cell.x <= -9990:
			continue
		var facing: int = int(ai.get("facing", 2))
		var state: String = str(ai.get("ai_state", MobAI.AI_IDLE))
		var home: Vector2i = MobAI.get_home_cell(ai)
		var wander_r: int = maxi(int(ai.get("wander_radius", 0)), 0)
		var in_vision: bool = false
		var player_stealthed = false
		if player_ok and ctrl.combat_stats.statuses != null:
			player_stealthed = ctrl.combat_stats.statuses.has_status("player", "stealth")
		if player_ok and not player_stealthed:
			in_vision = MobAI.player_in_vision(cell, facing, ctrl.player_cell, ctrl.map_collision)
		var chasing: bool = str(ai.get("chase_target", "")) != "" or state == MobAI.AI_CHASE
		var can_aggro: bool = MobAI.wants_chase(ai) and not player_stealthed

		# Leash reset in progress: no re-aggro / no chase until home (do not attack).
		if state == MobAI.AI_RETURN_HOME:
			var home_only: Array = _mob_ai_return_home_step(npc_id, ai, cell, home)
			actions.append_array(home_only)
			continue

		# Stealth: treat as invisible — break existing chase / no new aggro.
		if player_stealthed and chasing and player_ok:
			actions.append_array(ctrl._evade_npc(npc_id))
			ai = ctrl.combat_stats.npc_ai[npc_id]
			state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
			chasing = false

		# Safe zone: no new aggro; break existing chase when player is inside.
		var player_safe = ctrl.player_in_safe_zone()
		if player_safe and chasing and player_ok:
			actions.append_array(ctrl._evade_npc(npc_id))
			ai = ctrl.combat_stats.npc_ai[npc_id]
			state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
			chasing = false
		# --- Aggro / lose-sight (only while player alive & outside safe zone) ---
		elif player_ok and (not player_safe) and can_aggro and in_vision:
			var tid = "player"
			if ctrl._session_character_id != "":
				tid = ctrl._session_character_id
			if ctrl.combat_stats.has_method("select_victim"):
				var hv: String = ctrl.combat_stats.select_victim(npc_id)
				if hv != "":
					tid = hv
			elif ctrl.combat_stats.has_method("highest_threat_target"):
				var ht: String = ctrl.combat_stats.highest_threat_target(npc_id)
				if ht != "":
					tid = ht
			ai["victim_id"] = tid
			ai["chase_target"] = tid
			ai["lose_sight_sec"] = 0.0
			ai["no_target_sec"] = 0.0
			ai["seen_target"] = true
			ai["ai_state"] = MobAI.AI_CHASE
			ai["idle_wander_acc"] = 0.0
			chasing = true
			state = MobAI.AI_CHASE
			facing = MobAI.facing_toward(cell, ctrl.player_cell)
			ai["facing"] = facing
			ctrl.combat_stats.npc_ai[npc_id] = ai
		elif chasing and player_ok:
			if in_vision:
				ai["lose_sight_sec"] = 0.0
				ai["seen_target"] = true
			else:
				# Pack assist / hit-from-behind start chase off-vision — do not
				# accumulate lose-sight until the mob has actually seen the player.
				if bool(ai.get("seen_target", false)):
					ai["lose_sight_sec"] = float(ai.get("lose_sight_sec", 0.0)) + dt
			if float(ai.get("lose_sight_sec", 0.0)) >= MobAI.LOSE_SIGHT_SEC:
				actions.append_array(ctrl._evade_npc(npc_id))
				# Fall through this tick into return_home / idle after clear.
				ai = ctrl.combat_stats.npc_ai[npc_id]
				state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
				chasing = false
			else:
				ai["ai_state"] = MobAI.AI_CHASE
				ctrl.combat_stats.npc_ai[npc_id] = ai
				state = MobAI.AI_CHASE

		# Home leash + no-valid-target: while chasing → evade / return_home.
		if chasing:
			ai = ctrl.combat_stats.npc_ai[npc_id]
			home = MobAI.get_home_cell(ai)
			var leash_r: int = int(ai.get("leash_radius", MobAI.DEFAULT_LEASH_RADIUS))
			var engage_r: int = leash_r if leash_r >= 0 else MobAI.DEFAULT_ENGAGE_RANGE
			engage_r = maxi(engage_r, MobAI.DEFAULT_ENGAGE_RANGE)
			var target_ok: bool = player_ok and MobAI.target_in_engage_range(
				cell, ctrl.player_cell, engage_r
			)
			if target_ok:
				ai["no_target_sec"] = 0.0
			else:
				ai["no_target_sec"] = float(ai.get("no_target_sec", 0.0)) + dt
			ctrl.combat_stats.npc_ai[npc_id] = ai
			var no_tgt: bool = float(ai.get("no_target_sec", 0.0)) >= MobAI.NO_VALID_TARGET_SEC
			if MobAI.beyond_leash(cell, home, leash_r) or no_tgt:
				actions.append_array(ctrl._evade_npc(npc_id))
				ai = ctrl.combat_stats.npc_ai[npc_id]
				state = str(ai.get("ai_state", MobAI.AI_RETURN_HOME))
				chasing = false

		# Re-read state after possible clear_chase.
		ai = ctrl.combat_stats.npc_ai[npc_id]
		state = str(ai.get("ai_state", MobAI.AI_IDLE))
		facing = int(ai.get("facing", facing))
		home = MobAI.get_home_cell(ai)
		wander_r = maxi(int(ai.get("wander_radius", 0)), 0)

		# Refresh sticky victim each AI tick while chasing (tank / multi-hate).
		if state == MobAI.AI_CHASE and ctrl.combat_stats.has_method("select_victim"):
			var prev_victim = str(ai.get("victim_id", ""))
			var sv: String = ctrl.combat_stats.select_victim(npc_id)
			ai = ctrl.combat_stats.npc_ai[npc_id]
			if sv != "":
				ai["chase_target"] = sv
				ctrl.combat_stats.npc_ai[npc_id] = ai
			var new_victim = str(ai.get("victim_id", sv))
			if new_victim != prev_victim:
				actions.append(ctrl._threat_update_action(npc_id))
			state = str(ai.get("ai_state", state))
		if state == MobAI.AI_CHASE and str(ai.get("chase_target", "")) != "" and player_ok:
			var chase_acts: Array = _mob_ai_chase_step(npc_id, ai, cell, facing, px, py)
			actions.append_array(chase_acts)
			continue

		if state == MobAI.AI_RETURN_HOME:
			var home_acts: Array = _mob_ai_return_home_step(npc_id, ai, cell, home)
			actions.append_array(home_acts)
			continue

		# Idle: wander_radius 0 → stand still; else low-frequency roam within radius.
		if state != MobAI.AI_IDLE:
			ai["ai_state"] = MobAI.AI_IDLE
			ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append_array(_mob_ai_idle_wander_step(npc_id, dt))
	return actions



func _mob_ai_idle_wander_step(npc_id: String, dt: float) -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null or not ctrl.combat_stats.npc_ai.has(npc_id):
		return actions
	var ai: Dictionary = ctrl.combat_stats.npc_ai[npc_id]
	var cell: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id)
	if cell.x <= -9990:
		return actions
	var home: Vector2i = MobAI.get_home_cell(ai)
	var wander_r: int = maxi(int(ai.get("wander_radius", 0)), 0)
	if wander_r <= 0:
		return actions
	ai["idle_wander_acc"] = float(ai.get("idle_wander_acc", 0.0)) + dt
	if float(ai.get("idle_wander_acc", 0.0)) < MobAI.IDLE_WANDER_INTERVAL_SEC:
		ctrl.combat_stats.npc_ai[npc_id] = ai
		return actions
	ai["idle_wander_acc"] = 0.0
	var wdir: int = MobAI.next_idle_wander_dir(ctrl.map_collision, cell, home, wander_r)
	ctrl.combat_stats.npc_ai[npc_id] = ai
	if wdir == 0:
		return actions
	var wm: Dictionary = try_npc_move(npc_id, cell.x, cell.y, wdir)
	if bool(wm.get("ok", false)):
		ai["facing"] = wdir
		ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": int(wm.get("x", cell.x)),
			"y": int(wm.get("y", cell.y)),
			"facing": wdir,
		})
	return actions



func _mob_ai_chase_step(npc_id: String, ai: Dictionary, cell: Vector2i, facing: int, px: int, py: int) -> Array:
	var actions: Array = []
	var skill_acts: Array = ctrl._try_npc_skill_tick(npc_id, ai, cell, px, py)
	if not skill_acts.is_empty():
		return skill_acts
	var man: int = maxi(absi(cell.x - px), absi(cell.y - py))
	if man <= 1:
		var face: int = MobAI.facing_toward(cell, ctrl.player_cell)
		if face != facing:
			ai["facing"] = face
			ctrl.combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face,
			})
		return actions
	if ctrl._npc_is_rooted(npc_id):
		var face_r: int = MobAI.facing_toward(cell, ctrl.player_cell)
		if face_r != int(ai.get("facing", 2)):
			ai["facing"] = face_r
			ctrl.combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face_r,
			})
		return actions
	var step_dir: int = MobAI.next_chase_dir(ctrl.map_collision, cell, ctrl.player_cell)
	if step_dir == 0:
		var face2: int = MobAI.facing_toward(cell, ctrl.player_cell)
		if face2 != int(ai.get("facing", 2)):
			ai["facing"] = face2
			ctrl.combat_stats.npc_ai[npc_id] = ai
			actions.append({
				"type": "npc_move",
				"npc_id": npc_id,
				"x": cell.x,
				"y": cell.y,
				"facing": face2,
			})
		return actions
	var moved: Dictionary = try_npc_move(npc_id, cell.x, cell.y, step_dir)
	if bool(moved.get("ok", false)):
		ai["facing"] = step_dir
		ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": int(moved.get("x", cell.x)),
			"y": int(moved.get("y", cell.y)),
			"facing": step_dir,
		})
	else:
		var face3: int = MobAI.facing_toward(cell, ctrl.player_cell)
		ai["facing"] = face3
		ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": cell.x,
			"y": cell.y,
			"facing": face3,
		})
	return actions



func _mob_ai_return_home_step(npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i) -> Array:
	var actions: Array = []
	if home.x <= -9990:
		ai["ai_state"] = MobAI.AI_IDLE
		ai["return_stuck_ticks"] = 0
		ctrl.combat_stats.npc_ai[npc_id] = ai
		return actions
	if cell == home:
		ai["ai_state"] = MobAI.AI_IDLE
		ai["idle_wander_acc"] = 0.0
		ai["return_stuck_ticks"] = 0
		ctrl.combat_stats.npc_ai[npc_id] = ai
		return actions
	var dist_before: int = MobAI.chebyshev(cell, home)
	var step_dir: int = MobAI.next_home_dir(ctrl.map_collision, cell, home)
	if step_dir == 0:
		return _mob_ai_return_home_stuck_or_face(npc_id, ai, cell, home, actions)
	var moved: Dictionary = try_npc_move(npc_id, cell.x, cell.y, step_dir)
	if bool(moved.get("ok", false)):
		var nx: int = int(moved.get("x", cell.x))
		var ny: int = int(moved.get("y", cell.y))
		var dest = Vector2i(nx, ny)
		var dist_after: int = MobAI.chebyshev(dest, home)
		ai["facing"] = step_dir
		# Strict improvement on best distance-to-home clears stuck; oscillation does not.
		var best: int = int(ai.get("return_best_dist", 99999))
		if dist_after < best:
			ai["return_best_dist"] = dist_after
			ai["return_stuck_ticks"] = 0
		else:
			ai["return_stuck_ticks"] = int(ai.get("return_stuck_ticks", 0)) + 1
			if int(ai.get("return_stuck_ticks", 0)) >= MobAI.RETURN_STUCK_TICKS:
				ctrl.combat_stats.npc_ai[npc_id] = ai
				return _mob_ai_teleport_home(npc_id, ai, dest, home, actions)
		if dest == home:
			ai["ai_state"] = MobAI.AI_IDLE
			ai["idle_wander_acc"] = 0.0
			ai["return_stuck_ticks"] = 0
		ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": nx,
			"y": ny,
			"facing": step_dir,
		})
	else:
		return _mob_ai_return_home_stuck_or_face(npc_id, ai, cell, home, actions)
	return actions



func _mob_ai_return_home_stuck_or_face(
	npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array
) -> Array:
	var stuck: int = int(ai.get("return_stuck_ticks", 0)) + 1
	ai["return_stuck_ticks"] = stuck
	if stuck >= MobAI.RETURN_STUCK_TICKS:
		return _mob_ai_teleport_home(npc_id, ai, cell, home, actions)
	var face: int = MobAI.facing_toward(cell, home)
	if face != int(ai.get("facing", 2)):
		ai["facing"] = face
		ctrl.combat_stats.npc_ai[npc_id] = ai
		actions.append({
			"type": "npc_move",
			"npc_id": npc_id,
			"x": cell.x,
			"y": cell.y,
			"facing": face,
		})
	else:
		ctrl.combat_stats.npc_ai[npc_id] = ai
	return actions



func _mob_ai_teleport_home(
	npc_id: String, ai: Dictionary, cell: Vector2i, home: Vector2i, actions: Array
) -> Array:
	var dest = home
	if ctrl.map_collision != null:
		if ctrl.map_collision.has_method("is_valid") and not bool(ctrl.map_collision.is_valid(home.x, home.y)):
			dest = cell
	if ctrl.map_collision != null and cell != dest:
		if ctrl.map_collision.has_method("set_extra_blocked"):
			ctrl.map_collision.set_extra_blocked(cell.x, cell.y, false)
			ctrl.map_collision.set_extra_blocked(dest.x, dest.y, true)
	ctrl.combat_stats.set_npc_cell(npc_id, dest.x, dest.y)
	var face: int = int(ai.get("facing", 2))
	if cell != dest:
		face = MobAI.facing_toward(cell, dest)
	ai["facing"] = face
	ai["ai_state"] = MobAI.AI_IDLE
	ai["idle_wander_acc"] = 0.0
	ai["return_stuck_ticks"] = 0
	ai["return_best_dist"] = 99999
	ctrl.combat_stats.npc_ai[npc_id] = ai
	actions.append({
		"type": "npc_move",
		"npc_id": npc_id,
		"x": dest.x,
		"y": dest.y,
		"facing": face,
		"teleport": true,
	})
	return actions

