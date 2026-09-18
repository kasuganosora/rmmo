extends RefCounted
## Session-owned known-skill set + skill points (MockServer / CombatStats).

## skill_id -> true
var known: Dictionary = {}
var skill_points: int = 0


func clear() -> void:
	known.clear()
	skill_points = 0


func is_known(skill_id: String) -> bool:
	skill_id = skill_id.strip_edges()
	if skill_id.is_empty():
		return false
	return known.has(skill_id)


func list_known() -> Array:
	var ids: Array = known.keys()
	ids.sort()
	var out: Array = []
	for sid in ids:
		out.append(str(sid))
	return out


func snapshot() -> Dictionary:
	return {
		"known": list_known(),
		"skill_points": maxi(skill_points, 0),
	}


func apply_snapshot(data: Dictionary) -> void:
	known.clear()
	var kv: Variant = data.get("known", [])
	if typeof(kv) == TYPE_ARRAY:
		for sid_v in kv:
			var sid := str(sid_v).strip_edges()
			if not sid.is_empty():
				known[sid] = true
	skill_points = maxi(int(data.get("skill_points", 0)), 0)
	known["basic_attack"] = true


## Reset to starter set from catalog. Starting SP = 0.
func grant_starters(catalog) -> void:
	clear()
	skill_points = 0
	known["basic_attack"] = true
	if catalog == null:
		return
	var ids: Array = []
	if catalog.has_method("all_ids"):
		ids = catalog.all_ids()
	elif catalog.has_method("list_all"):
		for d_v in catalog.list_all():
			if typeof(d_v) == TYPE_DICTIONARY:
				ids.append(str(d_v.get("id", "")))
	for sid_v in ids:
		var sid := str(sid_v).strip_edges()
		if sid.is_empty():
			continue
		var def: Dictionary = {}
		if catalog.has_method("get_skill"):
			def = catalog.get_skill(sid)
		if def.is_empty():
			continue
		if _is_starter_def(def):
			known[sid] = true
	known["basic_attack"] = true


func _is_starter_def(def: Dictionary) -> bool:
	if bool(def.get("starter", false)):
		return true
	if bool(def.get("auto_known", false)):
		return true
	var sid := str(def.get("id", "")).strip_edges()
	return sid == "basic_attack"


func grant_skill_points(amount: int) -> int:
	if amount > 0:
		skill_points = maxi(skill_points, 0) + amount
	return skill_points


## {ok, reason, message, skill_id, name, skill_points, known}
func try_learn(skill_id: String, catalog, player_level: int) -> Dictionary:
	skill_id = skill_id.strip_edges()
	var out := {
		"ok": false,
		"reason": "",
		"message": "",
		"skill_id": skill_id,
		"name": skill_id,
		"skill_points": skill_points,
		"known": list_known(),
	}
	if skill_id.is_empty():
		out["reason"] = "empty"
		out["message"] = "无效技能。"
		return out
	if catalog == null or not catalog.has_method("get_skill"):
		out["reason"] = "no_catalog"
		out["message"] = "未知技能。"
		return out
	var def: Dictionary = catalog.get_skill(skill_id)
	if def.is_empty():
		out["reason"] = "unknown"
		out["message"] = "未知技能。"
		return out
	var sname := str(def.get("name", skill_id))
	out["name"] = sname
	if is_known(skill_id):
		out["reason"] = "already"
		out["message"] = "已学会【%s】。" % sname
		return out
	var need_lv: int = maxi(int(def.get("learn_level", 1)), 1)
	var cost: int = maxi(int(def.get("sp_cost", 1)), 0)
	if _is_starter_def(def):
		need_lv = 1
		cost = 0
	if player_level < need_lv:
		out["reason"] = "level"
		out["message"] = "等级不足，需要 Lv.%d。" % need_lv
		return out
	if skill_points < cost:
		out["reason"] = "sp"
		out["message"] = "技能点不足（需要 %d，当前 %d）。" % [cost, skill_points]
		return out
	skill_points -= cost
	known[skill_id] = true
	out["ok"] = true
	out["reason"] = "ok"
	out["message"] = "学会了【%s】。" % sname
	out["skill_points"] = skill_points
	out["known"] = list_known()
	return out


## Reset learned skills (keep basic_attack only); refund catalog sp_cost into skill_points.
## {ok, reason, message, refunded_sp, known, skill_points, cleared}
func try_respec(catalog) -> Dictionary:
	var out := {
		"ok": false,
		"reason": "",
		"message": "",
		"refunded_sp": 0,
		"known": list_known(),
		"skill_points": skill_points,
		"cleared": [],
	}
	var cleared: Array = []
	var refund := 0
	for sid_v in list_known():
		var sid := str(sid_v).strip_edges()
		if sid.is_empty() or sid == "basic_attack":
			continue
		cleared.append(sid)
		var cost := 0
		if catalog != null and catalog.has_method("get_skill"):
			var def: Dictionary = catalog.get_skill(sid)
			if not def.is_empty():
				cost = maxi(int(def.get("sp_cost", 0)), 0)
				# Starters were free at learn time; still sum listed sp_cost (usually 0).
				if _is_starter_def(def):
					cost = 0
		refund += cost
	if cleared.is_empty():
		out["reason"] = "nothing"
		out["message"] = "没有可重置的技能。"
		return out
	known.clear()
	known["basic_attack"] = true
	skill_points = maxi(skill_points, 0) + refund
	out["ok"] = true
	out["reason"] = "ok"
	out["message"] = "已重置技能，返还技能点 %d。" % refund
	out["refunded_sp"] = refund
	out["known"] = list_known()
	out["skill_points"] = skill_points
	out["cleared"] = cleared
	return out
