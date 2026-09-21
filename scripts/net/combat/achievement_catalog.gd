extends "res://scripts/util/catalog_base.gd"
## Achievement definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"combat/achievements.json",
]

func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "achievements"


## Stable ordered list of ids (catalog order).
var _order: Array = []


func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var aid := str(out.get("id", "")).strip_edges()
	out["id"] = aid
	if not out.has("name") or str(out.get("name", "")).strip_edges() == "":
		out["name"] = aid
	out["desc"] = str(out.get("desc", "")).strip_edges()
	out["letter"] = str(out.get("letter", "")).strip_edges()
	out["icon_index"] = int(out.get("icon_index", 0))
	var req: Dictionary = {}
	var req_v: Variant = out.get("require", {})
	if typeof(req_v) == TYPE_DICTIONARY:
		for k in (req_v as Dictionary).keys():
			var key := str(k).strip_edges()
			var n: int = maxi(int(req_v[k]), 0)
			if key.is_empty() or n <= 0:
				continue
			req[key] = n
	out["require"] = req
	var reward: Dictionary = {}
	var rew_v: Variant = out.get("reward", {})
	if typeof(rew_v) == TYPE_DICTIONARY:
		var g: int = maxi(int(rew_v.get("gold", 0)), 0)
		var e: int = maxi(int(rew_v.get("exp", 0)), 0)
		if g > 0:
			reward["gold"] = g
		if e > 0:
			reward["exp"] = e
	out["reward"] = reward
	return out


func get_achievement(ach_id: String) -> Dictionary:
	return get_def(ach_id)
func has_achievement(ach_id: String) -> bool:
	return has_id(ach_id)
func achievement_name(ach_id: String) -> String:
	var d: Dictionary = get_achievement(ach_id)
	if d.is_empty():
		return ach_id.strip_edges()
	return str(d.get("name", ach_id))


func check_unlocks(counters: Dictionary, unlocked: Array) -> Array:
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var newly: Array = []
	for aid in all_ids():
		if have.has(str(aid)):
			continue
		var def: Dictionary = get_achievement(str(aid))
		if def.is_empty():
			continue
		var req_v: Variant = def.get("require", {})
		if typeof(req_v) != TYPE_DICTIONARY or (req_v as Dictionary).is_empty():
			continue
		var ok := true
		for k in (req_v as Dictionary).keys():
			var need: int = int(req_v[k])
			var have_n: int = int(counters.get(str(k), 0))
			if have_n < need:
				ok = false
				break
		if ok:
			newly.append(str(aid))
	return newly


func _load_builtin_fallback() -> void:
	_by_id.clear()
	_order.clear()
	for row in [
		{"id": "ach_first_kill", "name": "初战告捷", "desc": "击杀 1 只怪物", "require": {"kills": 1}, "reward": {"gold": 20, "exp": 10}},
		{"id": "ach_gather_10", "name": "勤劳采撷", "desc": "采集 10 次", "require": {"gathers": 10}, "reward": {"gold": 30, "exp": 15}},
		{"id": "ach_level_5", "name": "初出茅庐", "desc": "达到等级 5", "require": {"level": 5}, "reward": {"gold": 50, "exp": 25}},
		{"id": "ach_party", "name": "结伴而行", "desc": "创建或加入队伍 1 次", "require": {"party": 1}, "reward": {"gold": 25, "exp": 10}},
	]:
		var aid := str(row.get("id", ""))
		_by_id[aid] = _normalize_def(row)
		_order.append(aid)

