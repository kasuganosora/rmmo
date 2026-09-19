extends RefCounted
## Domain module: sustain (sit/inn rest, rested EXP accumulate).

var ctrl
func _init(c):
	ctrl = c

const CombatStats = preload("res://scripts/net/combat/combat_stats.gd")
const SIT_REGEN_INTERVAL := 3.0
const SIT_REGEN_HP := 3
const SIT_REGEN_MP := 2

func _stand_if_sitting(actions: Array) -> bool:
	if not ctrl.sitting:
		return false
	ctrl.sitting = false
	ctrl._sit_acc = 0.0
	ctrl._sit_regen_acc = 0.0
	actions.append({"type": "sit", "on": false})
	actions.append({"type": "system_message", "text": "你站了起来。"})
	return true



func _tick_sit(delta: float) -> void:
	if not ctrl.sitting or ctrl.combat_stats == null:
		return
	if ctrl.awaiting_respawn or not ctrl.combat_stats.player_alive():
		ctrl.sitting = false
		ctrl._sit_acc = 0.0
		ctrl._sit_regen_acc = 0.0
		return
	# Rested EXP keeps 1s cadence (independent of HP/MP regen interval).
	ctrl._sit_acc += delta
	while ctrl._sit_acc >= 1.0:
		ctrl._sit_acc -= 1.0
		ctrl._pending_tick_actions.append_array(_tick_rested_accumulate())
	# Out-of-combat sit HP/MP: +3 HP / +2 MP every ~3s (2× in safe zone). Silent set_stat.
	var in_combat = false
	if ctrl.combat_engine != null and ctrl.combat_engine.has_method("player_in_combat"):
		in_combat = bool(ctrl.combat_engine.player_in_combat())
	if in_combat:
		ctrl._sit_regen_acc = 0.0
		return
	ctrl._sit_regen_acc += delta
	if ctrl._sit_regen_acc < SIT_REGEN_INTERVAL:
		return
	ctrl._sit_regen_acc = 0.0
	var p: Dictionary = ctrl.combat_stats.player
	var hp_max: int = int(p.get("hp_max", 100))
	var mp_max: int = int(p.get("mp_max", 50))
	var hp: int = int(p.get("hp", 0))
	var mp: int = int(p.get("mp", 0))
	var base_h: int = SIT_REGEN_HP
	var base_m: int = SIT_REGEN_MP
	if ctrl.player_in_safe_zone():
		base_h *= 2
		base_m *= 2
	var dh: int = 0
	var dm: int = 0
	if hp < hp_max:
		dh = mini(hp_max - hp, base_h)
	if mp < mp_max:
		dm = mini(mp_max - mp, base_m)
	if dh <= 0 and dm <= 0:
		return
	p["hp"] = hp + dh
	p["mp"] = mp + dm
	ctrl.combat_stats.player = p
	var set_act = {
		"type": "set_stat",
		"target": "player",
		"hp": int(p.get("hp", 0)),
		"hp_max": hp_max,
		"mp": int(p.get("mp", 0)),
		"mp_max": mp_max,
	}
	if ctrl.combat_stats.has_method("get_rested_exp"):
		set_act["rested_exp"] = int(ctrl.combat_stats.get_rested_exp())
		set_act["rested_exp_max"] = int(ctrl.combat_stats.rested_exp_max())
	ctrl._pending_tick_actions.append(set_act)



func _tick_rested_accumulate() -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null or not ctrl.sitting:
		return actions
	if not ctrl.player_in_safe_zone():
		return actions
	if not ctrl.combat_stats.has_method("add_rested_exp"):
		return actions
	ctrl.combat_stats.ensure_rested()
	var before: int = int(ctrl.combat_stats.get_rested_exp())
	var cap: int = int(ctrl.combat_stats.rested_exp_max())
	if before >= cap:
		return actions
	var per: int = int(CombatStats.RESTED_EXP_PER_TICK) if CombatStats != null else 5
	var result: Dictionary = ctrl.combat_stats.add_rested_exp(per)
	var after: int = int(result.get("rested_exp", before))
	if after == before:
		return actions
	actions.append({
		"type": "rested_update",
		"rested_exp": after,
		"rested_exp_max": int(result.get("rested_exp_max", cap)),
	})
	if bool(result.get("was_empty", false)) and after > 0:
		actions.append({"type": "system_message", "text": "开始积攒休息经验。"})
	if bool(result.get("hit_cap", false)) and not ctrl._rested_cap_notified:
		ctrl._rested_cap_notified = true
		actions.append({"type": "system_message", "text": "休息经验已满。"})
	elif after < cap:
		ctrl._rested_cap_notified = false
	return actions



func try_sit(on: bool = true) -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.sitting == on:
		actions.append({"type": "sit", "on": ctrl.sitting})
		return {"ok": true, "reason": "same", "actions": actions}
	ctrl.sitting = on
	ctrl._sit_acc = 0.0
	ctrl._sit_regen_acc = 0.0
	actions.append({"type": "sit", "on": ctrl.sitting})
	if ctrl.sitting:
		actions.append({"type": "system_message", "text": "你坐了下来。"})
	else:
		actions.append({"type": "system_message", "text": "你站了起来。"})
	return {"ok": true, "actions": actions}



func try_inn_rest(cost: int = 25) -> Dictionary:
	var actions: Array = []
	cost = maxi(int(cost), 0)
	if ctrl.combat_stats != null and not ctrl.combat_stats.player_alive():
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.combat_stats == null:
		actions.append({"type": "system_message", "text": "无法休息。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	var p: Dictionary = ctrl.combat_stats.player
	var hp_max: int = int(p.get("hp_max", 100))
	var mp_max: int = int(p.get("mp_max", 50))
	var hp: int = int(p.get("hp", 0))
	var mp: int = int(p.get("mp", 0))
	var has_harmful = false
	if ctrl.combat_stats.statuses != null:
		for s in ctrl.combat_stats.statuses.snapshot_statuses("player"):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var kind = str((s as Dictionary).get("kind", ""))
			if kind == "debuff" or kind == "dot":
				has_harmful = true
				break
	if hp >= hp_max and mp >= mp_max and not has_harmful:
		actions.append({"type": "system_message", "text": "你已经状态全满。"})
		return {"ok": false, "reason": "already_full", "actions": actions}
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not ctrl.inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足。"})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if ctrl.sitting:
		_stand_if_sitting(actions)
	p["hp"] = hp_max
	p["mp"] = mp_max
	ctrl.combat_stats.player = p
	if ctrl.combat_stats.statuses != null:
		ctrl.combat_stats.statuses.clear_harmful("player")
		actions.append(ctrl.combat_stats.statuses.status_update_action("player"))
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
	})
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({"type": "system_message", "text": "你休息得很好。"})
	return {"ok": true, "actions": actions}


