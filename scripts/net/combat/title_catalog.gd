extends "res://scripts/util/catalog_base.gd"
## Title / achievement definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"combat/titles.json",
]

func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "titles"


## Stable ordered list of ids (catalog order).
var _order: Array = []


func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var tid := str(out.get("id", "")).strip_edges()
	out["id"] = tid
	if not out.has("name") or str(out.get("name", "")).strip_edges() == "":
		out["name"] = tid
	out["desc"] = str(out.get("desc", "")).strip_edges()
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
	return out


func get_title(title_id: String) -> Dictionary:
	return get_def(title_id)
func has_title(title_id: String) -> bool:
	return has_id(title_id)
func title_name(title_id: String) -> String:
	var d: Dictionary = get_title(title_id)
	if d.is_empty():
		return title_id.strip_edges()
	return str(d.get("name", title_id))


func check_unlocks(counters: Dictionary, unlocked: Array) -> Array:
	var have: Dictionary = {}
	for u in unlocked:
		have[str(u)] = true
	var newly: Array = []
	for tid in all_ids():
		if have.has(str(tid)):
			continue
		var def: Dictionary = get_title(str(tid))
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
			newly.append(str(tid))
	return newly


func _load_builtin_fallback() -> void:
	_by_id.clear()
	_order.clear()
	for row in [
		{"id": "newbie_slayer", "name": "初出茅庐", "desc": "击杀 1 只怪物", "require": {"kills": 1}},
		{"id": "hunter", "name": "猎手", "desc": "击杀 10 只怪物", "require": {"kills": 10}},
		{"id": "crafter", "name": "巧手", "desc": "成功制作 1 次", "require": {"crafts": 1}},
		{"id": "fallen", "name": "屡败屡战", "desc": "死亡 1 次", "require": {"deaths": 1}},
	]:
		var tid := str(row.get("id", ""))
		_by_id[tid] = _normalize_def(row)
		_order.append(tid)

