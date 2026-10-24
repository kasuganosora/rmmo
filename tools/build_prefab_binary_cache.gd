extends SceneTree
## Read-only source conversion and exact data/key roundtrip audit.
const Binary=preload("res://scripts/world3d/prefab_binary_cache.gd")
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	Binary.configure(preload("res://scripts/world3d/map_paths.gd").external_root())
	var before:=FileAccess.get_sha256(path);var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var seen:Dictionary={};var sources:Dictionary={};var products:Array=[];var failures:Array=[];var total_bytes:=0;var old_us:=0;var new_us:=0
	for record:Dictionary in document.nodes[0].extras.rmmo_records:
		if not record.has("rmmo_ref"):continue
		var source:=path.get_base_dir().path_join(record.rmmo_ref.uri)
		if sources.has(source):continue
		sources[source]=FileAccess.get_sha256(source)
		var bytes:=FileAccess.get_file_as_bytes(source)
		var definition:Dictionary=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
		if not definition.has("house_prefab") or seen.has(definition.house_prefab.sha256):continue
		var value:Dictionary=definition.house_prefab;seen[value.sha256]=true
		Binary.enabled=false;var began:=Time.get_ticks_usec();var expected:=House._decode_uncached(value.data,value.sha256,value.length,false);old_us+=Time.get_ticks_usec()-began
		Binary.enabled=true;var built:=Binary.build(value)
		if not built.ok:failures.append(built);continue
		began=Time.get_ticks_usec();var restored:=House._decode_uncached(value.data,value.sha256,value.length,false);new_us+=Time.get_ticks_usec()-began
		if restored.is_empty() or var_to_bytes(expected.data)!=var_to_bytes(restored.data) or expected.geometry_keys!=restored.geometry_keys or expected.local_bounds!=restored.local_bounds:failures.append({"sha256":value.sha256,"reason":"roundtrip"})
		for i:int in expected.data.meshes.size():
			var oracle:=Cpu.new();oracle.surfaces=expected.data.meshes[i].surfaces
			if oracle.collision_faces()!=restored.collision_faces[i]:failures.append({"sha256":value.sha256,"reason":"collision_roundtrip"})
		products.append(built);total_bytes+=int(built.bytes)
	for source:String in sources:
		if FileAccess.get_sha256(source)!=sources[source]:failures.append({"source":source,"reason":"source_changed"})
	if FileAccess.get_sha256(path)!=before:failures.append({"reason":"map_changed"})
	var report:Dictionary={"products":products,"failures":failures,"bytes":total_bytes,"old_decode_us":old_us,"binary_decode_us":new_us,"map_sha256":before,"source_sha256":sources,"scope":"Exact object-free geometry/material descriptors; white-only derived cache, no authored data changes or GPU quality claim"}
	if not output.is_empty():var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("PREFAB_BINARY_BUILD ",JSON.stringify({"products":products.size(),"bytes":total_bytes,"old_us":old_us,"new_us":new_us,"failures":failures}));quit(0 if failures.is_empty() else 1)
