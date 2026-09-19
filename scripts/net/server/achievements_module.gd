extends RefCounted
## Domain module: achievements (snapshot, unlock, counters, rewards).

var ctrl
func _init(c):
	ctrl = c

func snapshot_achievements() -> Dictionary:
	if ctrl.combat_stats == null:
		return {
			"counters": {"kills": 0, "gathers": 0, "level": 1, "party": 0},
			"unlocked_achievements": [],
			"achievements": [],
			"kills": 0,
			"gathers": 0,
			"level": 1,
			"party": 0,
		}
	var snap: Dictionary = ctrl.combat_stats.snapshot_achievements()
	var rows: Array = []
	var unlocked: Array = snap.get("unlocked_achievements", [])
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var catalog_rows: Array = []
	if ctrl.achievement_catalog != null:
		catalog_rows = ctrl.achievement_catalog.list_all()
	for def in catalog_rows:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var aid = str(def.get("id", ""))
		var row: Dictionary = def.duplicate(true)
		row["unlocked"] = have.has(aid)
		rows.append(row)
	snap["achievements"] = rows
	return snap



func _achievement_update_action() -> Dictionary:
	return {"type": "achievement_update", "achievements": snapshot_achievements()}



func _grant_achievement_reward(def: Dictionary) -> Array:
	var actions: Array = []
	var rew_v: Variant = def.get("reward", {})
	if typeof(rew_v) != TYPE_DICTIONARY:
		return actions
	var rew: Dictionary = rew_v
	var gold: int = maxi(int(rew.get("gold", 0)), 0)
	var exp_amt: int = maxi(int(rew.get("exp", 0)), 0)
	if gold > 0 and ctrl.inventory != null:
		ctrl.inventory.add_gold(gold)
		actions.append({
			"type": "inventory_update",
			"items": ctrl.inventory.snapshot(),
			"gold": ctrl.inventory.get_gold(),
		})
		actions.append({"type": "system_message", "text": "成就奖励：金币 +%d" % gold})
	if exp_amt > 0 and ctrl.combat_stats != null:
		var summary: Dictionary = ctrl.combat_stats.grant_exp(exp_amt)
		actions.append({
			"type": "exp_gain",
			"amount": int(summary.get("amount", exp_amt)),
			"exp": int(summary.get("exp", 0)),
			"exp_to_next": int(summary.get("exp_to_next", 0)),
			"level": int(summary.get("level", 1)),
		})
		actions.append({"type": "system_message", "text": "成就奖励：经验 +%d" % int(summary.get("amount", exp_amt))})
		if bool(summary.get("leveled", false)):
			var combat_snap: Dictionary = summary.get("combat", {}) if typeof(summary.get("combat", {})) == TYPE_DICTIONARY else ctrl.combat_stats.snapshot_player_stats()
			for lv_v in summary.get("levels_gained", []):
				actions.append({"type": "level_up", "level": int(lv_v), "combat": combat_snap})
				actions.append({"type": "system_message", "text": "升级到 Lv.%d！" % int(lv_v)})
			ctrl._append_level_up_sp(actions, summary.get("levels_gained", []))
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
	return actions



func _flush_achievement_unlocks() -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null:
		return actions
	if ctrl.achievement_catalog == null:
		actions.append(_achievement_update_action())
		return actions
	var newly: Array = ctrl.achievement_catalog.check_unlocks(
		ctrl.combat_stats.achievement_counters,
		ctrl.combat_stats.unlocked_achievements
	)
	for aid in newly:
		if ctrl.combat_stats.unlock_achievement(str(aid)):
			var def: Dictionary = ctrl.achievement_catalog.get_achievement(str(aid))
			var aname: String = str(ctrl.achievement_catalog.achievement_name(str(aid)))
			actions.append({"type": "system_message", "text": "成就解锁：%s" % aname})
			actions.append_array(_grant_achievement_reward(def))
	actions.append(_achievement_update_action())
	return actions



func _note_achievement_counter(key: String, amount: int = 1) -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null or amount == 0:
		return actions
	ctrl.combat_stats.bump_achievement_counter(key, amount)
	actions.append_array(_flush_achievement_unlocks())
	return actions



func _sync_achievement_level(level: int) -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null:
		return actions
	var before: int = int(ctrl.combat_stats.achievement_counters.get("level", 1))
	var after: int = ctrl.combat_stats.set_achievement_counter_at_least("level", level)
	if after == before and after < level:
		return actions
	if after == before:
		# Still flush in case require was already met but unlock pending (tests).
		pass
	actions.append_array(_flush_achievement_unlocks())
	return actions



func force_achievement_progress(key: String, value: int) -> Dictionary:
	var actions: Array = []
	key = str(key).strip_edges()
	if ctrl.combat_stats == null or key.is_empty():
		return {"ok": false, "reason": "no_stats", "actions": actions}
	ctrl.combat_stats.achievement_counters[key] = maxi(int(value), 0)
	actions.append_array(_flush_achievement_unlocks())
	return {"ok": true, "actions": actions, "achievements": snapshot_achievements()}



func force_achievement_unlock(ach_id: String) -> Dictionary:
	var actions: Array = []
	ach_id = str(ach_id).strip_edges()
	if ctrl.combat_stats == null:
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if ctrl.achievement_catalog != null and not ctrl.achievement_catalog.has_achievement(ach_id):
		actions.append({"type": "system_message", "text": "未知成就。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	if not ctrl.combat_stats.unlock_achievement(ach_id):
		return {"ok": false, "reason": "already", "actions": actions, "achievements": snapshot_achievements()}
	var def: Dictionary = {}
	if ctrl.achievement_catalog != null:
		def = ctrl.achievement_catalog.get_achievement(ach_id)
	var aname: String = ach_id
	if ctrl.achievement_catalog != null:
		aname = str(ctrl.achievement_catalog.achievement_name(ach_id))
	actions.append({"type": "system_message", "text": "成就解锁：%s" % aname})
	actions.append_array(_grant_achievement_reward(def))
	actions.append(_achievement_update_action())
	return {"ok": true, "actions": actions, "achievements": snapshot_achievements()}


