extends SceneTree
## Run against RMMO's pinned dependency or an identically patched checkout.
## This is a compatibility probe, not acceptance of clothing or body collision.
var sample:=PackedByteArray()
var received:=false
func plane(height:float)->PackedVector3Array:
	return PackedVector3Array([Vector3(-2,height,-2),Vector3(-2,height,3),Vector3(3,height,-2),Vector3(3,height,-2),Vector3(-2,height,3),Vector3(3,height,3)])
func _initialize()->void:call_deferred("run")
func receive(bytes:PackedByteArray)->void:
	sample=bytes;received=true
func read_result(solver:Node)->void:
	call_deferred("receive",solver._rd.buffer_get_data(solver._positions_buffer))
func run()->void:
	var blend:=OS.get_cmdline_user_args().has("--blend")
	var inertia:=OS.get_cmdline_user_args().has("--inertia")
	var scene:=Node3D.new();root.add_child(scene)
	var vertices:=PackedVector3Array();var colors:=PackedColorArray();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
	for y in 9:
		for x in 9:
			vertices.append(Vector3(float(x)/8.0,1.0,float(y)/8.0));normals.append(Vector3.UP)
			colors.append(Color(0 if y==0 and not inertia else (.5 if blend else 1.0),0,0,1))
	for y in 8:
		for x in 8:
			var a:=y*9+x
			indices.append_array(PackedInt32Array([a,a+1,a+9,a+1,a+10,a+9]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var target:=MeshInstance3D.new();target.name="TestCloth";target.mesh=mesh;scene.add_child(target)
	var script:Script=load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd")
	assert(script!=null)
	var solver=script.new();solver.name="Candidate";solver.target_mesh=NodePath("../TestCloth")
	var external:=OS.get_cmdline_user_args().has("--external")
	if external:solver.external_surface_input=true;solver.external_triangle_count=2
	if external and OS.get_cmdline_user_args().has("--reverse"):solver.external_reverse_contacts=true
	solver.substeps=4;solver.max_travel_distance=.5
	if inertia:solver.gravity=Vector3.ZERO;solver.damping=1;solver.max_travel_distance=0
	scene.add_child(solver)
	if inertia:
		await probe_reference_motion(solver,scene,vertices)
		return
	var targets:PackedVector3Array=solver._welded_positions.duplicate()
	if external:
		assert(solver.set_external_frame(targets,plane(.75)))
		var packet:PackedByteArray=solver._external_targets.duplicate()
		assert(not solver.set_external_frame(PackedVector3Array(),plane(.75)))
		var invalid:=targets.duplicate();invalid[0]=Vector3(NAN,0,0)
		assert(not solver.set_external_frame(invalid,plane(.75)))
		var collapsed:=plane(.75);collapsed[1]=collapsed[0]
		assert(not solver.set_external_frame(targets,collapsed))
		assert(solver._external_targets==packet,"Invalid input must not partially replace the accepted frame")
	for frame in 180:await process_frame
	if external:
		# Move the authored attachment targets and the scene collision surface.
		for frame in 60:
			for i in targets.size():targets[i]=solver._welded_positions[i]+Vector3(.2,.1,0)*float(frame+1)/60.0
			assert(solver.set_external_frame(targets,plane(.75+.1*float(frame+1)/60.0)))
			await process_frame
		for frame in 60:await process_frame
	assert(solver._gpu_init_done,"Candidate GPU initialization failed")
	solver.set_process(false)
	if OS.get_cmdline_user_args().has("--large-step"):
		solver.substeps=1
		solver._simulate(.5)
		for frame in 3:await process_frame
	var minimum_height:=.847
	if OS.get_cmdline_user_args().has("--moving-impact"):
		assert(external)
		# The face crosses the resting cloth in one frame. End-point proximity
		# and a particle-only sweep cannot detect this moving-surface contact.
		solver.substeps=1
		if blend:
			for i in targets.size():
				if solver._debug_cloth_weights[i]>.00001:targets[i].y=.95
		assert(solver.set_external_frame(targets,plane(1.05)))
		solver._simulate(1.0/60.0)
		for frame in 3:await process_frame
		minimum_height=1.047
	RenderingServer.call_on_render_thread(read_result.bind(solver))
	for frame in 120:
		if received:break
		await process_frame
	assert(received and sample.size()==solver._particle_count*16)
	var values:=sample.to_float32_array();var drop:=0.0;var pin_error:=0.0
	for i in solver._particle_count:
		var point:=Vector3(values[i*4],values[i*4+1],values[i*4+2])
		assert(point.is_finite() and point.length()<5)
		drop=maxf(drop,1.0-point.y)
		if solver._debug_cloth_weights[i]<.00001:
			pin_error=maxf(pin_error,point.distance_to(targets[i]))
		if external and point.y<minimum_height:
			push_error("External collider penetrated: particle=%d y=%f"%[i,point.y])
			scene.free()
			for frame in 4:await process_frame
			quit(2);return
	assert((drop>.001 or blend or OS.get_cmdline_user_args().has("--moving-impact")) and pin_error<.00001,"Gravity and fixed row must both work")
	print("PASS candidate smoke: external=",external," particles=",solver._particle_count," max_drop=",drop," pin_error=",pin_error)
	scene.free()
	for frame in 4:await process_frame
	quit()

func probe_reference_motion(solver:Node3D,scene:Node3D,vertices:PackedVector3Array)->void:
	solver.set_process(false)
	for frame in 4:await process_frame
	assert(solver._gpu_init_done)
	# Also move before seeding: warm start must reset the old reference frame.
	scene.position=Vector3(.2,.1,0)
	var initial:Transform3D=solver.global_transform
	if solver.has_method("warm_start"):solver.warm_start()
	else:
		RenderingServer.call_on_render_thread(solver._gpu_do_warm_start)
		# Legacy baseline should be tested for velocity recovery, not warm-up.
		solver._prev_skel_world_pos=solver.global_position
		solver._prev_skel_world_basis=solver.global_basis
	for frame in 3:await process_frame
	for frame in 20:
		scene.position+=Vector3(.01,-.005,.007)
		if OS.get_cmdline_user_args().has("--rotate-inertia"):scene.rotation.y+=.01
		solver._simulate(1.0/60.0)
		await process_frame
		await RenderingServer.frame_post_draw
	received=false;RenderingServer.call_on_render_thread(read_result.bind(solver))
	while not received:await process_frame
	var values:=sample.to_float32_array();var maximum:=0.0
	for i in vertices.size():
		var point:=Vector3(values[i*4],values[i*4+1],values[i*4+2])
		maximum=maxf(maximum,(solver.global_transform*point).distance_to(initial*vertices[i]))
	print("REFERENCE MOTION maximum world drift=",maximum)
	scene.free()
	for frame in 4:await process_frame
	if maximum>.0001:push_error("Reference motion was accumulated as physical velocity");quit(2)
	else:print("PASS reference-frame motion");quit()
