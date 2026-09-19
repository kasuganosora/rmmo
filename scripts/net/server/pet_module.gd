extends RefCounted
## Domain module: companion pet (summon/dismiss/follow/combat assist).

var ctrl
func _init(c):
	ctrl = c

const TileId = preload("res://scripts/map/tile_id.gd")
const MobAI = preload("res://scripts/net/combat/mob_ai.gd")
const PET_FOLLOW_INTERVAL_SEC := 0.45
const PET_COMBAT_INTERVAL_SEC := 1.5
const PET_COMBAT_RANGE := 2
const PET_LAG_MIN := 1
const PET_LAG_MAX := 2
const PET_DEFS := {
	"default": {"name": "小跟班", "look_id": "1"},
}

func try_set_pet_assist(on: bool) -> void:
	ctrl.pet_assist = bool(on)



func snapshot_pet() -> Dictionary:
	var active = bool(ctrl._pet.get("active", false))
	return {
		"active": active,
		"id": str(ctrl._pet.get("id", "")),
		"name": str(ctrl._pet.get("name", "")),
		"cell": (ctrl._pet.get("cell", {"x": 0, "y": 0}) as Dictionary).duplicate(true)
			if typeof(ctrl._pet.get("cell", {})) == TYPE_DICTIONARY
			else {"x": 0, "y": 0},
		"look_id": str(ctrl._pet.get("look_id", "1")),
		"facing": int(ctrl._pet.get("facing", 2)),
		"atk": _pet_atk() if active else 0,
		"assist": bool(ctrl.pet_assist),
	}



func _pet_reset() -> void:
	ctrl._pet = {
		"active": false,
		"id": "",
		"name": "",
		"cell": {"x": 0, "y": 0},
		"look_id": "1",
		"facing": 2,
		"follow_acc": 0.0,
		"combat_acc": 0.0,
	}



func _pet_spawn_action() -> Dictionary:
	var snap: Dictionary = snapshot_pet()
	return {
		"type": "pet_spawn",
		"pet": snap,
		"id": str(snap.get("id", "")),
		"name": str(snap.get("name", "")),
		"x": int((snap.get("cell", {}) as Dictionary).get("x", 0)),
		"y": int((snap.get("cell", {}) as Dictionary).get("y", 0)),
		"look_id": str(snap.get("look_id", "1")),
		"facing": int(snap.get("facing", 2)),
	}



func _pet_despawn_action() -> Dictionary:
	return {
		"type": "pet_despawn",
		"id": str(ctrl._pet.get("id", "")),
	}



func _pet_pick_spawn_cell(pc: Vector2i) -> Vector2i:
	var offsets: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0),
	]
	for off_v in offsets:
		var off: Vector2i = off_v
		var cand = Vector2i(pc.x + off.x, pc.y + off.y)
		if cand == pc:
			continue
		var blocked = false
		if ctrl.map_collision != null and ctrl.map_collision.has_method("is_blocked"):
			blocked = bool(ctrl.map_collision.is_blocked(cand.x, cand.y))
		if blocked:
			continue
		return cand
	return Vector2i(pc.x + 1, pc.y)



func _pet_snap_near_player() -> void:
	if not bool(ctrl._pet.get("active", false)):
		return
	var pc = ctrl._player_xy()
	var cell = _pet_pick_spawn_cell(pc)
	ctrl._pet["cell"] = {"x": cell.x, "y": cell.y}
	ctrl._pet["facing"] = MobAI.facing_toward(cell, pc)
	ctrl._pet["follow_acc"] = 0.0
	ctrl._pet["combat_acc"] = 0.0



func try_pet_summon(pet_id: String = "default") -> Dictionary:
	var actions: Array = []
	pet_id = str(pet_id).strip_edges()
	if pet_id.is_empty():
		pet_id = "default"
	if bool(ctrl._pet.get("active", false)):
		actions.append({"type": "system_message", "text": "已有宠物。"})
		return {"ok": false, "reason": "already_active", "actions": actions}
	var def_v: Variant = PET_DEFS.get(pet_id, PET_DEFS.get("default", {}))
	var def: Dictionary = def_v if typeof(def_v) == TYPE_DICTIONARY else {"name": "小跟班", "look_id": "1"}
	if not PET_DEFS.has(pet_id) and pet_id != "default":
		# Unknown id → still allow as default-named custom id.
		def = {"name": str(PET_DEFS["default"].get("name", "小跟班")), "look_id": "1"}
	var pc = ctrl._player_xy()
	var cell = _pet_pick_spawn_cell(pc)
	ctrl._pet = {
		"active": true,
		"id": pet_id,
		"name": str(def.get("name", "小跟班")),
		"cell": {"x": cell.x, "y": cell.y},
		"look_id": str(def.get("look_id", "1")),
		"facing": MobAI.facing_toward(cell, pc),
		"follow_acc": 0.0,
		"combat_acc": 0.0,
	}
	actions.append(_pet_spawn_action())
	actions.append({
		"type": "system_message",
		"text": "召唤了宠物【%s】。" % str(ctrl._pet.get("name", "")),
	})
	return {"ok": true, "actions": actions}



func try_pet_dismiss() -> Dictionary:
	var actions: Array = []
	if not bool(ctrl._pet.get("active", false)):
		actions.append({"type": "system_message", "text": "当前没有宠物。"})
		return {"ok": false, "reason": "not_active", "actions": actions}
	var pname = str(ctrl._pet.get("name", "宠物"))
	actions.append(_pet_despawn_action())
	_pet_reset()
	actions.append({"type": "system_message", "text": "收回了宠物【%s】。" % pname})
	return {"ok": true, "actions": actions}



func _tick_pet_follow(dt: float) -> Array:
	var actions: Array = []
	if not bool(ctrl._pet.get("active", false)):
		return actions
	ctrl._pet["follow_acc"] = float(ctrl._pet.get("follow_acc", 0.0)) + dt
	if float(ctrl._pet.get("follow_acc", 0.0)) < PET_FOLLOW_INTERVAL_SEC:
		return actions
	ctrl._pet["follow_acc"] = 0.0
	var cell_v: Variant = ctrl._pet.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return actions
	var cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var pc = ctrl._player_xy()
	var dist: int = ctrl._chebyshev(cell.x, cell.y, pc.x, pc.y)
	if dist <= PET_LAG_MAX and dist >= PET_LAG_MIN:
		return actions
	if dist == 0:
		# Nudge off player cell.
		var nudge = _pet_pick_spawn_cell(pc)
		if nudge == cell:
			return actions
		ctrl._pet["cell"] = {"x": nudge.x, "y": nudge.y}
		ctrl._pet["facing"] = MobAI.facing_toward(nudge, pc)
		actions.append({
			"type": "pet_move",
			"id": str(ctrl._pet.get("id", "")),
			"x": nudge.x,
			"y": nudge.y,
			"facing": int(ctrl._pet.get("facing", 2)),
		})
		return actions
	if dist <= PET_LAG_MAX:
		return actions
	# Step toward player; do not enter player cell (lag stays ≥ 1).
	var wdir: int = MobAI.next_step_dir(ctrl.map_collision, cell, pc, false)
	if wdir == 0:
		# Fallback greedy cardinal toward player (ignore collision if no map).
		wdir = MobAI.facing_toward(cell, pc)
		var delta0: Vector2i = TileId.dir_delta(wdir)
		var trial = Vector2i(cell.x + delta0.x, cell.y + delta0.y)
		if trial == pc:
			return actions
		if ctrl.map_collision != null and ctrl.map_collision.has_method("is_blocked"):
			if bool(ctrl.map_collision.is_blocked(trial.x, trial.y)):
				return actions
		wdir = MobAI.facing_toward(cell, pc)
	var delta: Vector2i = TileId.dir_delta(wdir)
	var next = Vector2i(cell.x + delta.x, cell.y + delta.y)
	if next == pc:
		return actions
	if ctrl.map_collision != null and ctrl.map_collision.has_method("is_blocked"):
		if bool(ctrl.map_collision.is_blocked(next.x, next.y)):
			return actions
	# Avoid stacking on shell remotes when possible.
	for oid in ctrl._remote_players.keys():
		var od: Variant = ctrl._remote_players[oid]
		if typeof(od) != TYPE_DICTIONARY:
			continue
		var oc: Variant = od.get("cell", {})
		if typeof(oc) == TYPE_DICTIONARY and int(oc.get("x", -9999)) == next.x and int(oc.get("y", -9999)) == next.y:
			return actions
	ctrl._pet["cell"] = {"x": next.x, "y": next.y}
	ctrl._pet["facing"] = wdir
	actions.append({
		"type": "pet_move",
		"id": str(ctrl._pet.get("id", "")),
		"x": next.x,
		"y": next.y,
		"facing": wdir,
	})
	return actions



func _pet_atk() -> int:
	var lv = 1
	if ctrl.combat_stats != null and typeof(ctrl.combat_stats.player) == TYPE_DICTIONARY:
		lv = maxi(1, int(ctrl.combat_stats.player.get("level", 1)))
	return 3 + lv



func _npc_display_name_for_pet(npc_id: String) -> String:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty():
		return "敌人"
	if ctrl.npc_spawn_templates.has(npc_id):
		var n = str(ctrl.npc_spawn_templates[npc_id].get("name", "")).strip_edges()
		if n != "":
			return n
	if ctrl.npc_meta.has(npc_id) and typeof(ctrl.npc_meta[npc_id]) == TYPE_DICTIONARY:
		var n2 = str(ctrl.npc_meta[npc_id].get("name", "")).strip_edges()
		if n2 != "":
			return n2
	return npc_id



func _resolve_pet_combat_target() -> String:
	if ctrl.combat_stats == null:
		return ""
	var cell_v: Variant = ctrl._pet.get("cell", {})
	if typeof(cell_v) != TYPE_DICTIONARY:
		return ""
	var pet_cell = Vector2i(int(cell_v.get("x", 0)), int(cell_v.get("y", 0)))
	var tid = str(ctrl._player_combat_target_id).strip_edges()
	if tid != "" and _pet_target_valid_in_range(tid, pet_cell):
		return tid
	# Fallback: hostile with player hate within pet range.
	var you = "player"
	if "player_actor_id" in ctrl.combat_stats:
		var aid = str(ctrl.combat_stats.player_actor_id).strip_edges()
		if aid != "":
			you = aid
	for nid_v in ctrl.combat_stats.npcs.keys():
		var nid = str(nid_v)
		if not _pet_target_valid_in_range(nid, pet_cell):
			continue
		if not ctrl.combat_stats.has_method("get_hate_list"):
			continue
		var hate: Array = ctrl.combat_stats.get_hate_list(nid, false)
		for e in hate:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if str(e.get("id", "")).strip_edges() == you:
				return nid
	return ""



func _pet_target_valid_in_range(npc_id: String, pet_cell: Vector2i) -> bool:
	npc_id = str(npc_id).strip_edges()
	if npc_id.is_empty() or ctrl.combat_stats == null or not ctrl.combat_stats.npcs.has(npc_id):
		return false
	var st: Dictionary = ctrl.combat_stats.npcs[npc_id]
	if int(st.get("hp", 0)) <= 0:
		return false
	if not bool(st.get("hostile", false)):
		return false
	var tc: Vector2i = ctrl.combat_stats.get_npc_cell(npc_id) if ctrl.combat_stats.has_method("get_npc_cell") else Vector2i(-9999, -9999)
	if tc.x <= -9990:
		return false
	return ctrl._chebyshev(pet_cell.x, pet_cell.y, tc.x, tc.y) <= PET_COMBAT_RANGE



func _tick_pet_combat(dt: float) -> Array:
	var actions: Array = []
	if not bool(ctrl._pet.get("active", false)):
		return actions
	if not bool(ctrl.pet_assist):
		return actions
	if ctrl.combat_stats == null or ctrl.combat_engine == null:
		return actions
	if ctrl.awaiting_respawn or not ctrl.combat_stats.player_alive():
		return actions
	ctrl._pet["combat_acc"] = float(ctrl._pet.get("combat_acc", 0.0)) + dt
	if float(ctrl._pet.get("combat_acc", 0.0)) < PET_COMBAT_INTERVAL_SEC:
		return actions
	ctrl._pet["combat_acc"] = 0.0
	var tid = _resolve_pet_combat_target()
	if tid.is_empty():
		return actions
	var hit_actions: Array = []
	var amount: int = _pet_atk()
	# Guaranteed hit; attribute as player so hate / loot / exp stay player-side.
	if ctrl.combat_engine.has_method("_damage_npc"):
		ctrl.combat_engine._damage_npc(tid, amount, hit_actions, false, "player")
	if hit_actions.is_empty():
		return actions
	var nm = _npc_display_name_for_pet(tid)
	hit_actions.append({"type": "system_message", "text": "宠物攻击了%s" % nm})
	if ctrl.combat_engine.has_method("_threat_update_action"):
		var thr_act: Dictionary = ctrl.combat_engine._threat_update_action(tid)
		if not thr_act.is_empty():
			hit_actions.append(thr_act)
	var finalized: Dictionary = ctrl._finalize_combat_result({"ok": true, "actions": hit_actions})
	actions.append_array(finalized.get("actions", []))
	if not ctrl.combat_stats.npcs.has(tid) or int(ctrl.combat_stats.npcs[tid].get("hp", 0)) <= 0:
		if str(ctrl._player_combat_target_id).strip_edges() == tid:
			ctrl._player_combat_target_id = ""
	return actions


