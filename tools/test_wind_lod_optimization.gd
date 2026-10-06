extends SceneTree
var failures=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var wind=preload("res://scripts/world3d/wind_runtime.gd").new();root.add_child(wind)
	var camera=Camera3D.new();root.add_child(camera);wind.camera=camera;wind.set_physics_process(false)
	var mesh=MeshInstance3D.new();mesh.mesh=BoxMesh.new();root.add_child(mesh)
	mesh.custom_aabb=AABB(Vector3(-2,0,-2),Vector3(4,10,4));mesh.position=Vector3(20,0,0);mesh.scale=Vector3(2,2,2)
	mesh.visibility_range_begin=35;mesh.visibility_range_end=85;mesh.visibility_range_begin_margin=1;mesh.visibility_range_end_margin=1
	for distance in [0.,32.,33.,35.,84.,87.,88.,100.]:
		camera.position=Vector3(20,10,distance)
		check(wind._range_active(mesh)==(distance>=33 and distance<=87),"transformed common center and transition guard "+str(distance))
	mesh.visibility_range_end=0;camera.position=Vector3(20,10,200);check(wind._range_active(mesh),"unbounded range")
	mesh.visibility_range_begin=0;check(wind._range_active(mesh),"ordinary wind mesh unaffected")
	mesh.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}})
	preload("res://scripts/world3d/wind_response.gd").register(mesh)
	mesh.visibility_range_begin=35;mesh.visibility_range_end=85
	camera.position=Vector3(20,10,40);wind.refresh();wind.advance(Vector3(2,0,0),1)
	check(wind.active_rows.size()==1,"active authored LOD")
	var material=wind.receivers[mesh.get_instance_id()].materials[0]
	camera.position=Vector3(20,10,10);wind.advance(Vector3(2,0,0),2)
	check(wind.active_rows.is_empty() and material.get_shader_parameter("wind_time")==1.,"hidden LOD skips update")
	camera.position=Vector3(20,10,40);wind.advance(Vector3(2,0,0),3)
	check(wind.active_rows.size()==1 and material.get_shader_parameter("wind_time")==3.,"camera return immediately resumes current time")
	mesh.position.x=300;wind.refresh();check(wind.active_rows.is_empty(),"removed receiver clears cached work")
	# Rank-one normal transform must match the previous full inverse under
	# both authorable anchor axes, including negative/reversed bend slopes.
	var rng=RandomNumberGenerator.new();rng.seed=717
	for i in 2000:
		var axis=Vector3.RIGHT if i%2==0 else Vector3.UP
		var slope=Vector3(rng.randf_range(-.8,.8),rng.randf_range(-.8,.8),rng.randf_range(-.8,.8))
		var jac=Basis(Vector3.RIGHT+slope*axis.x,Vector3.UP+slope*axis.y,Vector3.BACK+slope*axis.z)
		var normal=Vector3(rng.randf(),rng.randf(),rng.randf()).normalized()
		var old=(jac.inverse().transposed()*normal).normalized()
		var fast=(normal-axis*slope.dot(normal)/(1.+axis.dot(slope))).normalized()
		check(old.distance_to(fast)<.00001,"normal algebra")
	print("WIND_LOD_FAILURES ",failures);quit(1 if failures else 0)
