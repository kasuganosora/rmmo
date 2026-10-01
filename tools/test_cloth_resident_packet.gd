extends SceneTree
var captured:=PackedByteArray()
func capture(packet:RefCounted)->void:captured=packet.rd.buffer_get_data(packet.output_buffer)
func read_packet(packet:RefCounted)->PackedByteArray:
	RenderingServer.call_on_render_thread(capture.bind(packet));RenderingServer.force_sync();return captured.duplicate()
func _initialize()->void:call_deferred("run")
func run()->void:
	var packet=preload("res://addons/godot_gpu_cloth/src/cloth_resident_packet.gd").new()
	var reference=preload("res://addons/godot_gpu_cloth/src/cloth_indexed_packet.gd").new()
	var indices:=PackedInt32Array([0,1,2]);var points:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var extras:=PackedVector3Array([Vector3(0,2,0),Vector3(1,2,0),Vector3(0,3,0)])
	assert(not packet.initialize(PackedInt32Array([0,-1,2]),3,3))
	assert(packet.initialize(indices,3,3));assert(reference.initialize(indices,3,3))
	var offset:=Vector3(.2,-.13,.7)
	assert(packet.build(points,offset,extras));assert(reference.build(points,offset,extras))
	var accepted:=read_packet(packet);assert(accepted==reference.output)
	for invalid in [Vector3(NAN,0,0),Vector3(INF,0,0),points[0]]:
		var bad:=points.duplicate();bad[1]=invalid
		assert(not packet.build(bad,offset,extras));assert(read_packet(packet)==accepted)
	var bad_extra:=extras.duplicate();bad_extra[1]=Vector3(NAN,0,0)
	assert(not packet.build(points,offset,bad_extra));assert(read_packet(packet)==accepted)
	assert(not packet.build(points,offset,PackedVector3Array()));assert(read_packet(packet)==accepted)
	points[1]+=Vector3(.1,.2,.3)
	assert(packet.build(points,offset,extras));assert(reference.build(points,offset,extras));assert(read_packet(packet)==reference.output)
	assert(packet.payload_readback_bytes==0 and packet.status_readback_bytes==24)
	var solver=preload("res://addons/godot_gpu_cloth/src/gpu_cloth_solver.gd").new()
	solver.external_surface_input=true;solver._particle_count=3;solver.external_triangle_count=2;solver._external_triangle_count_at_init=2
	assert(solver.set_indexed_external_frame(extras,packet,points,offset,extras))
	var saved_targets:PackedByteArray=solver._external_targets.duplicate();accepted=read_packet(packet)
	var bad_targets:=extras.duplicate();bad_targets[0]=Vector3(NAN,0,0)
	assert(not solver.set_indexed_external_frame(bad_targets,packet,points,offset,extras))
	assert(solver._external_targets==saved_targets and read_packet(packet)==accepted)
	assert(solver._external_triangles.is_empty() and solver._external_resident_packet==packet)
	solver.free()
	packet.close();packet.close();reference.close()
	var automatic=preload("res://addons/godot_gpu_cloth/src/cloth_resident_packet.gd").new()
	assert(automatic.initialize(indices,3,3));automatic=null
	RenderingServer.force_sync()
	print("PASS resident GPU payload parity, atomic invalid rejection/recovery, 4-byte status only, repeated release");quit()
