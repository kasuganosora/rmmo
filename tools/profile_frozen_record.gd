extends SceneTree
const Prefab=preload("res://scripts/world3d/house_prefab.gd")
const SOURCE="D:/code/rmmo_runtime/cache/world3d/bridge_perf_20261006/map.gltf"
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var uuid:String=args[0];var output:String=args[1]
	var parsed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE));var record:Dictionary={}
	for node in parsed.nodes:
		for candidate in node.get("extras",{}).get("rmmo_records",[]):
			if candidate.uuid==uuid:record=candidate;break
	if record.is_empty() or not Prefab.valid(record):quit(1);return
	var preparation:Dictionary={};var scope:Dictionary={}
	if args.has("--prepared-textures"):
		var helper=preload("res://scripts/world_editor/terrain_texture_preparation.gd")
		var worker:=Thread.new();var mark:=Time.get_ticks_usec();var frames:=0
		worker.start(helper.decode.bind(helper.requests(record,{}),preload("res://scripts/world3d/map_paths.gd").external_root()))
		while worker.is_alive():await process_frame;frames+=1
		var payload:Dictionary=worker.wait_to_finish()
		preparation={"wait_ms":(Time.get_ticks_usec()-mark)/1000.,"worker_ms":payload.elapsed_us/1000.,"frames":frames,"images":payload.images.size()}
		scope=helper.install(payload)
	var timings:Dictionary={};var mark:=Time.get_ticks_usec()
	var visual:MeshInstance3D=Prefab.visual(record,true,{}, {},timings)
	timings.total_ms=(Time.get_ticks_usec()-mark)/1000.
	if args.has("--prepared-textures"):preload("res://scripts/world_editor/terrain_texture_preparation.gd").restore(scope)
	var result:={"uuid":uuid,"validated_decode":true,"decoded_bytes":record.house_prefab.length,"timings":timings,"preparation":preparation,"surfaces":visual.mesh.get_surface_count()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("FROZEN_RECORD_PROFILE ",JSON.stringify(result))
	visual.free();quit(0)
