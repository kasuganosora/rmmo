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
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	var negative := OS.get_cmdline_user_args().has("--disabled")
	var scene := Node3D.new()
	root.add_child(scene)
	var points := PackedVector3Array([Vector3(-1,1,-1),Vector3(1,1,-1),Vector3(0,1,1),Vector3(-.1,1.001,-.1),Vector3(.1,1.001,-.1),Vector3(0,1.001,.1)])
	var edge_only := OS.get_cmdline_user_args().has("--edge-only")
	var reverse_self := OS.get_cmdline_user_args().has("--reverse-self")
	if edge_only:
		points = PackedVector3Array([Vector3(-2,1,-.02),Vector3(2,1,-.02),Vector3(2,1,.02),Vector3(-.02,1.1,-2),Vector3(-.02,1.1,2),Vector3(.02,1.1,2)])
	var sweep := OS.get_cmdline_user_args().has("--sweep") or reverse_self
	var moving_anchor := OS.get_cmdline_user_args().has("--moving-anchor")
	if sweep or moving_anchor:
		for i in range(3,6): points[i].y = 1.1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.BLACK,Color.BLACK,Color.BLACK,Color.RED,Color.RED,Color.RED])
	if reverse_self: arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED,Color.RED,Color.RED,Color.BLACK,Color.BLACK,Color.BLACK])
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
	solver.self_contact_structural_projection = OS.get_cmdline_user_args().has("--contact-structure")
	solver.self_contact_mass_balance = OS.get_cmdline_user_args().has("--mass-balance")
	solver.review_stage_trace = OS.get_cmdline_user_args().has("--stage-trace")
	solver.review_trace_active = solver.review_stage_trace
	solver.self_contact_iterations = 4 if OS.get_cmdline_user_args().has("--contact-iterations") else 1
	solver.self_edge_contacts = edge_only and not OS.get_cmdline_user_args().has("--without-edges")
	solver.self_collide = not negative
	solver.continuous_self_contacts = not OS.get_cmdline_user_args().has("--legacy")
	solver.peer_collider_voxel_resolution = 0
	if OS.get_cmdline_user_args().has("--proxy"):
		solver.peer_collider_voxel_resolution = 32
	solver.self_collide_thickness = .006
	solver.gravity = Vector3.ZERO
	if sweep: solver.gravity = Vector3(0,-720,0) # 20 cm in one 1/60 s step.
	if reverse_self: solver.gravity = Vector3(0,720,0)
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
	if solver.review_stage_trace:ok = ok and not solver.review_stage_labels.is_empty()
	var gap := INF
	var pin_error := 0.0
	if ok:
		var values := result.to_float32_array()
		for i in 6:
			var point := Vector3(values[i*4],values[i*4+1],values[i*4+2])
			ok = ok and point.is_finite()
			if (i >= 3 if reverse_self else i < 3): pin_error = maxf(pin_error,point.distance_to(points[i]))
			else: gap = minf(gap,point.y-(1.2 if moving_anchor else 1.0))
		if reverse_self:
			var a:=Vector3(values[0],values[1],values[2]);var b:=Vector3(values[4],values[5],values[6]);var c:=Vector3(values[8],values[9],values[10])
			var normal:Vector3=(b-a).cross(c-a)
			ok = ok and absf(normal.y)>1e-8
			gap=INF
			for i in range(3,6):
				var p:Vector3=points[i]
				ok = ok and inside_xz(Vector2(p.x,p.z),a,b,c)
				var y:float=a.y-(normal.x*(p.x-a.x)+normal.z*(p.z-a.z))/normal.y
				gap=minf(gap,p.y-y)
		if edge_only:
			# Endpoints lie metres outside the narrow crossed strip. Measure the
			# actual overlapping faces, not clearance at non-contact endpoints.
			var a:=Vector3(values[12],values[13],values[14])
			var b:=Vector3(values[16],values[17],values[18])
			var c:=Vector3(values[20],values[21],values[22])
			var normal:Vector3=(b-a).cross(c-a)
			gap=INF
			ok = ok and absf(normal.y)>1e-8
			for z in [-.015,-.01,-.005]:
				# These samples lie inside the overlap, away from both diagonals.
				ok = ok and inside_xz(Vector2(-.01,z),a,b,c) and inside_xz(Vector2(-.01,z),points[0],points[1],points[2])
				var y:float=a.y-(normal.x*(-.01-a.x)+normal.z*(z-a.z))/normal.y
				gap=minf(gap,y-1.0)
	var required_gap := .0059 if sweep or moving_anchor or not solver.continuous_self_contacts else .0009
	ok = ok and gap >= required_gap and pin_error < .000001
	if not sweep and not moving_anchor and solver.continuous_self_contacts: ok = ok and gap < .0011
	print("SELF CONTACT gap=",gap," pin_error=",pin_error," enabled=",not negative)
	scene.free()
	for frame in 4: await process_frame
	if ok: print("PASS self contact separation"); quit()
	else: push_error("Full topology self contact did not separate the sheets"); quit(2)

func inside_xz(p:Vector2,a:Vector3,b:Vector3,c:Vector3)->bool:
	var origin:=Vector2(a.x,a.z);var u:=Vector2(b.x,b.z)-origin;var v:=Vector2(c.x,c.z)-origin
	var determinant:=u.cross(v)
	if absf(determinant)<1e-10:return false
	var q:=p-origin;var x:=q.cross(v)/determinant;var y:=u.cross(q)/determinant
	return x>=0.0 and y>=0.0 and x+y<=1.0
