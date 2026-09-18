extends RefCounted
## World gather-node definitions (herb/ore/etc.) loaded from JSON.

const DATA_PATHS: Array[String] = [
	"res://scripts/net/combat/data/gather_nodes.json",
	"res://data/combat/gather_nodes.json",
]

## id -> normalized def
var _by_id: Dictionary = {}
## map_id -> Array[node_id]
var _by_map: Dictionary = {}


func load_catalog() -> void:
	_by_id.clear()
	_by_map.clear()
	var raw: Variant = _load_json_first(DATA_PATHS)
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var list_v: Variant = (raw as Dictionary).get("nodes", [])
	if typeof(list_v) != TYPE_ARRAY:
		return
	for item in list_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = _normalize(item)
		var nid := str(d.get("id", ""))
		if nid.is_empty():
			continue
		_by_id[nid] = d
		var mid := str(d.get("map_id", "")).strip_edges()
		if mid.is_empty():
			mid = "*"
		if not _by_map.has(mid):
			_by_map[mid] = []
		(_by_map[mid] as Array).append(nid)


func _normalize(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var nid := str(out.get("id", "")).strip_edges()
	out["id"] = nid
	out["name"] = str(out.get("name", nid)).strip_edges()
	if out["name"].is_empty():
		out["name"] = nid
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
	out["respawn_sec"] = maxf(float(out.get("respawn_sec", 30.0)), 0.0)
	out["gather_level"] = maxi(int(out.get("gather_level", 1)), 1)
	var tool_s := str(out.get("tool", "")).strip_edges()
	if tool_s.is_empty():
		out.erase("tool")
	else:
		out["tool"] = tool_s
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


func has_node(node_id: String) -> bool:
	return _by_id.has(node_id.strip_edges())


func get_node(node_id: String) -> Dictionary:
	node_id = node_id.strip_edges()
	if _by_id.has(node_id):
		return (_by_id[node_id] as Dictionary).duplicate(true)
	return {}


func nodes_for_map(map_id: String) -> Array:
	map_id = map_id.strip_edges()
	var out: Array = []
	var seen: Dictionary = {}
	for mid in [map_id, "*"]:
		if mid.is_empty() or not _by_map.has(mid):
			continue
		for nid in _by_map[mid]:
			var id_s := str(nid)
			if seen.has(id_s):
				continue
			seen[id_s] = true
			var d: Dictionary = get_node(id_s)
			if not d.is_empty():
				out.append(d)
	return out


func list_all() -> Array:
	var out: Array = []
	for nid in _by_id.keys():
		out.append(get_node(str(nid)))
	return out


func pick_yield(node_def: Dictionary) -> Dictionary:
	## Weighted pick of one yield row. Empty if none.
	var yv: Variant = node_def.get("yields", [])
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


func _load_json_first(paths: Array[String]) -> Variant:
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return null
