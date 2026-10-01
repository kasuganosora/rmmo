extends RefCounted
## External-id catalog for objects the editor can place. Search does not load meshes.

const CATALOG := [
	{"id": "ground_4", "label": "地面", "category": "地面", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "rotation": Vector3.ZERO, "paint": true},
	{"id": "road_4", "label": "道路（自动）", "category": "地面 自动拼接", "surface_id": "ground", "size": Vector3(4, 0.06, 4), "rotation": Vector3.ZERO, "paint": true, "auto_family": "road"},
	{"id": "wall_4", "label": "墙（自动）", "category": "墙 自动拼接", "surface_id": "block", "size": Vector3(4, 2, 4), "rotation": Vector3.ZERO, "paint": true, "auto_family": "wall"},
	{"id": "bridge_4", "label": "桥面", "category": "桥", "surface_id": "bridge_deck", "size": Vector3(4, 0.2, 4), "rotation": Vector3.ZERO, "paint": false},
	{"id": "ramp_4", "label": "坡道", "category": "桥", "surface_id": "ramp", "size": Vector3(4, 0.25, 4), "rotation": Vector3(-31, 0, 0), "paint": false},
	{"id": "grass_auto", "label": "草地（自动）", "category": "地形 自动过渡", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "auto_family": "grass", "paint": true},
	{"id": "dirt_auto", "label": "泥土（自动）", "category": "地形 自动过渡", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "auto_family": "dirt", "paint": true},
	{"id": "water_auto", "label": "浅水 / 水岸（自动）", "category": "地形 自动过渡", "surface_id": "ground", "size": Vector3(4, 0.2, 4), "auto_family": "water", "paint": true},
	{"id": "cliff_auto", "label": "高台 / 悬崖（自动）", "category": "高差 地形 自动拼接", "surface_id": "ground", "size": Vector3(4, 2, 4), "auto_family": "cliff", "paint": true},
	{"id": "stairs_auto", "label": "楼梯（自动）", "category": "高差 楼梯 自动拼接", "surface_id": "ground", "size": Vector3(4, 2, 4), "auto_family": "stairs", "paint": true},
	{"id": "roof_auto", "label": "屋顶（自动）", "category": "建筑 屋顶 自动拼接", "surface_id": "ground", "size": Vector3(4, 2, 4), "auto_family": "roof", "paint": true},
	{"id": "bridge_auto", "label": "桥 / 栏杆（自动）", "category": "桥 高差 栏杆 自动拼接", "surface_id": "bridge_deck", "size": Vector3(4, 1.2, 4), "auto_family": "bridge", "paint": true},
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
