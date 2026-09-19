extends RefCounted
## Domain module: progression (level-up SP, attr allocate/respec, kill EXP).

var ctrl
func _init(c):
	ctrl = c

const SP_PER_LEVEL := 1
const ATTR_RESPEC_GOLD_COST := 30

func _append_level_up_sp(actions: Array, levels_gained: Array) -> void:
	if ctrl.combat_stats == null or levels_gained.is_empty():
		return
	ctrl.combat_stats.ensure_skill_book()
	var gained: int = int(levels_gained.size()) * SP_PER_LEVEL
	if gained > 0:
		ctrl.combat_stats.skill_book.grant_skill_points(gained)
		var book: Dictionary = ctrl.snapshot_skill_book()
		actions.append({
			"type": "skill_book_update",
			"known": book.get("known", []),
			"skill_points": int(book.get("skill_points", 0)),
		})
		actions.append({
			"type": "system_message",
			"text": "获得技能点 %d（当前 %d）。" % [gained, int(book.get("skill_points", 0))],
		})
	# Attr points already added inside grant_exp; announce + push snapshot.
	if ctrl.combat_stats.has_method("ensure_attrs"):
		ctrl.combat_stats.ensure_attrs()
	var attr_gained: int = int(levels_gained.size()) * 5
	var snap: Dictionary = ctrl.combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(snap.get("attr_points", 0)),
		"attrs": snap.get("attrs", {"str": 0, "agi": 0, "vit": 0, "intel": 0}),
		"combat": snap,
	})
	if attr_gained > 0:
		actions.append({
			"type": "system_message",
			"text": "获得属性点 %d（当前 %d）。" % [attr_gained, int(snap.get("attr_points", 0))],
		})



func try_allocate_attr(stat_key: String, amount: int = 1) -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats == null:
		actions.append({"type": "system_message", "text": "无法分配属性点。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not ctrl.combat_stats.player_alive() or ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	var result: Dictionary = ctrl.combat_stats.try_allocate_attr(stat_key, amount)
	actions.append({"type": "system_message", "text": str(result.get("message", ""))})
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var combat_snap: Dictionary = result.get("combat", {}) if typeof(result.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"combat": combat_snap,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(combat_snap.get("hp", 0)),
		"hp_max": int(combat_snap.get("hp_max", 0)),
		"mp": int(combat_snap.get("mp", 0)),
		"mp_max": int(combat_snap.get("mp_max", 0)),
		"level": int(combat_snap.get("level", 1)),
		"exp": int(combat_snap.get("exp", 0)),
		"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
		"atk": int(combat_snap.get("atk", 0)),
		"def": int(combat_snap.get("def", 0)),
		"attr_points": int(combat_snap.get("attr_points", 0)),
		"attrs": combat_snap.get("attrs", {}),
	})
	return {
		"ok": true,
		"reason": "ok",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"actions": actions,
	}



func try_attr_respec() -> Dictionary:
	var actions: Array = []
	if ctrl.combat_stats == null:
		actions.append({"type": "system_message", "text": "无法重置属性。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if not ctrl.combat_stats.player_alive() or ctrl.awaiting_respawn:
		actions.append({"type": "system_message", "text": "你已经倒下了。"})
		return {"ok": false, "reason": "dead", "actions": actions}
	if ctrl.in_duel():
		actions.append({"type": "system_message", "text": "决斗中无法重置属性。"})
		return {"ok": false, "reason": "duel", "actions": actions}
	var cost: int = ATTR_RESPEC_GOLD_COST
	if ctrl.inventory == null:
		actions.append({"type": "system_message", "text": "无法重置属性。"})
		return {"ok": false, "reason": "no_inv", "actions": actions}
	# Peek: any allocated attrs?
	ctrl.combat_stats.ensure_attrs()
	var peek: Dictionary = ctrl.combat_stats.player.get("attrs", {})
	var allocated = 0
	for k in ["str", "agi", "vit", "intel"]:
		allocated += int(peek.get(k, 0))
	if allocated <= 0:
		actions.append({"type": "system_message", "text": "没有可重置的属性点。"})
		return {"ok": false, "reason": "nothing", "actions": actions}
	if ctrl.inventory.get_gold() < cost:
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	if not ctrl.inventory.try_spend_gold(cost):
		actions.append({"type": "system_message", "text": "金币不足（需要 %d）。" % cost})
		return {"ok": false, "reason": "no_gold", "actions": actions}
	var result: Dictionary = ctrl.combat_stats.try_attr_respec_refund()
	if not bool(result.get("ok", false)):
		ctrl.inventory.add_gold(cost)
		actions.append({"type": "system_message", "text": str(result.get("message", "无法重置属性。"))})
		return {"ok": false, "reason": str(result.get("reason", "fail")), "actions": actions}
	var combat_snap: Dictionary = result.get("combat", {}) if typeof(result.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
	actions.append({
		"type": "attr_update",
		"attr_points": int(result.get("attr_points", 0)),
		"attrs": result.get("attrs", {}),
		"combat": combat_snap,
	})
	actions.append({
		"type": "set_stat",
		"target": "player",
		"hp": int(combat_snap.get("hp", 0)),
		"hp_max": int(combat_snap.get("hp_max", 0)),
		"mp": int(combat_snap.get("mp", 0)),
		"mp_max": int(combat_snap.get("mp_max", 0)),
		"level": int(combat_snap.get("level", 1)),
		"exp": int(combat_snap.get("exp", 0)),
		"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
		"atk": int(combat_snap.get("atk", 0)),
		"def": int(combat_snap.get("def", 0)),
		"attr_points": int(combat_snap.get("attr_points", 0)),
		"attrs": combat_snap.get("attrs", {}),
	})
	actions.append({
		"type": "inventory_update",
		"items": ctrl.inventory.snapshot(),
		"gold": ctrl.inventory.get_gold(),
	})
	actions.append({
		"type": "system_message",
		"text": str(result.get("message", "已重置属性。")),
	})
	return {
		"ok": true,
		"reason": "ok",
		"refunded": int(result.get("refunded", 0)),
		"gold_spent": cost,
		"attr_points": int(result.get("attr_points", 0)),
		"actions": actions,
	}



func grant_kill_exp(npc_id: String) -> Array:
	var actions: Array = []
	npc_id = npc_id.strip_edges()
	if npc_id.is_empty() or ctrl.combat_stats == null:
		return actions
	var npc_lv: int = 1
	if ctrl.combat_stats.npcs.has(npc_id):
		npc_lv = maxi(int(ctrl.combat_stats.npcs[npc_id].get("level", 1)), 1)
	elif ctrl.npc_spawn_templates.has(npc_id):
		var tmpl: Dictionary = ctrl.npc_spawn_templates[npc_id]
		if tmpl.has("level"):
			npc_lv = maxi(int(tmpl.get("level", 1)), 1)
		else:
			# Match combat_stats.ensure_npc hash fallback when template lacks level.
			npc_lv = 1 + absi(hash(npc_id + ":lv")) % 8
	else:
		npc_lv = 1 + absi(hash(npc_id + ":lv")) % 8
	var base_amount: int = ctrl.combat_stats.kill_exp_for_npc_level(npc_lv)
	var amount: int = base_amount
	var party_n: int = 0
	if ctrl.in_party():
		party_n = ctrl._party_online_same_map_count()
		amount = ctrl._party_kill_exp_with_bonus(base_amount, party_n)
	# Rested bonus: up to 2× while pool remains (bonus = min(pool, grant_base)).
	var grant_base: int = amount
	var rested_bonus: int = 0
	if ctrl.combat_stats.has_method("spend_rested_for_kill"):
		rested_bonus = int(ctrl.combat_stats.spend_rested_for_kill(grant_base))
		amount = grant_base + rested_bonus
		if rested_bonus > 0:
			ctrl._rested_cap_notified = false
	var summary: Dictionary = ctrl.combat_stats.grant_exp(amount)
	var rested_now: int = int(ctrl.combat_stats.get_rested_exp()) if ctrl.combat_stats.has_method("get_rested_exp") else 0
	var rested_max: int = int(ctrl.combat_stats.rested_exp_max()) if ctrl.combat_stats.has_method("rested_exp_max") else 0
	actions.append({
		"type": "exp_gain",
		"amount": int(summary.get("amount", amount)),
		"exp": int(summary.get("exp", 0)),
		"exp_to_next": int(summary.get("exp_to_next", 0)),
		"level": int(summary.get("level", 1)),
		"rested_bonus": rested_bonus,
		"rested_exp": rested_now,
		"rested_exp_max": rested_max,
	})
	actions.append({
		"type": "system_message",
		"text": "获得经验 %d" % int(summary.get("amount", amount)),
	})
	if rested_bonus > 0:
		actions.append({
			"type": "system_message",
			"text": "休息加成 +%d" % rested_bonus,
		})
		actions.append({
			"type": "rested_update",
			"rested_exp": rested_now,
			"rested_exp_max": rested_max,
		})
	if party_n > 1 and grant_base > base_amount:
		actions.append({
			"type": "system_message",
			"text": "队伍加成",
		})
	if bool(summary.get("leveled", false)):
		var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
		for lv_v in summary.get("levels_gained", []):
			var new_lv: int = int(lv_v)
			actions.append({
				"type": "level_up",
				"level": new_lv,
				"combat": combat_snap,
			})
			actions.append({
				"type": "system_message",
				"text": "升级到 Lv.%d！" % new_lv,
			})
		_append_level_up_sp(actions, summary.get("levels_gained", []))
		# Also push set_stat so HUD bars pick up new max HP/MP.
		actions.append({
			"type": "set_stat",
			"target": "player",
			"hp": int(combat_snap.get("hp", 0)),
			"hp_max": int(combat_snap.get("hp_max", 0)),
			"mp": int(combat_snap.get("mp", 0)),
			"mp_max": int(combat_snap.get("mp_max", 0)),
			"level": int(combat_snap.get("level", 1)),
			"exp": int(combat_snap.get("exp", 0)),
			"exp_to_next": int(combat_snap.get("exp_to_next", 0)),
			"atk": int(combat_snap.get("atk", 0)),
			"def": int(combat_snap.get("def", 0)),
			"attr_points": int(combat_snap.get("attr_points", 0)),
			"attrs": combat_snap.get("attrs", {}),
		})
		actions.append_array(ctrl._sync_achievement_level(int(combat_snap.get("level", 1))))
	return actions


