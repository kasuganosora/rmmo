extends RefCounted
## Check fixture copied from the 2D Axel town. Not a shipped map.
## Houses are cubes. Walls, gates, and roads follow the painted cells.

const N := 256
const CHUNK := 32
const TOWN_DIR := "D:/code/rmmo_runtime/style_work/town_m"
const PACK_DIR := "user://content/packs/default"
const SPAWN_CELL := Vector2i(112, 119)

const GRASS := [0.34, 0.45, 0.26]
const ROAD := [0.64, 0.58, 0.48]
const BRIDGE := [0.50, 0.39, 0.28]
const WALL := [0.56, 0.54, 0.50]
const HOUSE := [0.93, 0.93, 0.91]
const STALL := [0.88, 0.84, 0.74]
const PROP := [0.72, 0.72, 0.70]
const WATER := [0.16, 0.36, 0.50]
const LAMP := [0.22, 0.21, 0.20]


static func build() -> Dictionary:
	var bits := _load_bits()
	if bits.is_empty():
		return {"ok": false, "error": "town masks did not load"}
	var plan_text := FileAccess.get_file_as_string(TOWN_DIR.path_join("plan.json"))
	var upgrade_text := FileAccess.get_file_as_string(TOWN_DIR.path_join("scene_upgrade.json"))
	var plan: Variant = JSON.parse_string(plan_text)
	var upgrade: Variant = JSON.parse_string(upgrade_text)
	if typeof(plan) != TYPE_DICTIONARY or typeof(upgrade) != TYPE_DICTIONARY:
		return {"ok": false, "error": "town plan json did not parse"}
	var pack = load("res://scripts/map/tilemap_pack.gd").load_pack(PACK_DIR, "Axel256")
	if pack == null or pack.collision == null:
		return {"ok": false, "error": "Axel256 collision did not load"}
	var land := PackedByteArray()
	land.resize(N * N)
	var col = pack.collision
	for y in N:
		for x in N:
			land[y * N + x] = 1 if col.is_landable(x, y) else 0
	var doc = load("res://scripts/world3d/world_document.gd").new()
	var filled: Dictionary = _fill(doc, bits, plan, upgrade, land)
	var counts: Dictionary = filled["counts"]
	var goals: Dictionary = filled["goals"]
	var spawn := _spawn_meters(land)
	var lamps: Array = counts["lamps"]
	doc.map_meta = {
		"rmmo_role": "check",
		"map_name": "阿克塞尔白模",
		"spawn": [spawn.x, spawn.y, spawn.z],
		"lamps": lamps,
	}
	counts.erase("lamps")
	return {"ok": true, "doc": doc, "land": land, "spawn": spawn, "counts": counts, "goals": goals}


static func _load_bits() -> PackedByteArray:
	var script_path := "C:/Users/luna/AppData/Local/Temp/axel_whitebox_masks.py"
	var bits_path := "C:/Users/luna/AppData/Local/Temp/axel_whitebox_bits.bin"
	var code := "import numpy as np\nfrom pathlib import Path\nroot = Path(r'%s')\nz = np.load(root / 'masks.npz')\nb = np.zeros(256 * 256, np.uint8)\nwater = np.asarray(z['water']).reshape(-1)\nwall = np.asarray(z['wall']).reshape(-1)\nbridge = np.asarray(z['bridge']).reshape(-1)\nb[water] = 1\nb[wall] += 2\nb[bridge] += 4\nPath(r'%s').write_bytes(b.tobytes())\n" % [TOWN_DIR, bits_path]
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return PackedByteArray()
	file.store_string(code)
	file.close()
	var output: Array = []
	var code_err: int = OS.execute("python", [script_path], output, true, false)
	if code_err != 0:
		push_error("town mask export failed: %s" % str(output))
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(bits_path)
	if bytes.size() != N * N:
		return PackedByteArray()
	return bytes


static func _fill(doc, bits: PackedByteArray, plan: Dictionary, upgrade: Dictionary, land: PackedByteArray) -> Dictionary:
	var house := PackedByteArray()
	var bastion := PackedByteArray()
	var stall := PackedByteArray()
	var gate := PackedByteArray()
	house.resize(N * N)
	bastion.resize(N * N)
	stall.resize(N * N)
	gate.resize(N * N)
	var buildings: Array = plan.get("buildings", [])
	for item in buildings:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := str(item.get("kind", ""))
		var mask := house
		if kind == "wall":
			mask = bastion
		elif kind == "stall":
			mask = stall
		elif kind == "gate":
			mask = gate
		elif kind != "building":
			continue
		_stamp(mask, int(item.get("x", 0)), int(item.get("y", 0)), int(item.get("w", 0)), int(item.get("h", 0)))
	var road := PackedByteArray()
	var drive := PackedByteArray()
	var bridge_pass := PackedByteArray()
	var lamp := PackedByteArray()
	road.resize(N * N)
	drive.resize(N * N)
	bridge_pass.resize(N * N)
	lamp.resize(N * N)
	for cell in plan.get("roads", []):
		if typeof(cell) == TYPE_DICTIONARY:
			_mark(road, int(cell.get("x", -1)), int(cell.get("y", -1)))
	for cell in plan.get("driveways", []):
		_mark_pair(drive, cell)
	for cell in plan.get("bridge_pass", []):
		_mark_pair(bridge_pass, cell)
	for cell in upgrade.get("lamp_feet", []):
		_mark_pair(lamp, cell)
	var ground := PackedByteArray()
	var road_vis := PackedByteArray()
	var bridge_vis := PackedByteArray()
	var water := PackedByteArray()
	var wall := PackedByteArray()
	var gate_wall := PackedByteArray()
	var stall_block := PackedByteArray()
	var prop := PackedByteArray()
	ground.resize(N * N)
	road_vis.resize(N * N)
	bridge_vis.resize(N * N)
	water.resize(N * N)
	wall.resize(N * N)
	gate_wall.resize(N * N)
	stall_block.resize(N * N)
	prop.resize(N * N)
	var gate_min := Vector2i(999, 999)
	var gate_max := Vector2i(-1, -1)
	for y in N:
		var row := y * N
		for x in N:
			var i := row + x
			var landable := land[i] != 0
			var water_bit := (bits[i] & 1) != 0
			var wall_bit := (bits[i] & 2) != 0
			if landable:
				ground[i] = 1
				if bridge_pass[i] != 0 or (bits[i] & 4) != 0:
					bridge_vis[i] = 1
				elif road[i] != 0 or drive[i] != 0:
					road_vis[i] = 1
				if gate[i] != 0:
					gate_min.x = mini(gate_min.x, x)
					gate_min.y = mini(gate_min.y, y)
					gate_max.x = maxi(gate_max.x, x)
					gate_max.y = maxi(gate_max.y, y)
				continue
			if house[i] != 0 or bastion[i] != 0 or lamp[i] != 0:
				continue
			if stall[i] != 0:
				stall_block[i] = 1
				continue
			if water_bit:
				water[i] = 1
				continue
			if gate[i] != 0:
				gate_wall[i] = 1
				continue
			if wall_bit:
				wall[i] = 1
				continue
			prop[i] = 1
	var counts := {}
	counts["ground"] = _merge(doc, ground, "ground", GRASS, 0.2, -0.1, "", "ground", false, 0.0)
	counts["road"] = _merge(doc, road_vis, "ground", ROAD, 0.03, 0.02, "none", "road", false, 0.0)
	counts["bridge"] = _merge(doc, bridge_vis, "ground", BRIDGE, 0.04, 0.025, "none", "bridge", false, 0.0)
	counts["water"] = _merge(doc, water, "ground", WATER, 0.16, -0.42, "none", "water", false, 0.0)
	counts["water_block"] = _merge(doc, water, "block", WATER, 1.15, 0.52, "", "water", true, 0.0)
	counts["wall"] = _merge(doc, wall, "block", WALL, 3.8, 1.9, "", "wall", false, 0.015)
	counts["gate"] = _merge(doc, gate_wall, "block", WALL, 5.2, 2.6, "", "gate", false, 0.015)
	counts["prop"] = _merge(doc, prop, "block", PROP, 2.2, 1.1, "", "prop", false, 0.015)
	counts["stall"] = _merge(doc, stall_block, "block", STALL, 1.15, 0.575, "", "stall", false, 0.02)
	counts["house"] = _footprints(doc, buildings, "building", HOUSE)
	counts["bastion"] = _footprints(doc, buildings, "wall", WALL)
	counts["lamp"] = _lamps(doc, lamp)
	if gate_max.x >= gate_min.x:
		_cover(doc, gate_min.x, gate_min.y, gate_max.x - gate_min.x + 1, gate_max.y - gate_min.y + 1, 1.3, 3.35, WALL, "lintel", false, 0.02)
		counts["lintel"] = 1
	else:
		counts["lintel"] = 0
	var flat: Array = []
	for y in N:
		for x in N:
			if lamp[y * N + x] == 0:
				continue
			flat.append(x + 0.5)
			flat.append(2.85)
			flat.append(y + 0.5)
	counts["lamps"] = flat
	return {"counts": counts, "goals": _goals(land, gate, bridge_pass, water, wall, house)}


static func _footprints(doc, buildings: Array, kind: String, color: Array) -> int:
	var n := 0
	for item in buildings:
		if typeof(item) != TYPE_DICTIONARY or str(item.get("kind", "")) != kind:
			continue
		var x := int(item.get("x", 0))
		var y := int(item.get("y", 0))
		var w := int(item.get("w", 0))
		var h := int(item.get("h", 0))
		if w <= 0 or h <= 0:
			continue
		var height := 6.8 if kind == "wall" else _house_height(w, h)
		_cover(doc, x, y, w, h, height, height * 0.5, color, kind, false, 0.02)
		n += 1
	return n


static func _house_height(w: int, h: int) -> float:
	var area := w * h
	if area >= 90:
		return 7.2
	if area >= 48:
		return 5.2
	if area >= 24:
		return 4.0
	return 3.2


static func _lamps(doc, lamp: PackedByteArray) -> int:
	var n := 0
	for y in N:
		for x in N:
			if lamp[y * N + x] == 0:
				continue
			_solid(doc, x + 0.04, y + 0.04, 0.92, 0.92, 2.6, 1.3, LAMP, "lamp", false)
			n += 1
	return n


static func _cover(doc, x: int, y: int, w: int, h: int, height: float, center_y: float, color: Array, kind: String, invisible: bool, inset: float) -> void:
	var x_end := x + w
	var y_end := y + h
	var cx := x
	while cx < x_end:
		var nx: int = mini(x_end, (int(cx / CHUNK) + 1) * CHUNK)
		var cy := y
		while cy < y_end:
			var ny: int = mini(y_end, (int(cy / CHUNK) + 1) * CHUNK)
			_solid(doc, cx + inset, cy + inset, float(nx - cx) - inset * 2.0, float(ny - cy) - inset * 2.0, height, center_y, color, kind, invisible)
			cy = ny
		cx = nx


static func _solid(doc, x: float, z: float, w: float, d: float, height: float, center_y: float, color: Array, kind: String, invisible: bool) -> void:
	if w <= 0.05 or d <= 0.05:
		return
	doc.add_box_silent("block", Vector3(x + w * 0.5, center_y, z + d * 0.5), Vector3(w, height, d))
	_paint(doc, color, "", kind, invisible)


static func _merge(doc, mask: PackedByteArray, surface: String, color: Array, height: float, center_y: float, collision: String, kind: String, invisible: bool, inset: float) -> int:
	var n := 0
	for cy in range(0, N, CHUNK):
		for cx in range(0, N, CHUNK):
			var used := PackedByteArray()
			used.resize(CHUNK * CHUNK)
			for ly in CHUNK:
				var y := cy + ly
				var lx := 0
				while lx < CHUNK:
					var x := cx + lx
					if mask[y * N + x] == 0 or used[ly * CHUNK + lx] != 0:
						lx += 1
						continue
					var w := 1
					while lx + w < CHUNK and mask[y * N + x + w] != 0 and used[ly * CHUNK + lx + w] == 0:
						w += 1
					var h := 1
					while ly + h < CHUNK:
						var row_ok := true
						for i in w:
							if mask[(y + h) * N + x + i] == 0 or used[(ly + h) * CHUNK + lx + i] != 0:
								row_ok = false
								break
						if not row_ok:
							break
						h += 1
					for iy in h:
						for ix in w:
							used[(ly + iy) * CHUNK + lx + ix] = 1
					var span_w := float(w) - inset * 2.0
					var span_d := float(h) - inset * 2.0
					if span_w > 0.05 and span_d > 0.05:
						doc.add_box_silent(surface, Vector3(x + inset + span_w * 0.5, center_y, y + inset + span_d * 0.5), Vector3(span_w, height, span_d))
						_paint(doc, color, collision, kind, invisible)
						n += 1
					lx += w
	return n


static func _paint(doc, color: Array, collision: String, kind: String, invisible: bool) -> void:
	var rec: Dictionary = doc.records[doc.records.size() - 1]
	rec["color"] = color
	if collision != "":
		rec["collision"] = collision
	if kind != "":
		rec["kind"] = kind
	if invisible:
		rec["invisible"] = true


static func _stamp(mask: PackedByteArray, x: int, y: int, w: int, h: int) -> void:
	for yy in range(y, y + h):
		if yy < 0 or yy >= N:
			continue
		for xx in range(x, x + w):
			if xx < 0 or xx >= N:
				continue
			mask[yy * N + xx] = 1


static func _mark(mask: PackedByteArray, x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= N or y >= N:
		return
	mask[y * N + x] = 1


static func _mark_pair(mask: PackedByteArray, cell) -> void:
	if typeof(cell) != TYPE_ARRAY or (cell as Array).size() < 2:
		return
	var pair: Array = cell
	_mark(mask, int(pair[0]), int(pair[1]))


static func _goals(land: PackedByteArray, gate: PackedByteArray, bridge_pass: PackedByteArray, water: PackedByteArray, wall: PackedByteArray, house: PackedByteArray) -> Dictionary:
	return {
		"gate": _seek(land, gate, Vector2i(103, 245)),
		"bridge": _seek(land, bridge_pass, Vector2i(140, 60)),
		"church": _nearest_land(land, Vector2i(202, 84), 4),
		"house": _nearest_blocked(house, Vector2i(112, 114)),
		"wall": _blocked_with_neighbor(land, wall),
		"water": _blocked_with_neighbor(land, water),
	}


static func _seek(land: PackedByteArray, mask: PackedByteArray, prefer: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1000000
	for y in N:
		for x in N:
			if mask[y * N + x] == 0 or land[y * N + x] == 0:
				continue
			var d := absi(x - prefer.x) + absi(y - prefer.y)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


static func _nearest_land(land: PackedByteArray, prefer: Vector2i, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1000000
	for y in range(prefer.y - radius, prefer.y + radius + 1):
		for x in range(prefer.x - radius, prefer.x + radius + 1):
			if x < 0 or y < 0 or x >= N or y >= N or land[y * N + x] == 0:
				continue
			var d := absi(x - prefer.x) + absi(y - prefer.y)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


static func _nearest_blocked(mask: PackedByteArray, prefer: Vector2i) -> Vector2i:
	if prefer.x >= 0 and prefer.y >= 0 and prefer.x < N and prefer.y < N and mask[prefer.y * N + prefer.x] != 0:
		return prefer
	return _seek_any(mask)


static func _seek_any(mask: PackedByteArray) -> Vector2i:
	for y in N:
		for x in N:
			if mask[y * N + x] != 0:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _blocked_with_neighbor(land: PackedByteArray, mask: PackedByteArray) -> Vector2i:
	for y in N:
		for x in N:
			if mask[y * N + x] == 0:
				continue
			if _open_neighbor(land, x, y) != Vector2i(-1, -1):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _open_neighbor(land: PackedByteArray, x: int, y: int) -> Vector2i:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + int(step.x)
		var ny: int = y + int(step.y)
		if nx < 0 or ny < 0 or nx >= N or ny >= N:
			continue
		if land[ny * N + nx] != 0:
			return Vector2i(nx, ny)
	return Vector2i(-1, -1)


static func _spawn_meters(land: PackedByteArray) -> Vector3:
	var cell := SPAWN_CELL
	if land[cell.y * N + cell.x] == 0:
		var found := false
		for radius in range(1, 6):
			for y in range(cell.y - radius, cell.y + radius + 1):
				for x in range(cell.x - radius, cell.x + radius + 1):
					if x < 0 or y < 0 or x >= N or y >= N:
						continue
					if land[y * N + x] != 0:
						cell = Vector2i(x, y)
						found = true
						break
				if found:
					break
			if found:
				break
	return Vector3(cell.x + 0.5, 0.95, cell.y + 0.5)
