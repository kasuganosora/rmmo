extends RefCounted
## Title / achievement definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/titles.json",
	"res://data/combat/titles.json",
]

## id -> def Dictionary
var _by_id: Dictionary = {}
## Stable ordered list of ids (catalog order).
var _order: Array = []


func load_catalog() -> void:
	_by_id.clear()
	_order.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("titles", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var tid := str(d.get("id", "")).strip_edges()
		if tid.is_empty():
			continue
		_by_id[tid] = _normalize_def(d)
		_order.append(tid)
	if _by_id.is_empty():
		_load_builtin_fallback()


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
	title_id = title_id.strip_edges()
	if _by_id.has(title_id):
		return (_by_id[title_id] as Dictionary).duplicate(true)
	return {}


func has_title(title_id: String) -> bool:
	return _by_id.has(title_id.strip_edges())


func title_name(title_id: String) -> String:
	var d: Dictionary = get_title(title_id)
	if d.is_empty():
		return title_id.strip_edges()
	return str(d.get("name", title_id))


func all_ids() -> Array:
	if not _order.is_empty():
		return _order.duplicate()
	var ids: Array = _by_id.keys()
	ids.sort()
	return ids


## Ordered list of title defs for HUD.
func list_all() -> Array:
	var out: Array = []
	for tid in all_ids():
		out.append(get_title(str(tid)))
	return out


## Titles whose require is fully met by counters, not yet unlocked.
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


static func _load_json_first(paths: Array) -> Variant:
	for p in paths:
		var path := str(p)
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null
