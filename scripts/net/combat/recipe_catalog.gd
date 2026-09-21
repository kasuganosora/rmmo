extends "res://scripts/util/catalog_base.gd"
## Crafting recipe definitions loaded from JSON (shared path with future GameServer).

const DATA_PATHS: Array[String] = [
	"combat/recipes.json",
]

func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "recipes"




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
	return get_def(recipe_id)
func has_recipe(recipe_id: String) -> bool:
	return has_id(recipe_id)
func register_recipe(def: Dictionary) -> String:
	return register_def(def)
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

