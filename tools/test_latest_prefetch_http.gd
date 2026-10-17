extends "res://tools/test_transfer_experience_http.gd"
## Current UI + real loopback HTTP save/reopen and confirmed transfer integration.
func run()->void:
	directory=Paths.cache_directory("latest_prefetch_http_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	evidence.gpu=[]
	await super.run()
func trigger(id:String,destination:Vector3)->void:
	var world:Node=editor._playtest.world
	var target:String=Net.server().world3d_events.targets[id].template.parameters.map_path
	if is_instance_valid(Net.session().editor_playtest):target=Net.session().editor_playtest.resolve_map(target)
	var cross:bool=not world._same_map_target(target)
	var hits:=0
	if cross:
		world._update_approach_preparation()
		var deadline:=Time.get_ticks_msec()+60000
		while not world._target_scene_prefetch._gpu_ready and Time.get_ticks_msec()<deadline:await process_frame
		var service:Node=world._target_scene_prefetch
		check(service._gpu_ready,"real authored transfer prepares a verified private GPU target")
		check(service._viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"ready target stops drawing while source playtest remains active")
		check(not world._transfer_pending and not world._player.input_locked and not world.get_viewport().disable_3d,"source remains visible and playable while ready target is parked")
		hits=service.profile.hits
	await super.trigger(id,destination)
	if cross:
		check(world._map_root.get_meta("gpu_preload_hit",false) and world._target_scene_prefetch.profile.hits==hits+1,"confirmed HTTP-authored transfer consumes the parked GPU target")
		check(not world._map_root.has_meta("prefetched_gpu_owners") and world._target_scene_prefetch._ledger==null,"target adoption releases the preload lease after the actual target frame")
		evidence.gpu.append(world._target_scene_prefetch.profile.duplicate())
