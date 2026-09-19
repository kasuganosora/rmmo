extends RefCounted
## Domain module: titles (snapshot, equip, counters).

var ctrl
func _init(c):
	ctrl = c

func snapshot_titles() -> Dictionary:
	if ctrl.combat_stats == null:
		return {
			"counters": {"kills": 0, "crafts": 0, "deaths": 0},
			"unlocked_titles": [],
			"active_title": "",
			"titles": [],
			"kills": 0,
			"crafts": 0,
			"deaths": 0,
		}
	var snap: Dictionary = ctrl.combat_stats.snapshot_titles()
	var rows: Array = []
	var unlocked: Array = snap.get("unlocked_titles", [])
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var catalog_rows: Array = []
	if ctrl.title_catalog != null:
		catalog_rows = ctrl.title_catalog.list_all()
	for def in catalog_rows:
		if typeof(def) != TYPE_DICTIONARY:
			continue
		var tid = str(def.get("id", ""))
		var row: Dictionary = def.duplicate(true)
		row["unlocked"] = have.has(tid)
		row["active"] = tid == str(snap.get("active_title", ""))
		rows.append(row)
	snap["titles"] = rows
	return snap



func _title_update_action() -> Dictionary:
	return {"type": "title_update", "titles": snapshot_titles()}



func _note_title_counter(key: String, amount: int = 1) -> Array:
	var actions: Array = []
	if ctrl.combat_stats == null or amount == 0:
		return actions
	ctrl.combat_stats.bump_title_counter(key, amount)
	if ctrl.title_catalog == null:
		actions.append(_title_update_action())
		return actions
	var newly: Array = ctrl.title_catalog.check_unlocks(
		ctrl.combat_stats.title_counters,
		ctrl.combat_stats.unlocked_titles
	)
	for tid in newly:
		if ctrl.combat_stats.unlock_title(str(tid)):
			var tname: String = str(ctrl.title_catalog.title_name(str(tid)))
			actions.append({"type": "system_message", "text": "解锁称号：%s" % tname})
	actions.append(_title_update_action())
	return actions



func try_title_equip(title_id: String) -> Dictionary:
	var actions: Array = []
	title_id = str(title_id).strip_edges()
	if ctrl.combat_stats == null:
		actions.append({"type": "system_message", "text": "称号不可用。"})
		return {"ok": false, "reason": "no_stats", "actions": actions}
	if title_id.is_empty():
		var r0: Dictionary = ctrl.combat_stats.try_title_equip("")
		actions.append(_title_update_action())
		actions.append({"type": "system_message", "text": "已卸下称号。"})
		return {"ok": bool(r0.get("ok", false)), "reason": str(r0.get("reason", "")), "actions": actions}
	if ctrl.title_catalog != null and not ctrl.title_catalog.has_title(title_id):
		actions.append({"type": "system_message", "text": "未知称号。"})
		return {"ok": false, "reason": "unknown", "actions": actions}
	var r: Dictionary = ctrl.combat_stats.try_title_equip(title_id)
	if not bool(r.get("ok", false)):
		var reason = str(r.get("reason", "locked"))
		var msg = "尚未解锁该称号。"
		if reason == "unknown":
			msg = "未知称号。"
		actions.append({"type": "system_message", "text": msg})
		return {"ok": false, "reason": reason, "actions": actions}
	var tname: String = title_id
	if ctrl.title_catalog != null:
		tname = str(ctrl.title_catalog.title_name(title_id))
	actions.append(_title_update_action())
	actions.append({"type": "system_message", "text": "已装备称号：%s" % tname})
	return {"ok": true, "actions": actions}


