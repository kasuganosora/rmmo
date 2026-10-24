extends "res://tools/test_house_geometry_identity_reuse.gd"
const Binary=preload("res://scripts/world3d/prefab_binary_cache.gd")
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.discard_map_textures=true;controls.enable_white_materials()
	Binary.directory_override=preload("res://scripts/world3d/map_paths.gd").cache_directory("prefab_face_work_test").path_join(str(OS.get_process_id()))
	var data:=fixture();var indices:=PackedInt32Array();indices.resize(60000)
	for i in indices.size():indices[i]=i%3
	data.meshes[0].surfaces[0][Mesh.ARRAY_INDEX]=indices
	for i in 3:data.meshes.append(data.meshes[0].duplicate(true))
	var value:=encode(data);var source:=record(value);var built:=Binary.build(value)
	check(built.ok,"large indexed fixture converts outside the project")
	var results:Array=[];var expected:Array=[]
	for binary:bool in [false,true]:
		Binary.enabled=binary;evict(value.sha256)
		var packet:=House._decode_packet(value)
		var began:=Time.get_ticks_usec();var last:Dictionary={}
		for i in 24:last=House.prepare_cpu(source)
		var elapsed:=Time.get_ticks_usec()-began
		if expected.is_empty():expected=last.collision_faces.duplicate(true)
		check(last.collision_faces==expected,"repeated preparation keeps exact triangle order")
		var exposed:PackedVector3Array=last.collision_faces[0];exposed[0]=Vector3(99,99,99)
		check(House.prepare_cpu(source).collision_faces==expected,"editing a job face array cannot change the next job or canonical data")
		if binary and not "--baseline" in OS.get_cmdline_user_args():
			check(packet.has("collision_faces") and House._decoded_bytes>=int(value.length)+4*60000*12,"cached face storage is charged to the existing decode budget")
		results.append({"binary":binary,"calls":24,"indexed_face_vertices_per_call":240000,"elapsed_us":elapsed})
	House.evict_geometry({value.sha256:true})
	check(not House._decoded.has(value.sha256) and House._decoded_bytes==0,"eviction releases the geometry and cached-face capacity together")
	check(House.prepare_cpu(source).collision_faces==expected,"returning after eviction reconstructs the same independent collision input")
	print("PREFAB_FACE_WORK ",JSON.stringify({"results":results,"failures":failures}));quit(1 if failures else 0)
