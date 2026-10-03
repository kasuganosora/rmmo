extends RefCounted
## City view loads 32 m chunks around the player. The document keeps every record.

const Location = preload("res://scripts/world3d/world_location.gd")
const CHUNK_M := 32.0
const RENDER_RADIUS := 1
const COLLISION_RADIUS := 2
## Gameplay spreads a chunk swap across frames. Tests pass 0 and finish in one call.
const FRAME_BUDGET := 12
const GroundBatcher = preload("res://scripts/world3d/ground_batcher.gd")
const CpuMesh = preload("res://scripts/world3d/ground_cpu_mesh.gd")


static func chunk_key(position: Vector3) -> Vector2i:
	return Vector2i(
		Location.chunk_index(position.x, 0.0, CHUNK_M),
		Location.chunk_index(position.z, 0.0, CHUNK_M)
	)


static func ring(origin: Vector3, radius: int) -> Dictionary:
	var center := chunk_key(origin)
	var keys := {}
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			keys[Vector2i(center.x + dx, center.y + dz)] = true
	return keys


static func sync(map_root: Node, host: Node, origin: Vector3, budget: int = 0) -> void:
	var library: Array = _library(map_root)
	var known := _dict(map_root, &"stream_known")
	var meshes := _dict(map_root, &"stream_meshes")
	var bodies := _dict(map_root, &"stream_bodies")
	var jobs := _jobs(map_root)
	var target := chunk_key(origin)
	var child_count := map_root.get_child_count()
	if jobs.is_empty() and _chunk_is(map_root, &"stream_chunk", target) and _child_count_is(map_root, child_count):
		return
	if not _child_count_is(map_root, child_count):
		_adopt(map_root, library, known)
		child_count = map_root.get_child_count()
		map_root.remove_meta(&"stream_target")
	if not _chunk_is(map_root, &"stream_target", target):
		map_root.set_meta(&"stream_target", target)
		map_root.remove_meta(&"stream_chunk")
		jobs.clear()
		map_root.set_meta(&"stream_candidates", _candidates(map_root, target, meshes, bodies))
		map_root.set_meta(&"stream_plan_cursor", 0)
		map_root.set_meta(&"stream_plan_bins", [[], [], [], [], []])
		map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_children", map_root.get_child_count())
	map_root.set_meta(&"stream_library", library)
	if not _plan_jobs(map_root, jobs, meshes, bodies, target, budget):
		return
	var cursor := int(map_root.get_meta(&"stream_cursor", 0))
	var left := 1000000 if budget <= 0 else budget
	var draw := _ring_at(target, RENDER_RADIUS)
	var solid := _ring_at(target, COLLISION_RADIUS)
	var apply_started := Time.get_ticks_usec()
	while left > 0 and cursor < jobs.size():
		_apply(map_root, host, jobs[cursor], draw, solid, meshes, bodies)
		cursor += 1
		left -= 1
		if budget > 0 and Time.get_ticks_usec() - apply_started >= 3000:
			break
	map_root.set_meta(&"stream_cursor", cursor)
	var batcher: Node3D = map_root.get_node_or_null("GroundRenderBatches")
	if batcher == null:
		batcher = GroundBatcher.new(); batcher.name = "GroundRenderBatches"; batcher.set_meta("stream_instance",true); map_root.add_child(batcher)
	batcher.sync(meshes.values())
	if budget <= 0: batcher.flush()
	map_root.set_meta(&"stream_library", library)
	map_root.set_meta(&"stream_children", map_root.get_child_count())
	if cursor < jobs.size():
		return
	jobs.clear()
	map_root.set_meta(&"stream_cursor", 0)
	map_root.set_meta(&"stream_chunk", target)


static func _library(map_root: Node) -> Array:
	var existing: Variant = map_root.get_meta(&"stream_library", [])
	if existing is Array:
		return existing
	var created: Array = []
	map_root.set_meta(&"stream_library", created)
	return created


static func _dict(node: Node, key: StringName) -> Dictionary:
	if node.has_meta(key):
		var existing: Variant = node.get_meta(key)
		if existing is Dictionary:
			return existing
	var created := {}
	node.set_meta(key, created)
	return created


static func _live(bag: Dictionary, uuid: String):
	var node: Variant = bag.get(uuid, null)
	if node == null or not is_instance_valid(node):
		bag.erase(uuid)
		return null
	return node


static func _jobs(node: Node) -> Array:
	if node.has_meta(&"stream_jobs"):
		var existing: Variant = node.get_meta(&"stream_jobs")
		if existing is Array:
			return existing
	var created: Array = []
	node.set_meta(&"stream_jobs", created)
	return created


static func _chunk_is(node: Node, key: StringName, chunk: Vector2i) -> bool:
	if not node.has_meta(key):
		return false
	var value: Variant = node.get_meta(key)
	return value is Vector2i and (value as Vector2i) == chunk


static func _child_count_is(node: Node, count: int) -> bool:
	return node.has_meta(&"stream_children") and int(node.get_meta(&"stream_children")) == count


static func _adopt(map_root: Node, library: Array, known: Dictionary) -> void:
	preload("res://scripts/world3d/scene_integrity.gd").prepare(map_root)
	var incoming: Array = []
	_collect_meshes(map_root, incoming)
	for mesh in incoming:
		var spec := _spec(mesh as MeshInstance3D)
		var world_transform: Transform3D = mesh.global_transform
		spec["transform"] = world_transform
		spec["position"] = world_transform.origin
		var bounds: AABB = world_transform * mesh.get_aabb()
		spec["chunk"] = chunk_key(world_transform.origin)
		spec["chunk_min"] = chunk_key(bounds.position)
		spec["chunk_max"] = chunk_key(bounds.end)
		preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
		var metadata: Dictionary = spec["extras"]
		spec["uuid"] = str(metadata.get("uuid", str(map_root.get_path_to(mesh)).replace("/", "__")))
		var adopted := str(spec.get("uuid", ""))
		library.append(spec)
		known[adopted] = true
		_dict(map_root, &"stream_by_id")[adopted] = spec
		var index := _dict(map_root, &"stream_index")
		var low: Vector2i = spec["chunk_min"]
		var high: Vector2i = spec["chunk_max"]
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var key := Vector2i(x, z)
				if not index.has(key):
					index[key] = []
				index[key].append(adopted)
	# Children must be removed before their mesh parents.
	incoming.reverse()
	for mesh in incoming:
		if mesh.has_meta("native_visual"):
			mesh.set_meta("stream_instance", true)
			preload("res://scripts/world3d/wind_response.gd").register(mesh)
			continue
		mesh.get_parent().remove_child(mesh)
		(mesh as Node).free()


static func _collect_meshes(node: Node, result: Array) -> void:
	for child in node.get_children():
		if child.has_meta("stream_instance"):
			continue
		if child is MeshInstance3D:
			result.append(child)
		_collect_meshes(child, result)


static func _candidates(map_root: Node, target: Vector2i, meshes: Dictionary, bodies: Dictionary) -> Array:
	var index := _dict(map_root, &"stream_index")
	var by_id := _dict(map_root, &"stream_by_id")
	var selected := {}
	for key in meshes:
		selected[key] = by_id[key]
	for key in bodies:
		selected[key] = by_id[key]
	for z in range(target.y - COLLISION_RADIUS, target.y + COLLISION_RADIUS + 1):
		for x in range(target.x - COLLISION_RADIUS, target.x + COLLISION_RADIUS + 1):
			for key in index.get(Vector2i(x, z), []):
				selected[key] = by_id[key]
	return selected.values()


static func _plan_jobs(map_root: Node, jobs: Array, meshes: Dictionary, bodies: Dictionary, target: Vector2i, budget: int) -> bool:
	if not map_root.has_meta(&"stream_candidates"):
		return true
	var candidates: Array = map_root.get_meta(&"stream_candidates")
	var cursor := int(map_root.get_meta(&"stream_plan_cursor", 0))
	var bins: Array = map_root.get_meta(&"stream_plan_bins")
	var draw := _ring_at(target, RENDER_RADIUS)
	var solid := _ring_at(target, COLLISION_RADIUS)
	var started := Time.get_ticks_usec()
	while cursor < candidates.size():
		var item: Dictionary = candidates[cursor]
		cursor += 1
		if _needs_work(item, draw, solid, meshes, bodies):
			var bin := 4
			if _overlaps(item, solid):
				var key: Vector2i = item["chunk"]
				bin = mini(maxi(absi(key.x - target.x), absi(key.y - target.y)), 3)
			bins[bin].append(item)
		if budget > 0 and Time.get_ticks_usec() - started >= 2000:
			map_root.set_meta(&"stream_plan_cursor", cursor)
			return false
	for bin in bins:
		jobs.append_array(bin)
	map_root.remove_meta(&"stream_candidates")
	map_root.remove_meta(&"stream_plan_bins")
	return true


static func _needs_work(spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary) -> bool:
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var has_mesh := _live(meshes, uuid) != null
	var has_body := _live(bodies, uuid) != null
	if not _overlaps(spec, solid):
		return has_mesh or has_body
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	if not bool(spec.get("native_visual", false)) and _overlaps(spec, draw) != has_mesh:
		return true
	if collides != has_body:
		return true
	return false


static func _apply(map_root: Node, host: Node, spec: Dictionary, draw: Dictionary, solid: Dictionary, meshes: Dictionary, bodies: Dictionary) -> void:
	var key: Vector2i = spec["chunk"]
	var uuid := str(spec["uuid"])
	var inst = _live(meshes, uuid) as MeshInstance3D
	var body = _live(bodies, uuid) as StaticBody3D
	var collides := str(spec.get("extras", {}).get("rmmo_collision", "")) != "none" and not (bool(spec.get("extras", {}).get("hostile", false)) or bool(spec.get("extras", {}).get("ally", false)))
	if not _overlaps(spec, solid):
		_drop(meshes, uuid, inst)
		_drop(bodies, uuid, body)
		return
	if bool(spec.get("native_visual", false)):
		pass
	elif _overlaps(spec, draw):
		if inst == null:
			inst = _spawn(spec)
			map_root.add_child(inst)
			inst.global_transform = spec["transform"]
			meshes[uuid] = inst
	elif inst != null:
		_drop(meshes, uuid, inst)
	if collides:
		if body == null:
			body = _make_body(host, spec)
			if body != null:
				bodies[uuid] = body
	elif body != null:
		_drop(bodies, uuid, body)


static func _ring_at(chunk: Vector2i, radius: int) -> Dictionary:
	return {"low": chunk - Vector2i(radius, radius), "high": chunk + Vector2i(radius, radius)}


static func _drop(bag: Dictionary, uuid: String, node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
	bag.erase(uuid)


static func _spec(visual: MeshInstance3D) -> Dictionary:
	var Io = load("res://scripts/world3d/gltf_map_io.gd")
	var bounds: AABB = visual.transform * visual.get_aabb()
	var extras: Dictionary = Io.extras_of(visual).duplicate(true)
	if visual.has_meta("native_dynamic"): extras["rmmo_collision"] = "none"
	var spec := {
		"native_visual": visual.has_meta("native_visual"),
		"uuid": str(visual.name),
		"position": visual.position,
		"rotation": visual.rotation,
		"transform": visual.transform,
		"chunk_min": chunk_key(bounds.position),
		"chunk_max": chunk_key(bounds.end),
		"mesh": visual.mesh,
		"material_override": visual.material_override,
		"surface_overrides": [],
		"cast_shadow": visual.cast_shadow,
		"extras": extras,
		"chunk": chunk_key(visual.position),
	}
	for slot in visual.mesh.get_surface_count(): spec.surface_overrides.append(visual.get_surface_override_material(slot))
	if visual.has_meta("ground_batch_record"):
		spec.ground_batch_record = visual.get_meta("ground_batch_record")
		# Off-screen terrain keeps CPU collision/authoring data, not GPU buffers.
		spec.mesh = CpuMesh.capture(visual.mesh)
	preload("res://scripts/world3d/building_fixtures.gd").prepare_spec(spec)
	return spec


static func _spawn(spec: Dictionary) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = str(spec.get("uuid", "chunk"))
	visual.mesh = spec.get("mesh")
	if visual.mesh is CpuMesh: visual.mesh = visual.mesh.restore()
	if spec.has("ground_batch_record"): visual.set_meta("ground_batch_record",spec.ground_batch_record)
	visual.material_override = spec.get("material_override")
	visual.cast_shadow=spec.get("cast_shadow",GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for slot in spec.get("surface_overrides",[]).size(): visual.set_surface_override_material(slot,spec.surface_overrides[slot])
	visual.set_meta("stream_instance", true)
	visual.position = spec.get("position", Vector3.ZERO)
	visual.rotation = spec.get("rotation", Vector3.ZERO)
	visual.transform = spec.get("transform", visual.transform)
	var extras: Dictionary = spec.get("extras", {})
	if not extras.is_empty():
		visual.set_meta("extras", extras)
	preload("res://scripts/world3d/wind_response.gd").register(visual)
	if bool(extras.get("invisible", false)):
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):
		visual.visible = false
		return visual
	if str(extras.get("kind", "")) == "npc":
		var bounds: AABB = visual.mesh.get_aabb()
		visual.mesh = null
		var actor := preload("res://scripts/char/character_model_3d.gd").create_npc(extras.get("appearance", {}))
		actor.position.y = bounds.position.y
		visual.add_child(actor)
		var label := preload("res://scripts/char/character_overhead_label.gd").new()
		label.model=actor
		label.text = str(extras.get("name", extras.get("npc_id", "NPC")))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.003
		visual.add_child(label)
	return visual


static func _make_body(host: Node, spec: Dictionary) -> StaticBody3D:
	var extras: Dictionary = spec.get("extras", {})
	if str(extras.get("rmmo_collision", "")) == "none" or (bool(extras.get("hostile", false)) or bool(extras.get("ally", false))):
		return null
	var body := StaticBody3D.new()
	body.name = "%s_body" % str(spec.get("uuid", "chunk"))
	body.set_meta("uuid", str(spec["uuid"]))
	body.set_meta("surface_id", str(extras.get("surface_id", "ground")))
	body.set_meta("kind", str(extras.get("kind", "box")))
	body.set_meta("target_path", str(extras.get("target_path", "")))
	body.set_meta("spawn", extras.get("spawn", [0, 0.9, 4]))
	body.set_meta("npc_id", str(extras.get("npc_id", "")))
	body.set_meta("node_id", str(extras.get("node_id", "")))
	body.set_meta("line", str(extras.get("line", "")))
	if extras.get("seat") is Dictionary:body.set_meta("seat",extras.seat.duplicate(true))
	var position: Vector3 = spec.get("position", Vector3.ZERO)
	body.set_meta("center", position)
	body.position = position
	body.rotation = spec.get("rotation", Vector3.ZERO)
	body.transform = spec.get("transform", body.transform)
	var shape := CollisionShape3D.new()
	var mesh: Mesh = spec.get("mesh", null) as Mesh
	if mesh == null:
		body.free()
		return null
	# A bounding box is not a collision mesh: it would fill arches and stairs.
	# Cache the static shape in the document view spec across residency changes.
	if not spec.has("shape"):
		if mesh is BoxMesh or (mesh is CpuMesh and mesh.box_size != Vector3.ZERO):
			var box := BoxShape3D.new()
			box.size = mesh.get_aabb().size
			spec["shape"] = box
		else:
			spec["shape"] = mesh.create_trimesh_shape()
	shape.shape = spec["shape"]
	body.add_child(shape)
	host.add_child(body)
	body.global_transform = spec.get("transform", body.transform)
	return body


static func _overlaps(spec: Dictionary, chunks: Dictionary) -> bool:
	var low: Vector2i = spec.get("chunk_min", spec["chunk"])
	var high: Vector2i = spec.get("chunk_max", spec["chunk"])
	var ring_low: Vector2i = chunks["low"]
	var ring_high: Vector2i = chunks["high"]
	return low.x <= ring_high.x and high.x >= ring_low.x and low.y <= ring_high.y and high.y >= ring_low.y
