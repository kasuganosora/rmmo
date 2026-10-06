extends SceneTree
func _initialize()->void:
	var solver=load("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
	solver.external_surface_input=true;solver._particle_count=65
	solver.external_triangle_count=129;solver._external_triangle_count_at_init=129
	var targets:=PackedVector3Array();var triangles:=PackedVector3Array()
	for i in 65:targets.append(Vector3(i*.001,-i*.37,i*.54))
	for i in 129:
		var center:=Vector3(i*.001,i*.02,-i*.007)
		triangles.append_array(PackedVector3Array([center,center+Vector3.RIGHT,center+Vector3.UP]))
	assert(solver.set_external_frame(targets,triangles))
	var expected:=PackedFloat32Array()
	for p in targets:expected.append_array(PackedFloat32Array([p.x,p.y,p.z,1]))
	assert(expected.to_byte_array()==solver._external_targets)
	expected.clear()
	for p in triangles:expected.append_array(PackedFloat32Array([p.x,p.y,p.z,0]))
	assert(expected.to_byte_array()==solver._external_triangles)
	var retained:PackedByteArray=solver._external_triangles.duplicate()
	var invalid:=triangles.duplicate();invalid[1]=invalid[0]
	assert(not solver.set_external_frame(targets,invalid))
	invalid=triangles.duplicate();invalid[-1]=Vector3(NAN,0,0)
	assert(not solver.set_external_frame(targets,invalid))
	assert(not solver.set_external_frame(PackedVector3Array(),triangles))
	assert(solver._external_triangles==retained)
	solver.free();print("PASS vec4 packet bytes match float32 reference; invalid packets stay atomic");quit()
