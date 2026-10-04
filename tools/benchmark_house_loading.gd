extends SceneTree
var MAP="D:/code/rmmo_runtime/maps/medieval_house_showcase/map.gltf"
const Stream=preload("res://scripts/world3d/world_stream.gd")
var stages: Dictionary={}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):MAP=arg.trim_prefix("--map=")
	Engine.max_fps=60
	var started:=Time.get_ticks_msec()
	var loader=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader)
	loader.progress.connect(func(stage,done,total):
		if not stages.has(stage): stages[stage]=Time.get_ticks_msec()-started; print("STAGE ",stage," at ",stages[stage])
		if done==total: print("INDEX_FINISHED ",Time.get_ticks_msec()-started))
	loader.start(MAP); var loaded: Array=await loader.finished
	if loaded[0]==null: push_error(loaded[2]); quit(1); return
	var indexed:=Time.get_ticks_msec(); var scene: Node=loaded[0]
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene)
	var frames:=0; var max_sync:=0.0
	while not scene.has_meta("stream_chunk"):
		var mark:=Time.get_ticks_usec()
		Stream.sync(scene,host,Vector3(0,.95,-53),Stream.LOAD_BUDGET)
		max_sync=maxf(max_sync,(Time.get_ticks_usec()-mark)/1000.)
		frames+=1; await process_frame
	var streamed:=Time.get_ticks_msec(); print("STREAM_FINISHED ",streamed-indexed," frames=",frames," max_sync_ms=",max_sync)
	var nav=preload("res://scripts/world3d/world_navigation.gd").new(); host.add_child(nav); nav.build(scene.get_meta("stream_library"),Vector3(0,.95,-53))
	while not nav.ready_for_queries: await process_frame
	var ready:=Time.get_ticks_msec()
	var batches:Node=scene.get_node("GroundRenderBatches")
	while batches.stats().pending_groups>0:await process_frame
	var result:={"load_ms":indexed-started,"stream_ms":streamed-indexed,"navigation_ms":ready-streamed,"total_ms":ready-started,"stream_frames":frames,"max_sync_ms":max_sync,"stages":stages,"shared_box_hits":scene.get_meta("load_box_cache_hits",0),"building_batches":batches.stats("building"),"collision_bodies":scene.get_meta("stream_bodies",{}).size()}
	print("HOUSE_LOADING_BENCHMARK ",JSON.stringify(result))
	print("HOUSE_LOAD_PROFILE ",JSON.stringify(scene.get_meta("load_profile",{})))
	var label:="baseline"
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):label=arg.validate_filename();break
	var file:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/house_playground/loading_"+label+".json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	host.free(); quit()
