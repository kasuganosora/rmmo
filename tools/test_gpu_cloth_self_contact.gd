extends SceneTree
## Two disconnected sheets: the upper free patch must separate from a fixed
## lower face even when proxy decimation is disabled. No body or pose workaround.
var result := PackedByteArray()
var received := false
func _initialize() -> void: call_deferred("run")
func receive(bytes: PackedByteArray) -> void:
	result = bytes
	received = true
func read_gpu(solver: Node) -> void:
	call_deferred("receive", solver._rd.buffer_get_data(solver._positions_buffer))
func run() -> void:
	var negative := OS.get_cmdline_user_args().has("--disabled")
	var scene := Node3D.new()
	root.add_child(scene)
	var points := PackedVector3Array([Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(0,1,1),Vector3(-.1,1.001,-.1),Vector3(.1,1.001,-.1),Vector3(0,1.001,.1)])
	var sweep := OS.get_cmdline_user_args().has("--sweep")
	var moving_anchor := OS.get_cmdline_user_args().has("--moving-anchor")
	if sweep or moving_anchor:
		for i in range(3,6): points[i].y = 1.1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.BLACK,Color.BLACK,Color.BLACK,Color.RED,Color.RED,Color.RED])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,3,4,5])
	if OS.get_cmdline_user_args().has("--flip-winding"):
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,3,5,4])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var target := MeshInstance3D.new()
	target.name = "Cloth"
	target.mesh = mesh
	scene.add_child(target)
	var solver = load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
	solver.target_mesh = NodePath("../Cloth")
	solver.self_collide = not negative
	solver.continuous_self_contacts = not OS.get_cmdline_user_args().has("--legacy")
	solver.peer_collider_voxel_resolution = 0
	if OS.get_cmdline_user_args().has("--proxy"):
		solver.peer_collider_voxel_resolution = 32
	solver.self_collide_thickness = .006
	solver.gravity = Vector3.ZERO
	if sweep: solver.gravity = Vector3(0,-720,0) # 20 cm in one 1/60 s step.
	solver.max_travel_distance = 0
	solver.damping = 1
	solver.max_speed = 100
	solver.substeps = 1
	if moving_anchor:
		solver.external_surface_input = true
		solver.external_triangle_count = 1
	scene.add_child(solver)
	solver.set_process(false)
	for frame in 6: await process_frame
	if not solver._gpu_init_done:
		push_error("Self contact GPU initialization failed")
		quit(2)
		return
	if moving_anchor:
		for i in 3: points[i].y = 1.2
		var far_collider := PackedVector3Array([Vector3(0,-10,0),Vector3(1,-10,0),Vector3(0,-10,1)])
		if not solver.set_external_frame(points,far_collider):
			push_error("Could not submit moving anchors"); quit(2); return
	if not negative and solver.continuous_self_contacts and not solver._self_collide_uniform_set.is_valid():
		push_error("Continuous self contact pipeline unavailable")
		scene.free()
		quit(2)
		return
	solver._simulate(1.0 / 60.0)
	for frame in 4: await process_frame
	RenderingServer.call_on_render_thread(read_gpu.bind(solver))
	for frame in 120:
		if received: break
		await process_frame
	var ok := received and result.size() == 6 * 16
	var gap := INF
	var pin_error := 0.0
	if ok:
		var values := result.to_float32_array()
		for i in 6:
			var point := Vector3(values[i*4],values[i*4+1],values[i*4+2])
			ok = ok and point.is_finite()
			if i < 3: pin_error = maxf(pin_error,point.distance_to(points[i]))
			else: gap = minf(gap,point.y-(1.2 if moving_anchor else 1.0))
	var required_gap := .0059 if sweep or moving_anchor or not solver.continuous_self_contacts else .0009
	ok = ok and gap >= required_gap and pin_error < .000001
	if not sweep and not moving_anchor and solver.continuous_self_contacts: ok = ok and gap < .0011
	print("SELF CONTACT gap=",gap," pin_error=",pin_error," enabled=",not negative)
	scene.free()
	for frame in 4: await process_frame
	if ok: print("PASS self contact separation"); quit()
	else: push_error("Full topology self contact did not separate the sheets"); quit(2)
