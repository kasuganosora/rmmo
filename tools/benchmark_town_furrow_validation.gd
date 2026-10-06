extends SceneTree
const Cache=preload("res://scripts/world3d/map_metadata_cache.gd")
const Furrows=preload("res://scripts/world3d/terrain_furrows.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	var meta:=Cache.read(path,FileAccess.get_sha256(path));var results:={};var elapsed:=0
	for record:Dictionary in meta.rmmo_records:
		if Furrows.maximum_height(record)<=0:continue
		var start:=Time.get_ticks_usec();var result:=Furrows._generate(record);elapsed+=Time.get_ticks_usec()-start
		results[record.uuid]=Cache.checksum(var_to_bytes(result)).hex_encode()
	var report:={"elapsed_us":elapsed,"patches":results.size(),"results":results};var exact:=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):
			var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--baseline=")))
			exact=baseline.results==results;report.matches_baseline=exact
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"))
	print("FURROW_VALIDATION_BENCHMARK ",JSON.stringify({"elapsed_us":elapsed,"patches":results.size(),"exact":exact}));quit(0 if exact else 1)
