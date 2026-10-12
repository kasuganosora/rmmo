extends SceneTree
## Isolated GLB geometry review. No game world, editor, catalog or user map write.
const OUT := "D:/code/rmmo_runtime/art_sources/axel_guild/whitebox_v1"
var failures: Array = []
var summary: Dictionary = {}
var mesh_count := 0
var triangles := 0
var collision_count := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("FAIL ", message)

func from_blender(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[2]), -float(p[1]))

func semantic(n: Node) -> String:
	var current := n
	while current != null:
		var label := str(current.name)
		if label.length() > 3 and label.substr(0, 2).is_valid_int() and label[2] == "_":
			return label
		current = current.get_parent()
	return "unknown"

func collisions(n: Node) -> void:
	if n is MeshInstance3D:
		mesh_count += 1
		for surf in n.mesh.get_surface_count():
			var arrays: Array = n.mesh.surface_get_arrays(surf)
			var indexes: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indexes.size() / 3 if not indexes.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
		var group := semantic(n)
		if not group.begins_with("60_") and bool(n.get_meta("collision_review", true)):
			var body := StaticBody3D.new()
			body.name = "ReviewCollision"
			body.set_meta("source", str(n.name))
			var shape := CollisionShape3D.new()
			shape.shape = n.mesh.create_trimesh_shape()
			body.add_child(shape)
			n.add_child(body)
			collision_count += 1
	for child in n.get_children():
		if not child is StaticBody3D:
			collisions(child)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/manifest.json"))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_file(OUT + "/axel_guild_whitebox.glb", state) == OK, "GLB parse")
	var scene := document.generate_scene(state)
	check(scene != null, "GLB scene instantiation")
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	collisions(scene)
	# External approach floor is a temporary review fixture, not part of asset.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(120, .2, 120)
	ground_shape.shape = ground_box
	ground.position = Vector3(16, -.42, -7)
	ground.add_child(ground_shape)
	scene.add_child(ground)
	for frame in 4: await physics_frame
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	# Body clearance above a 0.22 m step band. Stair rises/floors checked separately.
	capsule.radius = .28
	capsule.height = 1.58
	var routes: Dictionary = manifest.route_probes_xyz_blender
	var route_results: Array = []
	var count := 0
	for route_name: String in routes:
		var route: Array = routes[route_name]
		var misses: Array = []
		var obstructions: Array = []
		var samples := 0
		for segment in range(route.size() - 1):
			var start := from_blender(route[segment])
			var end := from_blender(route[segment + 1])
			var steps := maxi(1, ceili(start.distance_to(end) / .12))
			for step in range(steps + 1):
				var p := start.lerp(end, float(step) / steps)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * .24, p - Vector3.UP * .27))
				if hit.is_empty():
					misses.append([p.x,p.y,p.z])
				else:
					p.y = hit.position.y
					var q := PhysicsShapeQueryParameters3D.new()
					q.shape = capsule
					q.margin = .005
					q.transform = Transform3D(Basis.IDENTITY,p + Vector3.UP * 1.03)
					var hits := space.intersect_shape(q, 4)
					if not hits.is_empty():
						obstructions.append({"point":[p.x,p.y,p.z],"objects":hits.map(func(h: Dictionary): return str(h.collider.get_meta("source",h.collider.name)))})
				samples += 1
		count += samples
		route_results.append({"route":route_name,"samples":samples,"floor_gaps":misses,"body_obstructions":obstructions})
		check(misses.is_empty(),route_name + " supporting floor")
		check(obstructions.is_empty(),route_name + " body/head clearance")
	# Solid wall versus real apertures; verifies exported geometry, not source flags.
	for probe: Dictionary in [
		{"name":"main door open", "start":Vector3(16,1.5,1),"end":Vector3(16,1.5,-.7),"clear":true},
		{"name":"front wall solid", "start":Vector3(12,1.5,1),"end":Vector3(12,1.5,-.7),"clear":false},
		{"name":"reception arch open", "start":Vector3(21,2,-10.3),"end":Vector3(21,2,-11.3),"clear":true},
		{"name":"reception pier solid", "start":Vector3(22.2,2,-10.3),"end":Vector3(22.2,2,-11.3),"clear":false}]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe.start,probe.end))
		check(hit.is_empty() == probe.clear, probe.name)
	check(mesh_count > 100, "hierarchy retained")
	check(triangles == int(manifest.triangles_evaluated), "export triangle count matches source")
	summary = {"failures":failures,"mesh_count":mesh_count,"triangles":triangles,"collision_meshes":collision_count,
		"route_sample_count":count,"routes":route_results,"glb_sha256":FileAccess.get_sha256(OUT + "/axel_guild_whitebox.glb"),
		"method":"Actual exported GLB; supporting-floor ray plus 0.56m-diameter body capsule above a 0.22m step band. Not game-controller, navmesh, camera or structural certification."}
	FileAccess.open(OUT + "/geometry_review.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	print("WHITEBOX_REVIEW ", failures.size(), " failures; ", count, " route samples; ", triangles, " triangles")
	quit(0 if failures.is_empty() else 1)
