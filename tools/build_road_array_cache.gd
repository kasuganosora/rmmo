extends SceneTree
## Offline conversion of current authored road shapes; never edits map/packs.
const Cache=preload("res://scripts/world3d/road_array_cache.gd")
const Store=preload("res://scripts/world3d/map_resource_store.gd")
const Prepare=preload("res://scripts/world3d/native_road_preparation.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):path=arg.trim_prefix("--map=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var root_path:=preload("res://scripts/world3d/map_paths.gd").external_root()
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	controls.discard_map_textures=true;controls.enable_white_materials()
	var before:=FileAccess.get_sha256(path);var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var sources:Dictionary={};var roads:Dictionary={};var products:Array=[];var failures:Array=[];var total_bytes:=0;var instances:=0;var old_us:=0;var read_us:=0
	for compact:Dictionary in document.nodes[0].extras.rmmo_records:
		if not compact.has("rmmo_ref"):continue
		var source:=path.get_base_dir().path_join(compact.rmmo_ref.uri)
		if not sources.has(source):
			sources[source]=FileAccess.get_sha256(source)
			var bytes:=FileAccess.get_file_as_bytes(source)
			var definition:Dictionary=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
			if definition.has("road_mesh"):roads[source]=true
		if not roads.has(source):continue
		# Match the production hydration/instance type conversion exactly.
		var hydrated:=Store.read_records([compact],path,root_path,null,1,true)
		if not hydrated.ok:failures.append({"reason":"hydrate","uuid":compact.uuid});continue
		var record:Dictionary=hydrated.records[0];var budget:=Prepare.estimate(record,true)
		var began:=Time.get_ticks_usec();var expected:=preload("res://scripts/world3d/road_surface.gd").arrays(record);old_us+=Time.get_ticks_usec()-began
		var built:=Cache.build(record,root_path,compact.rmmo_ref.sha256)
		if not built.ok:failures.append(built);continue
		began=Time.get_ticks_usec();var restored:=Cache.read(record,root_path,budget.output_bytes,compact.rmmo_ref.sha256);read_us+=Time.get_ticks_usec()-began
		if restored.is_empty() or var_to_bytes(restored.arrays)!=var_to_bytes(expected):failures.append({"uuid":record.uuid,"reason":"exact_channels"})
		if restored.get("bounds")!=preload("res://scripts/world3d/procedural_surface_bounds.gd").bounds(expected):failures.append({"uuid":record.uuid,"reason":"exact_bounds"})
		instances+=1;products.append(built);total_bytes+=int(built.bytes)
	for source:String in sources:
		if FileAccess.get_sha256(source)!=sources[source]:failures.append({"source":source,"reason":"source_changed"})
	if FileAccess.get_sha256(path)!=before:failures.append({"reason":"map_changed"})
	var report:Dictionary={"instances":instances,"products":products,"failures":failures,"bytes":total_bytes,"old_generate_us":old_us,"product_read_us":read_us,"map_sha256":before,"source_sha256":sources,"contract":"Exact road/kerb positions, normals, UVs, tangents, surface order; no author changes or texture work"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROAD_ARRAY_BUILD ",JSON.stringify({"instances":instances,"bytes":total_bytes,"old_generate_us":old_us,"product_read_us":read_us,"failures":failures}));quit(1 if not failures.is_empty() else 0)
