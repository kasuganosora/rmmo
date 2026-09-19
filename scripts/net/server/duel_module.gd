extends RefCounted
## Domain module: duel (challenge/accept/decline/forfeit, tick, damage).

var ctrl
func _init(c):
	ctrl = c

const DUEL_DURATION_SEC := 60.0
const DUEL_STUB_HP := 100
const DUEL_RANGE_CELLS := 1

func snapshot_duel() -> Dictionary:
	if not ctrl._duel.is_empty() and bool(ctrl._duel.get("active", false)):
		return {
			"active": true,
			"pending": false,
			"opponent_id": str(ctrl._duel.get("opponent_id", "")),
			"opponent_name": str(ctrl._duel.get("opponent_name", "")),
			"started_at": float(ctrl._duel.get("started_at", 0.0)),
			"ends_at": float(ctrl._duel.get("ends_at", 0.0)),
			"opponent_hp": int(ctrl._duel.get("opponent_hp", 0)),
			"opponent_hp_max": int(ctrl._duel.get("opponent_hp_max", DUEL_STUB_HP)),
		}
	if not ctrl._duel_pending.is_empty():
		return {
			"active": false,
			"pending": true,
			"opponent_id": str(ctrl._duel_pending.get("opponent_id", "")),
			"opponent_name": str(ctrl._duel_pending.get("opponent_name", "")),
			"started_at": 0.0,
			"ends_at": 0.0,
			"opponent_hp": 0,
			"opponent_hp_max": DUEL_STUB_HP,
		}
	return {
		"active": false,
		"pending": false,
		"opponent_id": "",
		"opponent_name": "",
		"started_at": 0.0,
		"ends_at": 0.0,
		"opponent_hp": 0,
		"opponent_hp_max": 0,
	}



func in_duel() -> bool:
	return not ctrl._duel.is_empty() and bool(ctrl._duel.get("active", false))



func _duel_update_action() -> Dictionary:
	return {"type": "duel_update", "duel": snapshot_duel()}



func _duel_force_clear_silent() -> void:
	ctrl._duel.clear()
	ctrl._duel_pending.clear()



func _duel_resolve_target(target_id_or_name: String) -> Dictionary:
	## Returns {ok, id, name} for a spawned remote, else {ok:false, reason}.
	var key = str(target_id_or_name).strip_edges()
	if key.is_empty():
		return {"ok": false, "reason": "empty"}
	var rid = ""
	if ctrl._remote_players.has(key):
		rid = key
	else:
		rid = ctrl.find_remote_by_name(key)
	if rid.is_empty():
		return {"ok": false, "reason": "not_found"}
	var rd: Dictionary = ctrl.get_remote_player(rid)
	var rname = str(rd.get("name", rid)).strip_edges()
	if rname.is_empty():
		rname = rid
	return {"ok": true, "id": rid, "name": rname}



func _duel_is_opponent(target_id: String) -> bool:
	if not in_duel():
		return false
	return str(target_id).strip_edges() == str(ctrl._duel.get("opponent_id", ""))



func _duel_seed_remote_hp(remote_id: String, hp: int, hp_max: int) -> void:
	if not ctrl._remote_players.has(remote_id):
		return
	var row: Variant = ctrl._remote_players[remote_id]
	if typeof(row) != TYPE_DICTIONARY:
		return
	var d: Dictionary = row
	d["hp"] = hp
	d["hp_max"] = hp_max
	ctrl._remote_players[remote_id] = d



func _duel_clear_remote_hp(remote_id: String) -> void:
	if not ctrl._remote_players.has(remote_id):
		return
	var row: Variant = ctrl._remote_players[remote_id]
	if typeof(row) != TYPE_DICTIONARY:
		return
	var d: Dictionary = row
	d.erase("hp")
	d.erase("hp_max")
	ctrl._remote_players[remote_id] = d



func _duel_start(opponent_id: String, opponent_name: String) -> Array:
	var now: float = ctrl._party_clock()
	var hp_max: int = DUEL_STUB_HP
	ctrl._duel_pending.clear()
	ctrl._duel = {
		"active": true,
		"opponent_id": opponent_id,
		"opponent_name": opponent_name,
		"started_at": now,
		"ends_at": now + DUEL_DURATION_SEC,
		"opponent_hp": hp_max,
		"opponent_hp_max": hp_max,
	}
	_duel_seed_remote_hp(opponent_id, hp_max, hp_max)
	var actions: Array = []
	actions.append(_duel_update_action())
	actions.append({
		"type": "system_message",
		"text": "与【%s】的决斗开始！" % opponent_name,
	})
	return actions



func _duel_end(reason: String, winner: String = "") -> Array:
	## reason: win | forfeit | timeout | cancel
	var actions: Array = []
	var opp_id = str(ctrl._duel.get("opponent_id", ""))
	var opp_name = str(ctrl._duel.get("opponent_name", "对手"))
	_duel_clear_remote_hp(opp_id)
	ctrl._duel.clear()
	ctrl._duel_pending.clear()
	actions.append(_duel_update_action())
	var msg = ""
	match reason:
		"win":
			msg = "决斗胜利！击败了【%s】。" % opp_name
		"forfeit":
			msg = "你认输了。决斗败给【%s】。" % opp_name
		"timeout":
			msg = "决斗超时，与【%s】未分出胜负。" % opp_name
		_:
			msg = "决斗结束。"
	if winner != "":
		msg = "决斗结束：【%s】获胜。" % winner
	actions.append({"type": "system_message", "text": msg})
	return actions



func _tick_duel() -> Array:
	if not in_duel():
		return []
	var now: float = ctrl._party_clock()
	if now < float(ctrl._duel.get("ends_at", 0.0)):
		return []
	return _duel_end("timeout")



func try_duel_challenge(target_id_or_name: String) -> Dictionary:
	var actions: Array = []
	if ctrl.player_in_safe_zone():
		return ctrl._safe_zone_block_pvp_result()
	if in_duel():
		actions.append({"type": "system_message", "text": "你已在决斗中。"})
		actions.append(_duel_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	if not ctrl._duel_pending.is_empty():
		actions.append({"type": "system_message", "text": "已有未处理的决斗邀请。"})
		actions.append(_duel_update_action())
		return {"ok": false, "reason": "pending", "actions": actions}
	var resolved: Dictionary = _duel_resolve_target(target_id_or_name)
	if not bool(resolved.get("ok", false)):
		var reason = str(resolved.get("reason", "not_found"))
		if reason == "empty":
			actions.append({"type": "system_message", "text": "请选择决斗目标。"})
		else:
			actions.append({"type": "system_message", "text": "找不到玩家【%s】。" % str(target_id_or_name).strip_edges()})
		return {"ok": false, "reason": "not_found" if reason != "empty" else "empty", "actions": actions}
	var oid = str(resolved.get("id", ""))
	var oname = str(resolved.get("name", oid))
	# Shell remotes: instant start (auto-accept in the same call).
	actions.append_array(_duel_start(oid, oname))
	return {"ok": true, "actions": actions, "auto_accepted": true}



func try_duel_accept() -> Dictionary:
	var actions: Array = []
	if in_duel():
		actions.append({"type": "system_message", "text": "决斗已在进行中。"})
		actions.append(_duel_update_action())
		return {"ok": false, "reason": "already", "actions": actions}
	if ctrl._duel_pending.is_empty():
		actions.append({"type": "system_message", "text": "没有待接受的决斗。"})
		return {"ok": false, "reason": "no_pending", "actions": actions}
	var oid = str(ctrl._duel_pending.get("opponent_id", ""))
	var oname = str(ctrl._duel_pending.get("opponent_name", oid))
	actions.append_array(_duel_start(oid, oname))
	return {"ok": true, "actions": actions}



func try_duel_decline() -> Dictionary:
	var actions: Array = []
	if ctrl._duel_pending.is_empty():
		actions.append({"type": "system_message", "text": "没有待拒绝的决斗。"})
		return {"ok": false, "reason": "no_pending", "actions": actions}
	var oname = str(ctrl._duel_pending.get("opponent_name", "对方"))
	ctrl._duel_pending.clear()
	actions.append(_duel_update_action())
	actions.append({"type": "system_message", "text": "已拒绝与【%s】的决斗。" % oname})
	return {"ok": true, "actions": actions}



func try_duel_forfeit() -> Dictionary:
	var actions: Array = []
	if not in_duel():
		actions.append({"type": "system_message", "text": "当前没有决斗。"})
		return {"ok": false, "reason": "not_in_duel", "actions": actions}
	actions.append_array(_duel_end("forfeit"))
	return {"ok": true, "actions": actions}



func try_duel_debug_pending(target_id_or_name: String) -> Dictionary:
	var actions: Array = []
	if in_duel() or not ctrl._duel_pending.is_empty():
		return {"ok": false, "reason": "busy", "actions": actions}
	var resolved: Dictionary = _duel_resolve_target(target_id_or_name)
	if not bool(resolved.get("ok", false)):
		return {"ok": false, "reason": "not_found", "actions": actions}
	ctrl._duel_pending = {
		"opponent_id": str(resolved.get("id", "")),
		"opponent_name": str(resolved.get("name", "")),
	}
	actions.append(_duel_update_action())
	return {"ok": true, "actions": actions}



func try_duel_debug_hit(amount: int = 25) -> Dictionary:
	var actions: Array = []
	if not in_duel():
		return {"ok": false, "reason": "not_in_duel", "actions": actions}
	amount = maxi(1, amount)
	actions.append_array(_duel_apply_damage(amount))
	return {"ok": true, "actions": actions}



func _duel_player_atk() -> int:
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("_effective_atk_player"):
		return maxi(1, int(ctrl.combat_engine._effective_atk_player()))
	if ctrl.combat_stats != null and typeof(ctrl.combat_stats.player) == TYPE_DICTIONARY:
		return maxi(1, int(ctrl.combat_stats.player.get("atk", 10)))
	return 10



func _duel_apply_damage(amount: int) -> Array:
	var actions: Array = []
	if not in_duel():
		return actions
	var dealt: int = maxi(1, amount)
	var hp: int = maxi(0, int(ctrl._duel.get("opponent_hp", 0)) - dealt)
	var hp_max: int = int(ctrl._duel.get("opponent_hp_max", DUEL_STUB_HP))
	ctrl._duel["opponent_hp"] = hp
	var oid = str(ctrl._duel.get("opponent_id", ""))
	_duel_seed_remote_hp(oid, hp, hp_max)
	actions.append({
		"type": "damage",
		"target": "remote",
		"id": oid,
		"amount": dealt,
		"hp": hp,
		"hp_max": hp_max,
	})
	actions.append(_duel_update_action())
	if hp <= 0:
		actions.append_array(_duel_end("win"))
	return actions



func _try_duel_attack_target(target_id: String, player_x: int, player_y: int) -> Dictionary:
	## Empty dict = not a duel hit (fall through). Else full result.
	target_id = str(target_id).strip_edges()
	if target_id.is_empty() or not _duel_is_opponent(target_id):
		return {}
	var actions: Array = []
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "actions": actions}
	if ctrl.combat_engine != null and ctrl.combat_engine.is_casting():
		actions.append({"type": "system_message", "text": "施法中，无法普攻。"})
		return {"ok": false, "actions": actions}
	if ctrl.combat_stats != null and not ctrl.combat_stats.is_attack_ready():
		actions.append({"type": "system_message", "text": "攻击冷却中。"})
		return {"ok": false, "actions": actions}
	var rd: Dictionary = ctrl.get_remote_player(target_id)
	if rd.is_empty():
		actions.append({"type": "system_message", "text": "决斗目标已离开。"})
		return {"ok": false, "reason": "gone", "actions": actions}
	var cell_v: Variant = rd.get("cell", {})
	var rx = player_x
	var ry = player_y
	if typeof(cell_v) == TYPE_DICTIONARY:
		rx = int(cell_v.get("x", player_x))
		ry = int(cell_v.get("y", player_y))
	if ctrl._chebyshev(player_x, player_y, rx, ry) > DUEL_RANGE_CELLS:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "range", "actions": actions}
	var cd: float = 0.8
	if ctrl.combat_stats != null and typeof(ctrl.combat_stats.player) == TYPE_DICTIONARY:
		cd = float(ctrl.combat_stats.player.get("atk_speed", 0.8))
		ctrl.combat_stats.set_attack_cooldown(cd)
		ctrl.combat_stats.set_skill_cooldown("basic_attack", cd)
	actions.append_array(_duel_apply_damage(_duel_player_atk()))
	actions.append({
		"type": "skill_cd",
		"skill_id": "basic_attack",
		"remaining": cd,
		"cooldown": cd,
	})
	return {"ok": true, "actions": actions}



func _try_duel_skill_target(skill_id: String, target_id: String, player_x: int, player_y: int) -> Dictionary:
	skill_id = str(skill_id).strip_edges()
	target_id = str(target_id).strip_edges()
	if target_id.is_empty() or not _duel_is_opponent(target_id):
		return {}
	if skill_id.is_empty() or skill_id == "basic_attack":
		return _try_duel_attack_target(target_id, player_x, player_y)
	# Thin: any targeted skill applies a slightly stronger stub hit while in duel.
	var actions: Array = []
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		return {"ok": false, "actions": actions}
	var rd: Dictionary = ctrl.get_remote_player(target_id)
	if rd.is_empty():
		return {"ok": false, "reason": "gone", "actions": [{"type": "system_message", "text": "决斗目标已离开。"}]}
	var cell_v: Variant = rd.get("cell", {})
	var rx = player_x
	var ry = player_y
	if typeof(cell_v) == TYPE_DICTIONARY:
		rx = int(cell_v.get("x", player_x))
		ry = int(cell_v.get("y", player_y))
	var range_cells = 1
	var def: Dictionary = ctrl.skill_def(skill_id) if ctrl.has_method("skill_def") else {}
	if not def.is_empty():
		range_cells = maxi(1, int(def.get("range", 1)))
	if ctrl._chebyshev(player_x, player_y, rx, ry) > range_cells:
		actions.append({"type": "system_message", "text": "目标太远。"})
		return {"ok": false, "reason": "range", "actions": actions}
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("is_skill_ready") and not ctrl.combat_stats.is_skill_ready(skill_id):
		actions.append({"type": "system_message", "text": "技能冷却中。"})
		return {"ok": false, "actions": actions}
	var atk: int = _duel_player_atk()
	var mult = 1.5
	if not def.is_empty():
		mult = float(def.get("power", def.get("damage_mult", 1.5)))
		if mult < 1.0:
			mult = 1.5
	var dealt: int = maxi(1, int(round(float(atk) * mult)))
	if ctrl.combat_stats != null and ctrl.combat_stats.has_method("set_skill_cooldown"):
		var cd: float = float(def.get("cooldown", 3.0)) if not def.is_empty() else 3.0
		ctrl.combat_stats.set_skill_cooldown(skill_id, cd)
		actions.append({
			"type": "skill_cd",
			"skill_id": skill_id,
			"remaining": cd,
			"cooldown": cd,
		})
	actions.append_array(_duel_apply_damage(dealt))
	return {"ok": true, "actions": actions}



