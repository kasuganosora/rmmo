extends RefCounted
## Crafting recipe definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/recipes.json",
	"res://data/combat/recipes.json",
]

## id -> def Dictionary
var _by_id: Dictionary = {}


func load_catalog() -> void:
	_by_id.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		_load_builtin_fallback()
		return
	var list_v: Variant = (raw as Dictionary).get("recipes", [])
	if typeof(list_v) != TYPE_ARRAY:
		_load_builtin_fallback()
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var rid := str(d.get("id", "")).strip_edges()
		if rid.is_empty():
			continue
		_by_id[rid] = _normalize_def(d)
	if _by_id.is_empty():
		_load_builtin_fallback()


func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var rid := str(out.get("id", "")).strip_edges()
	out["id"] = rid
	if not out.has("name") or str(out.get("name", "")).strip_edges() == "":
		out["name"] = rid
	var ings: Array = []
	var ings_v: Variant = out.get("ingredients", [])
	if typeof(ings_v) == TYPE_ARRAY:
		for row in ings_v:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var iid := str(row.get("id", "")).strip_edges()
			var q: int = maxi(int(row.get("qty", 0)), 0)
			if iid.is_empty() or q <= 0:
				continue
			ings.append({"id": iid, "qty": q})
	out["ingredients"] = ings
	var out_v: Variant = out.get("output", {})
	var oid := ""
	var oq := 0
	if typeof(out_v) == TYPE_DICTIONARY:
		oid = str(out_v.get("id", "")).strip_edges()
		oq = maxi(int(out_v.get("qty", 1)), 1)
	out["output"] = {"id": oid, "qty": oq}
	out["gold_cost"] = maxi(int(out.get("gold_cost", 0)), 0)
	out["learn_level"] = maxi(int(out.get("learn_level", 1)), 1)
	# Prefer explicit craft_level; else map learn_level → craft req (not combat level).
	if out.has("craft_level"):
		out["craft_level"] = maxi(int(out.get("craft_level", 1)), 1)
	else:
		out["craft_level"] = int(out["learn_level"])
	return out


func get_recipe(recipe_id: String) -> Dictionary:
	recipe_id = recipe_id.strip_edges()
	if _by_id.has(recipe_id):
		return (_by_id[recipe_id] as Dictionary).duplicate(true)
	return {}


func has_recipe(recipe_id: String) -> bool:
	return _by_id.has(recipe_id.strip_edges())


## Runtime inject for tests / pack overrides. Does not persist.
func register_recipe(def: Dictionary) -> String:
	var rid := str(def.get("id", "")).strip_edges()
	if rid.is_empty():
		return ""
	_by_id[rid] = _normalize_def(def)
	return rid


func all_ids() -> Array:
	return _by_id.keys()


## Ordered list of recipe defs for HUD.
func list_all() -> Array:
	var ids: Array = _by_id.keys()
	ids.sort()
	var out: Array = []
	for rid in ids:
		out.append(get_recipe(str(rid)))
	return out


func _load_builtin_fallback() -> void:
	_by_id.clear()
	register_recipe({
		"id": "craft_hp_potion",
		"name": "调制小型生命药水",
		"ingredients": [{"id": "wild_herb", "qty": 2}],
		"output": {"id": "potion_hp_small", "qty": 1},
		"gold_cost": 2,
		"learn_level": 1,
	})
	register_recipe({
		"id": "craft_mp_potion",
		"name": "调制小型魔法药水",
		"ingredients": [
			{"id": "wild_herb", "qty": 1},
			{"id": "slime_jelly", "qty": 1},
		],
		"output": {"id": "potion_mp_small", "qty": 1},
		"gold_cost": 2,
		"learn_level": 1,
	})
	register_recipe({
		"id": "craft_leather_cap",
		"name": "缝制皮帽",
		"ingredients": [
			{"id": "torn_cloth", "qty": 3},
			{"id": "monster_fang", "qty": 1},
		],
		"output": {"id": "leather_cap", "qty": 1},
		"gold_cost": 5,
		"learn_level": 1,
		"craft_level": 2,
	})


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
