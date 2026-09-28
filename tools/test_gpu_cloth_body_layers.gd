extends SceneTree
## One moving body triangle pushes two close free cloth layers from below.
## Both body clearance and source layer ordering must hold simultaneously.
var captured:=PackedByteArray()
var received:=false
var test_basis:=Basis.IDENTITY
func _initialize()->void:call_deferred("run")
func receive(data:PackedByteArray)->void:captured=data;received=true
func read_gpu(solver:Node)->void:call_deferred("receive",solver._rd.buffer_get_data(solver._positions_buffer))
func collider(y:float)->PackedVector3Array:
	var points:=PackedVector3Array([Vector3(-.02,y,-.01),Vector3(.02,y,-.01),Vector3(0,y,.02)])
	for i in points.size():points[i]=test_basis*points[i]
	return points
func run()->void:
	if preload("res://tools/gpu_shader_review_manifest.gd").collect().is_empty():quit(2);return
	if OS.get_cmdline_user_args().has("--rotated"):test_basis=Basis(Vector3(0,0,1),.7)*Basis(Vector3.UP,.4)
	var scene:=Node3D.new();root.add_child(scene)
	var points:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
	for layer in 2:
		var size:float=1.0-float(layer)*.05;var y:float=1.0+float(layer)*.002
		if OS.get_cmdline_user_args().has("--aligned"):size=1.0
		points.append_array(PackedVector3Array([Vector3(-size,y,-size),Vector3(size,y,-size),Vector3(0,y,size)]))
		for i in 3:normals.append(Vector3.UP);colors.append(Color.RED);indices.append(layer*3+i)
	for i in points.size():points[i]=test_basis*points[i];normals[i]=test_basis*normals[i]
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var target:=MeshInstance3D.new();target.name="Cloth";target.mesh=mesh;scene.add_child(target)
	var solver=load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
	solver.target_mesh=NodePath("../Cloth");solver.external_surface_input=true;solver.external_triangle_count=1;solver.external_reverse_contacts=true
	solver.self_collide=true;solver.continuous_self_contacts=true;solver.self_edge_contacts=true;solver.self_contact_mass_balance=true
	solver.self_contact_body_tangents=OS.get_cmdline_user_args().has("--body-tangents")
	solver.self_contact_iterations=4;solver.self_contact_structural_projection=true;solver.peer_collider_voxel_resolution=0
	solver.substeps=1;solver.solver_iterations=12;solver.gravity=Vector3.ZERO;solver.damping=1;solver.collider_friction=0;solver.max_travel_distance=0
	solver.body_collider_thickness=.006;solver.self_collide_thickness=.006
	scene.add_child(solver);solver.set_process(false)
	for frame in 5:await process_frame
	assert(solver.set_external_frame(points,collider(.9)));assert(solver.warm_start())
	for frame in 3:await process_frame
	assert(solver.set_external_frame(points,collider(1.1)));solver._simulate(1.0/60)
	for frame in 4:await process_frame
	RenderingServer.call_on_render_thread(read_gpu.bind(solver))
	for frame in 120:
		if received:break
		await process_frame
	var ok:=received and captured.size()==6*16
	var clearance:=INF;var layer_gap:=INF
	if ok:
		var values:=captured.to_float32_array();var output:=PackedVector3Array()
		for i in 6:
			var p:Vector3=test_basis.inverse()*Vector3(values[i*4],values[i*4+1],values[i*4+2]);ok=ok and p.is_finite();output.append(p)
		for point:Vector3 in collider(1.1):
			point=test_basis.inverse()*point
			var heights:Array[float]=[]
			for layer in 2:
				var a:Vector3=output[layer*3];var normal:Vector3=(output[layer*3+1]-a).cross(output[layer*3+2]-a)
				ok=ok and absf(normal.y)>1e-8
				heights.append(a.y-(normal.x*(point.x-a.x)+normal.z*(point.z-a.z))/normal.y)
				clearance=minf(clearance,heights[-1]-point.y)
			layer_gap=minf(layer_gap,heights[1]-heights[0])
	print("BODY LAYERS body_gap=",clearance," layer_gap=",layer_gap)
	ok=ok and clearance>=.0059 and layer_gap>=.0009
	scene.free()
	for frame in 4:await process_frame
	if ok:print("PASS simultaneous body and layer separation");quit()
	else:push_error("Body and cloth-layer constraints conflict");quit(2)
