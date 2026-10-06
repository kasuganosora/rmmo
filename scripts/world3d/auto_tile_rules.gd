extends RefCounted
## Persistent logical cells. Rendering and brushes share these adjacency rules.
const OFFSETS = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
const FAMILIES = ["road", "wall", "grass", "dirt", "water", "cliff", "stairs", "roof", "bridge"]
const LABELS = {"road": "道路", "wall": "墙", "grass": "草地", "dirt": "泥土", "water": "浅水 / 水岸", "cliff": "高台 / 悬崖", "stairs": "楼梯", "roof": "屋顶", "bridge": "桥 / 栏杆"}
const Kits = preload("res://scripts/world3d/auto_tile_kit.gd")


static func slot(family: String) -> String:
	return "terrain" if family in ["grass", "dirt", "water"] else family


static func cell_at(point: Vector3, cell_size: float) -> Vector2i:
	return Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))


static func key(cell: Vector2i, family: String, cell_size: float, elevation: float) -> String:
	return "%s:%.3f:%.3f:%d:%d" % [slot(family), cell_size, elevation, cell.x, cell.y]


static func attached(record: Dictionary) -> bool:
	var tile: Variant = record.get("tile3d", {})
	return tile is Dictionary and not tile.is_empty() and bool(tile.get("attached", true))


static func valid(record: Dictionary, relative: bool = false, content_root: String = "") -> bool:
	if not record.has("tile3d"): return true
	var tile: Variant = record.tile3d
	if not tile is Dictionary or tile.get("version") != 1 or tile.get("family") not in FAMILIES: return false
	var cell: Variant = tile.get("cell")
	if not cell is Array or cell.size() != 2: return false
	for coordinate in cell:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or coordinate != floorf(coordinate): return false
	for field in ["cell_size", "elevation", "mask"]:
		var number: Variant = tile.get(field)
		if not (number is int or number is float) or not is_finite(float(number)): return false
	if tile.cell_size <= 0 or tile.mask < 0 or tile.mask > 255 or tile.mask != floorf(tile.mask): return false
	var neighbors: Variant = tile.get("neighbors")
	if not neighbors is Array or neighbors.size() not in [0, 8]: return false
	for family in neighbors:
		if family != "" and family not in FAMILIES: return false
	if not options_error(tile.family, tile.elevation, tile.get("options", {}), relative, content_root).is_empty(): return false
	if tile.has("drops"):
		if not tile.drops is Array or tile.drops.size() != 4: return false
		for drop in tile.drops:
			if not (drop is float or drop is int) or not is_finite(float(drop)) or drop < 0 or drop > 1: return false
	return tile.get("attached", true) is bool


static func options_error(family: String, elevation: float, options: Variant, relative: bool = false, content_root: String = "") -> String:
	if not options is Dictionary: return "自动拼接参数必须是对象"
	for field in options:
		if field not in ["base_height", "rise", "direction", "rail_height", "kit"]: return "未知自动拼接参数：" + str(field)
	for field in ["base_height", "rise", "direction", "rail_height"]:
		if not options.has(field): continue
		var value: Variant = options[field]
		if not (value is float or value is int) or not is_finite(float(value)): return "高度和朝向必须为有限数值"
	if family == "cliff" and (elevation - float(options.get("base_height", 0.0)) < 0.1 or elevation - float(options.get("base_height", 0.0)) > 1000): return "高台表面需高于基底 0.1～1000 米"
	if options.has("base_height") and (family != "cliff" or absf(options.base_height) > 1000): return "基底高度仅适用于高台，范围 ±1000 米"
	if options.has("rise") and (family not in ["stairs", "roof"] or options.rise < 0.1 or options.rise > 8): return "楼梯 / 屋顶升高范围为 0.1～8 米"
	if options.has("direction") and (family != "stairs" or options.direction < 0 or options.direction > 3 or options.direction != floorf(options.direction)): return "楼梯上升朝向须为 0 北 / 1 东 / 2 南 / 3 西"
	if options.has("rail_height") and (family != "bridge" or options.rail_height < 0.3 or options.rail_height > 3): return "桥栏杆高度范围为 0.3～3 米"
	if options.has("kit") and (not Kits.valid(options.kit, relative, content_root) or options.kit.family != family): return "自动拼接套件无效或类型不匹配"
	return ""


static func normalized_options(family: String, options: Dictionary) -> Dictionary:
	var result := options.duplicate(true)
	match family:
		"cliff": result["base_height"] = float(options.get("base_height", 0))
		"stairs":
			result["rise"] = float(options.get("rise", 2))
			result["direction"] = int(options.get("direction", 0))
		"roof": result["rise"] = float(options.get("rise", 2))
		"bridge": result["rail_height"] = float(options.get("rail_height", 1))
	return result


static func record_key(record: Dictionary) -> String:
	var tile: Dictionary = record.tile3d
	return key(Vector2i(tile.cell[0], tile.cell[1]), str(tile.family), float(tile.cell_size), layer(tile))


static func layer(tile: Dictionary) -> float:
	return float(tile.get("options", {}).get("base_height", 0)) if tile.family == "cliff" else float(tile.elevation)


static func index_records(records: Array) -> Dictionary:
	var result := {}
	for record in records:
		if attached(record): result[record_key(record)] = record
	return result


static func configure(record: Dictionary, cell: Vector2i, family: String, cell_size: float, elevation: float, options: Dictionary = {}) -> void:
	options = normalized_options(family, options)
	var height := 2.0 if family == "wall" else (0.06 if family == "road" else 0.2)
	var y := elevation + height * 0.5 if family in ["wall", "road"] else elevation - height * 0.5
	match family:
		"cliff":
			height = elevation - float(options.base_height)
			y = elevation - height * 0.5
		"stairs", "roof":
			height = float(options.rise)
			y = elevation + height * 0.5
		"bridge":
			height = float(options.rail_height) + 0.2
			y = elevation - 0.2 + height * 0.5
	record.position = [(cell.x + 0.5) * cell_size, y, (cell.y + 0.5) * cell_size]
	record.size = [cell_size, height, cell_size]
	record.rotation = [0.0, 0.0, 0.0]
	record.surface_id = "block" if family == "wall" else ("bridge_deck" if family == "bridge" else "ground")
	record["tile3d"] = {"version": 1, "family": family, "cell": [cell.x, cell.y], "cell_size": cell_size, "elevation": elevation, "mask": 0, "neighbors": [], "attached": true}
	if not options.is_empty(): record.tile3d["options"] = options


static func refresh(index: Dictionary, record: Dictionary, surfaces: Variant = null) -> bool:
	var tile: Dictionary = record.tile3d
	var cell := Vector2i(tile.cell[0], tile.cell[1])
	var mask := 0
	var neighbors: Array = []
	var drops: Array = []
	for i in OFFSETS.size():
		var other: Dictionary = index.get(key(cell + OFFSETS[i], str(tile.family), float(tile.cell_size), layer(tile)), {})
		# Bridge exits connect to the walking surface of roads, plateaus and stair landings.
		if tile.family in ["bridge", "road"] and i < 4 and other.is_empty(): other = landing(index, cell + OFFSETS[i], tile, i, surfaces)
		var family := str(other.get("tile3d", {}).get("family", ""))
		neighbors.append(family)
		var joins: bool = family == tile.family or (tile.family in ["bridge", "road"] and not family.is_empty())
		if tile.family == "roof" and not other.is_empty(): joins = joins and is_equal_approx(float(other.tile3d.get("options", {}).get("rise", 2)), float(tile.get("options", {}).get("rise", 2)))
		if joins: mask |= 1 << i
		if tile.family == "cliff" and i < 4:
			var base := layer(tile)
			var bottom := clampf(float(other.get("tile3d", {}).get("elevation", base)), base, float(tile.elevation))
			drops.append((float(tile.elevation) - bottom) / (float(tile.elevation) - base))
	# A diagonal only joins terrain when both side neighbors join as well.
	for i in 4:
		if not (mask & (1 << i) and mask & (1 << ((i + 1) % 4))): mask &= ~(1 << (i + 4))
	var changed: bool = tile.mask != mask or tile.neighbors != neighbors or (tile.family == "cliff" and tile.get("drops", []) != drops)
	tile.mask = mask
	tile.neighbors = neighbors
	if tile.family == "cliff": tile["drops"] = drops
	return changed


static func landing_index(index: Dictionary) -> Dictionary:
	var result := {}
	for record: Dictionary in index.values():
		var tile: Dictionary = record.tile3d
		if tile.family not in ["cliff", "stairs"]: continue
		var key_ := key(Vector2i(tile.cell[0], tile.cell[1]), "landing", float(tile.cell_size), 0)
		if not result.has(key_): result[key_] = []
		result[key_].append(record)
	return result


static func landing(index: Dictionary, cell: Vector2i, tile: Dictionary, side: int, surfaces: Variant = null) -> Dictionary:
	var height := float(tile.elevation)
	var size_ := float(tile.cell_size)
	var road: Dictionary = index.get(key(cell, "road", size_, height), {})
	if not road.is_empty(): return road
	var bridge: Dictionary = index.get(key(cell, "bridge", size_, height), {})
	if not bridge.is_empty(): return bridge
	# Spatially indexed landings avoid scanning the whole map for every bridge edge.
	if surfaces == null: surfaces = landing_index(index)
	for other: Dictionary in surfaces.get(key(cell, "landing", size_, 0), []):
		var t: Dictionary = other.tile3d
		if float(t.cell_size) != size_ or t.cell != [cell.x, cell.y]: continue
		if t.family == "cliff" and is_equal_approx(float(t.elevation), height): return other
		if t.family == "stairs":
			var options := normalized_options("stairs", t.get("options", {}))
			var facing := int(options.direction)
			if facing == (side + 2) % 4 and is_equal_approx(float(t.elevation) + float(options.rise), height): return other
			if facing == side and is_equal_approx(float(t.elevation), height): return other
	return {}


static func refresh_all(records: Array) -> Array[String]:
	var index := index_records(records)
	var surfaces := landing_index(index)
	var changed: Array[String] = []
	for record in index.values():
		if refresh(index, record, surfaces): changed.append(str(record.uuid))
	return changed


static func detach(record: Dictionary) -> void:
	if record.has("tile3d"): record.tile3d.attached = false


static func shape_name(mask: int) -> String:
	var count := 0
	for i in 4:
		if mask & (1 << i): count += 1
	match count:
		0: return "独立"
		1: return "端头"
		2: return "直线" if (mask & 15) in [5, 10] else "转角"
		3: return "T 形"
	return "十字"
