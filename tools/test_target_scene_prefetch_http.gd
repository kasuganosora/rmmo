extends "res://tools/test_transfer_experience_http.gd"
func run()->void:
	directory="D:/code/rmmo_runtime/review_artifacts/runtime_completion_20261017/transfer_http";evidence.gpu=[]
	await super.run()
func trigger(id:String,destination:Vector3)->void:
	var world:Node=editor._playtest.world
	check(editor._event_panel.transfer_hint.text.contains("预加载"),"UI documents automatic GPU preparation alongside shared transfer behavior")
	var target:String=Net.server().world3d_events.targets[id].template.parameters.map_path
	if is_instance_valid(Net.session().editor_playtest):target=Net.session().editor_playtest.resolve_map(target)
	var cross:bool=not world._same_map_target(target);var hits:=0
	if cross:
		world._update_approach_preparation();var deadline:=Time.get_ticks_msec()+60000
		while not world._target_scene_prefetch._gpu_ready and Time.get_ticks_msec()<deadline:await process_frame
		check(world._target_scene_prefetch._gpu_ready,"saved UI/MCP event automatically prepares target GPU resources before trigger")
		check(not world._transfer_pending and not world._player.input_locked and not world.get_viewport().disable_3d,"source remains visible and playable throughout GPU preload")
		hits=world._target_scene_prefetch.profile.hits
	await super.trigger(id,destination)
	if cross:
		check(world._map_root.get_meta("gpu_preload_hit",false) and world._target_scene_prefetch.profile.hits==hits+1,"real confirmed cross-map transfer consumes GPU-ready target")
		check(not world._map_root.has_meta("prefetched_gpu_owners") and world._target_scene_prefetch._ledger==null,"target draw takes ownership without a map-lifetime preload pin")
		evidence.gpu.append(world._target_scene_prefetch.profile.duplicate())
