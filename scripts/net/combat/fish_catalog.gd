extends "res://scripts/util/catalog_base.gd"
## World fishing-spot definitions loaded from JSON (mirror of gather_catalog).

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


func _normalize(d: Dictionary) -> Dictionary:
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
	if typeof(yv) != TYPE_ARRAY or (yv as Array).is_empty():
		return {}
	var rows: Array = yv
	var total := 0.0
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			total += maxf(float(row.get("weight", 1.0)), 0.0)
	if total <= 0.0:
		return {}
	var r := randf() * total
	var acc := 0.0
	for row2 in rows:
		if typeof(row2) != TYPE_DICTIONARY:
			continue
		acc += maxf(float(row2.get("weight", 1.0)), 0.0)
		if r <= acc:
			return {
				"item_id": str(row2.get("item_id", "")),
				"qty": maxi(int(row2.get("qty", 1)), 1),
			}
	var last: Dictionary = rows[rows.size() - 1]
	return {
		"item_id": str(last.get("item_id", "")),
		"qty": maxi(int(last.get("qty", 1)), 1),
	}

