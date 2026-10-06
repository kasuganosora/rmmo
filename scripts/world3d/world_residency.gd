extends RefCounted
## Draw distance and collision distance are separate. Far ground is not a hole.

const RENDER_M := 48.0
const COLLISION_M := 96.0


static func classify(origin: Vector3, records: Array) -> Dictionary:
	var render: Array[String] = []
	var collision: Array[String] = []
	for record in records:
		var position: Array = record.get("position", [0, 0, 0])
		var dx := float(position[0]) - origin.x
		var dz := float(position[2]) - origin.z
		var distance := Vector2(dx, dz).length()
		var uuid := str(record.get("uuid", ""))
		if distance <= COLLISION_M:
			collision.append(uuid)
		if distance <= RENDER_M:
			render.append(uuid)
	return {"render": render, "collision": collision}


static func sync(map_root: Node, host: Node, origin: Vector3) -> void:
	var hold := _hold(map_root)
	var meshes: Array = []
	for child in map_root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	for child in hold.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	var records: Array = []
	for mesh in meshes:
		var visual := mesh as MeshInstance3D
		records.append({
			"uuid": str(visual.name),
			"position": [visual.position.x, visual.position.y, visual.position.z],
		})
	var bands: Dictionary = classify(origin, records)
	var collision: Array = bands.collision
	var render: Array = bands.render
	for mesh in meshes:
		var visual := mesh as MeshInstance3D
		var uuid := str(visual.name)
		var body := host.get_node_or_null("%s_body" % uuid)
		if not collision.has(uuid):
			if visual.get_parent() != hold:
				visual.reparent(hold)
			if body != null:
				body.queue_free()
			continue
		if visual.get_parent() != map_root:
			visual.reparent(map_root)
		visual.visible = render.has(uuid)
		if body == null:
			_make_body(host, visual)


static func _hold(map_root: Node) -> Node:
	if map_root.has_meta(&"residency_hold"):
		var existing: Variant = map_root.get_meta(&"residency_hold")
		if is_instance_valid(existing) and existing is Node and not (existing as Node).is_queued_for_deletion():
			return existing
		map_root.remove_meta(&"residency_hold")
	var hold := Node.new()
	hold.name = "ResidencyHold"
	map_root.set_meta(&"residency_hold", hold)
	if not bool(map_root.get_meta(&"residency_hold_exit", false)):
		map_root.set_meta(&"residency_hold_exit", true)
		map_root.tree_exiting.connect(_release_hold.bind(map_root), CONNECT_ONE_SHOT)
	return hold


static func _release_hold(map_root: Node) -> void:
	if not is_instance_valid(map_root) or not map_root.has_meta(&"residency_hold"):
		return
	var hold: Variant = map_root.get_meta(&"residency_hold")
	map_root.remove_meta(&"residency_hold")
	if is_instance_valid(hold):
		(hold as Node).free()


static func _make_body(host: Node, visual: MeshInstance3D) -> void:
	var Io = load("res://scripts/world3d/gltf_map_io.gd")
	var body := StaticBody3D.new()
	body.name = "%s_body" % str(visual.name)
	var extras: Dictionary = Io.extras_of(visual)
	body.set_meta("surface_id", str(extras.get("surface_id", "ground")))
	body.set_meta("kind", str(extras.get("kind", "box")))
	body.set_meta("target_path", str(extras.get("target_path", "")))
	body.set_meta("spawn", extras.get("spawn", [0, 0.9, 4]))
	body.set_meta("npc_id", str(extras.get("npc_id", "")))
	body.set_meta("node_id", str(extras.get("node_id", "")))
	body.set_meta("line", str(extras.get("line", "")))
	body.set_meta("center", visual.global_position)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = visual.get_aabb().size
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.global_transform = visual.global_transform
