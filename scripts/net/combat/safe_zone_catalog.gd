extends RefCounted
## Inclusive AABB safe-zone rects per map (town / inn hub). Loaded from JSON.

const JsonUtil = preload("res://scripts/util/json_util.gd")

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/safe_zones.json",
	"res://data/combat/safe_zones.json",
]

## map_id -> Array[Dictionary] of {id, min_x, min_y, max_x, max_y}
var _by_map: Dictionary = {}


func load_catalog() -> void:
	_by_map.clear()
	var raw: Variant = JsonUtil.load_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("zones", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_add_zone(item)
	if _by_map.is_empty():
		_load_builtin_fallback()


func _load_builtin_fallback() -> void:
	_by_map.clear()
	_add_zone({
		"id": "demo_town",
		"map_id": "demo_map",
		"min_x": 5,
		"min_y": 11,
		"max_x": 16,
		"max_y": 19,
	})


func _add_zone(d: Dictionary) -> void:
	var mid := str(d.get("map_id", "")).strip_edges()
	if mid.is_empty():
		return
	var z := {
		"id": str(d.get("id", "")).strip_edges(),
		"map_id": mid,
		"min_x": int(d.get("min_x", d.get("x0", 0))),
		"min_y": int(d.get("min_y", d.get("y0", 0))),
		"max_x": int(d.get("max_x", d.get("x1", 0))),
		"max_y": int(d.get("max_y", d.get("y1", 0))),
	}
	if z["max_x"] < z["min_x"]:
		var tx: int = z["min_x"]
		z["min_x"] = z["max_x"]
		z["max_x"] = tx
	if z["max_y"] < z["min_y"]:
		var ty: int = z["min_y"]
		z["min_y"] = z["max_y"]
		z["max_y"] = ty
	if not _by_map.has(mid):
		_by_map[mid] = []
	(_by_map[mid] as Array).append(z)


func is_in_safe_zone(map_id: String, x: int, y: int) -> bool:
	map_id = map_id.strip_edges()
	if map_id.is_empty() or not _by_map.has(map_id):
		return false
	for z in _by_map[map_id]:
		if typeof(z) != TYPE_DICTIONARY:
			continue
		if x >= int(z.get("min_x", 0)) and x <= int(z.get("max_x", 0)) \
				and y >= int(z.get("min_y", 0)) and y <= int(z.get("max_y", 0)):
			return true
	return false


func zones_for_map(map_id: String) -> Array:
	map_id = map_id.strip_edges()
	if not _by_map.has(map_id):
		return []
	var out: Array = []
	for z in _by_map[map_id]:
		if typeof(z) == TYPE_DICTIONARY:
			out.append((z as Dictionary).duplicate(true))
	return out
