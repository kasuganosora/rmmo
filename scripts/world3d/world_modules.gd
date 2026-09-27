extends RefCounted
## External-id catalog for objects the editor can place. Search does not load meshes.

const CATALOG := [
	{"id": "ground_4", "label": "地面", "category": "地面", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "rotation": Vector3.ZERO, "paint": true},
	{"id": "road_4", "label": "道路", "category": "地面", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "rotation": Vector3.ZERO, "paint": true},
	{"id": "wall_4", "label": "墙", "category": "墙", "surface_id": "block", "size": Vector3(0.4, 2, 4), "rotation": Vector3.ZERO, "paint": false},
	{"id": "bridge_4", "label": "桥面", "category": "桥", "surface_id": "bridge_deck", "size": Vector3(4, 0.2, 4), "rotation": Vector3.ZERO, "paint": false},
	{"id": "ramp_4", "label": "坡道", "category": "桥", "surface_id": "ramp", "size": Vector3(4, 0.25, 4), "rotation": Vector3(-31, 0, 0), "paint": false},
]


static func all() -> Array:
	return CATALOG


static func search(query: String) -> Array:
	var needle := query.strip_edges().to_lower()
	var found := []
	for item in CATALOG:
		if needle == "":
			found.append(item)
			continue
		var label := str(item.get("label", "")).to_lower()
		var category := str(item.get("category", "")).to_lower()
		var id := str(item.get("id", "")).to_lower()
		if label.contains(needle) or category.contains(needle) or id.contains(needle):
			found.append(item)
	return found


static func get_module(module_id: String) -> Dictionary:
	for item in CATALOG:
		if str(item.get("id", "")) == module_id:
			return item
	return {}
