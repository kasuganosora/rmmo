extends "res://tools/test_house_geometry_identity_reuse.gd"
const Binary=preload("res://scripts/world3d/prefab_binary_cache.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
func run()->void:
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	Binary.directory_override=preload("res://scripts/world3d/map_paths.gd").cache_directory("prefab_binary_test").path_join(str(OS.get_process_id()))
	var data:=fixture();data.meshes[0].lods=[{1.5:PackedInt32Array([0,1,2])}]
	var value:=encode(data);var source:=record(value)
	Binary.enabled=false;var before:=House._decode_packet(value);var old_cpu:=House.prepare_cpu(source);evict(value.sha256)
	Binary.enabled=true
	check(Binary.read(value.sha256,value.length).is_empty(),"absent product is a source fallback")
	var built:=Binary.build(value)
	check(built.ok,"offline conversion writes an external binary product")
	var after:=House._decode_packet(value);var cpu:=House.prepare_cpu(source)
	var worker:=Thread.new();worker.start(func():return Binary.read(value.sha256,value.length))
	while worker.is_alive():await process_frame
	var worker_result:Dictionary=worker.wait_to_finish()
	check(not worker_result.is_empty() and var_to_bytes(worker_result.data)==var_to_bytes(after.data),"worker reads configured paths without accessing live scene nodes")
	check(var_to_bytes(after.data)==var_to_bytes(before.data) and after.geometry_keys==before.geometry_keys and after.local_bounds==before.local_bounds,"binary product preserves every array, LOD, material descriptor and bound")
	check(cpu.collision_faces==old_cpu.collision_faces and all_sealed(after) and all_sealed(cpu.data),"collision order and sealed ownership remain identical")
	var vertices:PackedVector3Array=cpu.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX];vertices[0]=Vector3(99,99,99)
	check(after.data.meshes[0].surfaces[0][Mesh.ARRAY_VERTEX][0]==Vector3.ZERO,"job geometry cannot mutate the canonical binary cache")
	check(Binary.read(value.sha256,value.length+1).is_empty(),"wrong source length cannot select a product")
	check(Binary.product_path("../outside").is_empty(),"non-digest product paths are refused")
	Controls.white_materials=false
	check(Binary.read(value.sha256,value.length).is_empty(),"ordinary material route remains independent of this white experiment")
	Controls.white_materials=true;preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
	check(Binary.read(value.sha256,value.length).is_empty(),"explicit source diagnostics bypass derived products")
	preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=false
	var file:=FileAccess.open(built.path,FileAccess.WRITE);file.store_string("partial");file.close();evict(value.sha256)
	check(Binary.read(value.sha256,value.length).is_empty() and House.prepare_cpu(source).collision_faces==old_cpu.collision_faces,"truncated product falls back to the exact source")
	print("PREFAB_BINARY_CACHE checks=",checks," failures=",failures);quit(1 if failures else 0)
