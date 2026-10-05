extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var map_path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
	var data:Dictionary=Cache.read(map_path,FileAccess.get_sha256(map_path))
	if data.is_empty():push_error("Validated town metadata cache is required for this read-only benchmark");quit(1);return
	var records:Array=data.rmmo_records.filter(func(r):return r.has("terrain_mesh"))
	var context=preload("res://scripts/world3d/terrain_neighbors.gd").new()
	var start:=Time.get_ticks_usec();context.update(records,"--parallel" in OS.get_cmdline_user_args())
	var neighbor_us:=Time.get_ticks_usec()-start
	var signatures:Dictionary={}
	for id:String in context.data:
		var c:Dictionary=context.data[id]
		signatures[id]=Cache.checksum(var_to_bytes([c.normals,c.padding,c.neighbors,c.image.get_data()])).hex_encode()
	start=Time.get_ticks_usec();var masks:=0
	for record:Dictionary in records:
		if record.has("terrain_regions"):
			var mask:=preload("res://scripts/world3d/terrain_regions.gd").mask(record)
			signatures[record.uuid+"/mask"]=Cache.checksum(mask.get_data()).hex_encode();masks+=1
	var report:={"neighbor_us":neighbor_us,"masks_serial_us":Time.get_ticks_usec()-start,"terrain_count":records.size(),"mask_count":masks,"signatures":signatures}
	var out:="";var baseline:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		if arg.begins_with("--baseline="):baseline=arg.trim_prefix("--baseline=")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out.get_base_dir());FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	var matched:=true
	if not baseline.is_empty():
		var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(baseline));matched=previous.signatures==signatures
	print("TERRAIN_CONTEXT_BENCHMARK ",JSON.stringify({"neighbor_ms":neighbor_us/1000.,"masks_serial_ms":report.masks_serial_us/1000.,"terrain_count":records.size(),"mask_count":masks,"matches_baseline":matched}))
	quit(0 if matched else 1)
