extends "res://scripts/util/catalog_base.gd"
## World fishing-spot definitions loaded from JSON (mirror of gather_catalog).

const RngUtil = preload("res://scripts/util/rng_util.gd")

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/fish_spots.json",
	"res://data/combat/fish_spots.json",
]

func _data_paths() -> Array:
	return DATA_PATHS


func _list_key() -> String:
	return "spots"


## map_id -> Array[spot_id]
var _by_map: Dictionary = {}


func _after_load() -> void:
	_index_by_field("map_id", _by_map, "*")


func _normalize_def(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var sid := str(out.get("id", "")).strip_edges()
	out["id"] = sid
	out["name"] = str(out.get("name", sid)).strip_edges()
	if out["name"].is_empty():
		out["name"] = sid
	out["map_id"] = str(out.get("map_id", "")).strip_edges()
	var cell_v: Variant = out.get("cell", {})
	var cx := 0
	var cy := 0
	if typeof(cell_v) == TYPE_DICTIONARY:
		cx = int(cell_v.get("x", 0))
		cy = int(cell_v.get("y", 0))
	elif typeof(cell_v) == TYPE_VECTOR2I:
		cx = cell_v.x
		cy = cell_v.y
	out["cell"] = {"x": cx, "y": cy}
	out["respawn_sec"] = maxf(float(out.get("respawn_sec", 20.0)), 0.0)
	out["cast_sec"] = maxf(float(out.get("cast_sec", 0.0)), 0.0)
	out["gather_level"] = maxi(int(out.get("gather_level", 1)), 1)
	var yields_out: Array = []
	var yv: Variant = out.get("yields", [])
	if typeof(yv) == TYPE_ARRAY:
		for row in yv:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var iid := str(row.get("item_id", row.get("id", ""))).strip_edges()
			var qty: int = maxi(int(row.get("qty", 1)), 1)
			var w: float = maxf(float(row.get("weight", 1.0)), 0.0)
			if iid.is_empty() or w <= 0.0:
				continue
			yields_out.append({"item_id": iid, "qty": qty, "weight": w})
	out["yields"] = yields_out
	return out


func has_spot(spot_id: String) -> bool:
	return has_id(spot_id)
func get_spot(spot_id: String) -> Dictionary:
	return get_def(spot_id)
func spots_for_map(map_id: String) -> Array:
	map_id = map_id.strip_edges()
	var out: Array = []
	var seen: Dictionary = {}
	for mid in [map_id, "*"]:
		if mid.is_empty() or not _by_map.has(mid):
			continue
		for sid in _by_map[mid]:
			var id_s := str(sid)
			if seen.has(id_s):
				continue
			seen[id_s] = true
			var d: Dictionary = get_spot(id_s)
			if not d.is_empty():
				out.append(d)
	return out


func pick_yield(spot_def: Dictionary) -> Dictionary:
	## Weighted pick of one yield row. Empty if none.
	var yv: Variant = spot_def.get("yields", [])
	if typeof(yv) != TYPE_ARRAY:
		return {}
	var picked: Dictionary = RngUtil.weighted_pick(yv)
	if picked.is_empty():
		return {}
	return {
		"item_id": str(picked.get("item_id", "")),
		"qty": maxi(int(picked.get("qty", 1)), 1),
	}

