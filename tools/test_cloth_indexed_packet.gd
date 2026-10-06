extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	for packed in [false,true]:
		var packet=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd").new()
		packet.packed_readback=packed
		var solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
		solver.external_surface_input=true;solver._particle_count=3;solver.external_triangle_count=130;solver._external_triangle_count_at_init=130
		var points:=PackedVector3Array();var indices:=PackedInt32Array()
		for i in 129:
			var p:=Vector3(i*.001,i*.01,-i*.007)
			for v in [p,p+Vector3.RIGHT,p+Vector3.UP]:indices.append(points.size());points.append(v)
		var extras:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
		assert(not packet.initialize(PackedInt32Array([0,-1,2]),points.size(),3))
		assert(packet.initialize(indices,points.size(),3))
		var targets:=extras.duplicate();var offset:=Vector3(.123,-.7,.004)
		var triangles:=PackedVector3Array()
		for index in indices:triangles.append(points[index]+offset)
		triangles.append_array(extras)
		assert(solver.set_external_frame(targets,triangles))
		var expected:PackedByteArray=solver._external_triangles.duplicate()
		assert(solver.set_indexed_external_frame(targets,packet,points,offset,extras))
		assert(solver._external_triangles==expected)
		for invalid in [Vector3(NAN,0,0),Vector3(INF,0,0),points[0]]:
			var bad:=points.duplicate();bad[1]=invalid
			assert(not solver.set_indexed_external_frame(targets,packet,bad,offset,extras))
			assert(solver._external_triangles==expected)
		assert(not solver.set_indexed_external_frame(targets,packet,points,offset,PackedVector3Array()))
		var bad_extra:=extras.duplicate();bad_extra[1]=Vector3(NAN,0,0)
		assert(not solver.set_indexed_external_frame(targets,packet,points,offset,bad_extra))
		assert(solver._external_triangles==expected)
		packet.close();packet.close();solver.free()

	print("PASS packed and separate indexed GPU packet byte parity, offset, extras, invalid indices/count/NaN/Inf/degenerate rejection and atomicity");quit()
