extends SceneTree
## Read-only CPU attribution of real frozen definitions; no model/GPU import.
const House=preload("res://scripts/world3d/house_prefab.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var before:=FileAccess.get_sha256(MAP)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var seen:Dictionary={};var sources:Dictionary={};var rows:Array=[];var totals:Dictionary={}
	for record:Dictionary in document.nodes[0].extras.rmmo_records:
		if not record.has("rmmo_ref"):continue
		var path:=MAP.get_base_dir().path_join(record.rmmo_ref.uri)
		if sources.has(path):continue
		var bytes:=FileAccess.get_file_as_bytes(path);sources[path]=true
		var definition:Dictionary=bytes_to_var(bytes.slice(16).decompress(bytes.decode_u64(8),FileAccess.COMPRESSION_ZSTD))
		if not definition.has("house_prefab") or seen.has(definition.house_prefab.sha256):continue
		var value:Dictionary=definition.house_prefab;seen[value.sha256]=true
		var row:Dictionary={"sha":value.sha256,"raw_bytes":value.length}
		var began:=Time.get_ticks_usec();var compressed:=Marshalls.base64_to_raw(value.data)
		row.base64_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		var raw:=compressed.decompress(value.length,FileAccess.COMPRESSION_ZSTD)
		row.decompress_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		var data:Dictionary=bytes_to_var(raw)
		row.variant_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		House._seal_owned_containers(data)
		row.seal_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		var keys:Array=[]
		for mesh:Dictionary in data.meshes:keys.append(Cpu.geometry_signature(mesh.surfaces,mesh.get("lods",[])))
		row.geometry_key_us=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		House._stored_local_bounds(data)
		row.bounds_us=Time.get_ticks_usec()-began;row.meshes=data.meshes.size()
		rows.append(row)
		for key:String in row:
			if key.ends_with("_us"):totals[key]=int(totals.get(key,0))+int(row[key])
	var report:Dictionary={"rows":rows,"totals":totals,"unique_definitions":seen.size(),"map_unchanged":FileAccess.get_sha256(MAP)==before}
	if not output.is_empty():var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("PREFAB_DECODE_PHASES ",JSON.stringify({"totals":totals,"unique_definitions":seen.size(),"map_unchanged":report.map_unchanged}))
	quit(0 if report.map_unchanged else 1)
