extends RefCounted
## Greybox rule kit. Unit meshes retain vertex-color transitions in exported glTF.
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
const COLORS = {"grass": Color("6b9653"), "dirt": Color("b8996c"), "water": Color("518fa9"), "": Color("b5a382")}
static var _cache := {}


static func build(tile: Dictionary) -> ArrayMesh:
	var family := str(tile.family)
	var mask := int(tile.mask)
	if tile.get("options", {}).has("kit"): return Rules.Kits.build(tile)
	var key := family + ":" + str(mask) + ":" + str(tile.get("neighbors", [])) + str(tile.get("options", {})) + str(tile.get("drops", [])) + str(tile.get("cell_size", 4))
	if _cache.has(key): return _cache[key]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if family in ["road", "wall"]:
		_connections(tool, family, mask)
	elif family == "cliff":
		_cliff(tool, tile)
	elif family == "stairs":
		_stairs(tool, tile)
	elif family == "roof":
		_roof(tool, mask)
	elif family == "bridge":
		_bridge(tool, tile)
	else:
		_terrain(tool, tile)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	tool.set_material(material)
	tool.index()
	var mesh := tool.commit()
	if _cache.size() >= 128: _cache.erase(_cache.keys()[0])
	_cache[key] = mesh
	return mesh


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		tool.set_normal(normal)
		tool.set_color(color.srgb_to_linear())
		tool.add_vertex(p)


static func _cliff(tool: SurfaceTool, tile: Dictionary) -> void:
	_quad(tool, Vector3(-.5, .5, -.5), Vector3(.5, .5, -.5), Vector3(.5, .5, .5), Vector3(-.5, .5, .5), Vector3.UP, Color("719653"))
	var drops: Array = tile.get("drops", [1, 1, 1, 1])
	for side in 4:
		var depth := float(drops[side])
		if depth <= 0: continue
		var basis := Basis(Vector3.UP, -side * PI / 2)
		_quad(tool, basis * Vector3(.5, .5, -.5), basis * Vector3(-.5, .5, -.5), basis * Vector3(-.5, .5 - depth, -.5), basis * Vector3(.5, .5 - depth, -.5), basis * Vector3.FORWARD, Color("94816b"))
	_quad(tool, Vector3(-.5, -.5, .5), Vector3(.5, -.5, .5), Vector3(.5, -.5, -.5), Vector3(-.5, -.5, -.5), Vector3.DOWN, Color("796955"))


static func _stairs(tool: SurfaceTool, tile: Dictionary) -> void:
	var options := Rules.normalized_options("stairs", tile.get("options", {}))
	var count := maxi(1, ceili(float(options.rise) / 0.18))
	var basis := Basis(Vector3.UP, -int(options.direction) * PI / 2)
	# Individual treads share a fixed bottom. Rise goes from +Z toward -Z.
	for i in count:
		var height := float(i + 1) / count
		var box := BoxMesh.new()
		box.size = Vector3(1, height, 1.0 / count)
		var arrays := box.get_mesh_arrays()
		for index in arrays[Mesh.ARRAY_INDEX]:
			tool.set_normal(basis * arrays[Mesh.ARRAY_NORMAL][index])
			tool.set_color(Color("b5a58c").srgb_to_linear())
			tool.add_vertex(basis * (arrays[Mesh.ARRAY_VERTEX][index] + Vector3(0, -.5 + height / 2, .5 - (i + .5) / count)))


static func _roof(tool: SurfaceTool, mask: int) -> void:
	# Shared boundary heights are derived from the same adjacent roof cells.
	var ring: Array[Vector3] = []
	for side in 4:
		var basis := Basis(Vector3.UP, -side * PI / 2)
		var corner_high := bool(mask & (1 << (4 + (side + 3) % 4)))
		ring.append(basis * Vector3(-.5, .5 if corner_high else -.5, -.5))
		ring.append(basis * Vector3(0, .5 if mask & (1 << side) else -.5, -.5))
	for i in 8:
		var a := ring[i]
		var b := ring[(i + 1) % 8]
		var center := Vector3(0, .5, 0)
		var normal := (b - center).cross(a - center).normalized()
		for point in [center, a, b]:
			tool.set_normal(normal)
			tool.set_color(Color("ac6853").srgb_to_linear())
			tool.add_vertex(point)
	_quad(tool, Vector3(-.5, -.5, .5), Vector3(.5, -.5, .5), Vector3(.5, -.5, -.5), Vector3(-.5, -.5, -.5), Vector3.DOWN, Color("784c40"))


static func _bridge(tool: SurfaceTool, tile: Dictionary) -> void:
	var total := float(tile.get("options", {}).get("rail_height", 1)) + .2
	var deck := .2 / total
	var rail := 1.0 - deck
	var width := .08 / float(tile.get("cell_size", 4))
	_box(tool, Vector3(0, -.5 + deck / 2, 0), Vector3(1, deck, 1), Color("a58c69"))
	for side in 4:
		if int(tile.mask) & (1 << side): continue
		var basis := Basis(Vector3.UP, -side * PI / 2)
		for x in [-.47, .47]:
			_box(tool, basis * Vector3(x, -.5 + deck + rail / 2, -.47), Vector3(width, rail, width), Color("685741"))
		for y in [.35, .85]:
			var dimensions := Vector3(1, .08 / total, width) if side % 2 == 0 else Vector3(width, .08 / total, 1)
			_box(tool, basis * Vector3(0, -.5 + deck + rail * y, -.47), dimensions, Color("80694e"))


static func _box(tool: SurfaceTool, position: Vector3, dimensions: Vector3, color: Color, omit_top: bool = false) -> void:
	var box := BoxMesh.new()
	box.size = dimensions
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		if omit_top and normals[index].y > 0.5: continue
		tool.set_normal(normals[index])
		tool.set_color(color.srgb_to_linear())
		tool.add_vertex(vertices[index] + position)


static func _connections(tool: SurfaceTool, family: String, mask: int) -> void:
	var width := 0.12 if family == "wall" else 0.55
	var color := Color("a8a59c") if family == "wall" else Color("c5b397")
	_box(tool, Vector3.ZERO, Vector3(width, 1, width), color)
	for axis in 4:
		if not mask & (1 << axis): continue
		var offset: Vector2i = Rules.OFFSETS[axis]
		var length := (1.0 - width) * 0.5
		var center := Vector3(offset.x, 0, offset.y) * (width * 0.5 + length * 0.5)
		var size := Vector3(width, 1, length) if axis % 2 == 0 else Vector3(length, 1, width)
		_box(tool, center, size, color)
	if family == "wall":
		# Cap follows the exact connected arms; it never fills the open inside corner.
		_box(tool, Vector3(0, 0.48, 0), Vector3(width + 0.025, 0.04, width + 0.025), color.lightened(0.18))


static func sample_color(tile: Dictionary, point: Vector2) -> Color:
	var center: Color = COLORS.get(str(tile.family), COLORS[""])
	var neighbors: Array = tile.get("neighbors", [])
	if neighbors.size() != 8: return center
	var x_side := 1 if point.x >= 0 else 3
	var z_side := 2 if point.y >= 0 else 0
	var diagonal := (5 if point.x >= 0 else 6) if point.y >= 0 else (4 if point.x >= 0 else 7)
	var x_color: Color = COLORS.get(str(neighbors[x_side]), COLORS[""])
	var z_color: Color = COLORS.get(str(neighbors[z_side]), COLORS[""])
	var corner: Color = COLORS.get(str(neighbors[diagonal]), COLORS[""])
	# Smooth bands meet at identical colors on both sides of every cell boundary.
	var x_weight := smoothstep(0.22, 0.78, absf(point.x))
	var z_weight := smoothstep(0.22, 0.78, absf(point.y))
	var blended := center.lerp(x_color, x_weight).lerp(z_color.lerp(corner, x_weight), z_weight)
	var wet := lerpf(lerpf(1.0 if tile.family == "water" else 0.0, 1.0 if neighbors[x_side] == "water" else 0.0, x_weight), lerpf(1.0 if neighbors[z_side] == "water" else 0.0, 1.0 if neighbors[diagonal] == "water" else 0.0, x_weight), z_weight)
	# The same neighborhood field produces a sand band around outer and inner shores.
	return blended.lerp(Color("c6b88a"), pow(4.0 * wet * (1.0 - wet), 2.0) * 0.85)


static func _terrain(tool: SurfaceTool, tile: Dictionary) -> void:
	# A thin physical slab plus an 8x8 top surface resolves edges and diagonal corners.
	_box(tool, Vector3.ZERO, Vector3.ONE, Color("8d8069"), true)
	for z in 8:
		for x in 8:
			var a := Vector2(x / 8.0 - 0.5, z / 8.0 - 0.5)
			var b := a + Vector2(0.125, 0)
			var c := a + Vector2(0.125, 0.125)
			var d := a + Vector2(0, 0.125)
			for point: Vector2 in [a, b, c, a, c, d]:
				tool.set_normal(Vector3.UP)
				tool.set_color(sample_color(tile, point).srgb_to_linear())
				tool.add_vertex(Vector3(point.x, 0.5, point.y))
