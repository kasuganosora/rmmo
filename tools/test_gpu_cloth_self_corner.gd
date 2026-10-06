extends SceneTree
## A free patch crosses two fixed orthogonal cloth faces in the same step.
var result := PackedByteArray()
var received := false
func _initialize() -> void: call_deferred("run")
func receive(bytes: PackedByteArray) -> void:
	result = bytes
	received = true
func read_gpu(solver: Node) -> void:
	call_deferred("receive", solver._rd.buffer_get_data(solver._positions_buffer))
func run() -> void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	var scene := Node3D.new()
	root.add_child(scene)
	var points := PackedVector3Array([
		Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(0,1,1),
		Vector3(0,0,-1),Vector3(0,2,-1),Vector3(0,1,1),
		Vector3(.1,1.1,-.02),Vector3(.12,1.1,-.02),Vector3(.1,1.12,.02)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in points.size():
		normals.append(Vector3.UP)
		colors.append(Color.BLACK if i < 6 else Color.RED)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,3,4,5,6,7,8])
	if OS.get_cmdline_user_args().has("--reverse-faces"):
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([3,5,4,0,2,1,6,8,7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var target := MeshInstance3D.new()
	target.name = "Cloth"
	target.mesh = mesh
	scene.add_child(target)
	var solver = load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
	solver.target_mesh = NodePath("../Cloth")
	solver.self_contact_mass_balance = OS.get_cmdline_user_args().has("--mass-balance")
	solver.self_contact_structural_projection = OS.get_cmdline_user_args().has("--contact-structure")
	solver.self_collide = true
	solver.continuous_self_contacts = true
	solver.self_contact_iterations = 1 if OS.get_cmdline_user_args().has("--single") else 4
	solver.peer_collider_voxel_resolution = 0
	solver.self_collide_thickness = .006
	solver.gravity = Vector3(-720,-720,0)
	solver.max_travel_distance = 0
	solver.max_speed = 100
	solver.damping = 1
	solver.substeps = 1
	scene.add_child(solver)
	solver.set_process(false)
	for frame in 6: await process_frame
	solver._simulate(1.0/60.0)
	for frame in 4: await process_frame
	RenderingServer.call_on_render_thread(read_gpu.bind(solver))
	for frame in 120:
		if received: break
		await process_frame
	var gap := INF
	var pin_error := 0.0
	var ok: bool = received and solver._self_collide_uniform_set.is_valid()
	if ok:
		var values := result.to_float32_array()
		for i in points.size():
			var id: int = solver._original_to_welded[i]
			var p := Vector3(values[id*4],values[id*4+1],values[id*4+2])
			ok = ok and p.is_finite()
			if i < 6: pin_error = maxf(pin_error,p.distance_to(points[i]))
			else: gap = minf(gap,minf(p.x,p.y-1.0))
	ok = ok and gap >= .0059 and pin_error < .000001
	print("SELF CORNER gap=",gap," pin_error=",pin_error)
	scene.free()
	for frame in 4: await process_frame
	if ok: print("PASS simultaneous self contacts"); quit()
	else: push_error("A self contact was lost when projecting the other face"); quit(2)
