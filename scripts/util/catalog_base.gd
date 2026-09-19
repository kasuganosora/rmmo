extends RefCounted
## Base class for JSON-backed `id -> def` catalogs (item / skill / achievement /
## recipe / title / fish / gather / ...). Consolidates the repeated
## load_catalog / all_ids / list_all / get/has/register / icon / _load_json_first
## that was previously written out per catalog.
##
## Subclass contract (template hooks):
##   _data_paths() -> Array        JSON candidate paths (first existing wins)
##   _list_key() -> String         key of the def list inside the JSON dict
##   _normalize_def(d) -> Dictionary   per-catalog field normalization
##   _load_builtin_fallback() -> void  per-catalog builtin defs when JSON missing/empty

const JsonUtil = preload("res://scripts/util/json_util.gd")

var _by_id: Dictionary = {}


func _data_paths() -> Array:
	return []


func _list_key() -> String:
	return ""


func _normalize_def(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


func _load_builtin_fallback() -> void:
	pass


func load_catalog() -> void:
	_by_id.clear()
	var raw: Variant = _load_json_first(_data_paths())
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get(_list_key(), [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for entry in list_v:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var iid := str(entry.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		_by_id[iid] = _normalize_def(entry)
	if _by_id.is_empty():
		_load_builtin_fallback()


func all_ids() -> Array:
	return _by_id.keys()


func has_id(id: String) -> bool:
	return _by_id.has(id.strip_edges())


func get_def(id: String) -> Dictionary:
	id = id.strip_edges()
	if _by_id.has(id):
		return (_by_id[id] as Dictionary).duplicate(true)
	return {}


## Runtime inject for tests / pack overrides. Does not persist.
func register_def(def: Dictionary) -> String:
	var iid := str(def.get("id", "")).strip_edges()
	if iid.is_empty():
		return ""
	_by_id[iid] = _normalize_def(def)
	return iid


## Ordered list of defs (sorted by id) for HUD text labels.
func list_all() -> Array:
	var ids: Array = _by_id.keys()
	ids.sort()
	var out: Array = []
	for iid in ids:
		out.append(get_def(str(iid)))
	return out


func icon_index_of(id: String) -> int:
	var def := get_def(id)
	if def.is_empty():
		return -1
	return int(def.get("icon_index", -1))


func icon_id_of(id: String) -> String:
	var def := get_def(id)
	if def.is_empty():
		return ""
	return str(def.get("icon", "")).strip_edges()


func icon_ref_of(id: String) -> String:
	var def := get_def(id)
	if def.is_empty():
		return ""
	var r := str(def.get("icon_ref", "")).strip_edges()
	if not r.is_empty():
		return r
	var iid := str(def.get("icon", "")).strip_edges()
	if iid.is_empty():
		return ""
	return "content://icon/%s" % iid


static func _load_json_first(paths: Array) -> Variant:
	return JsonUtil.load_first(paths)
