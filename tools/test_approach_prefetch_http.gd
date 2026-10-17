extends "res://tools/test_transfer_experience_http.gd"
## Real UI form + loopback 3D MCP + saved events + runtime transfer handoff.
func run()->void:
	directory="D:/code/rmmo_runtime/review_artifacts/editor_runtime_followup_20261017/transfer_http"
	evidence.prefetch=[]
	await super.run()
func trigger(id:String,destination:Vector3)->void:
	var world:Node=editor._playtest.world
	var spec:Dictionary=Net.server().world3d_events.targets[id]
	var target:String=spec.template.parameters.map_path
	if is_instance_valid(Net.session().editor_playtest):target=Net.session().editor_playtest.resolve_map(target)
	var cross:bool=not world._same_map_target(target)
	var hits:=0
	if cross:
		var source:Node=world._map_root;var position:Vector3=world._player.global_position
		world._update_approach_preparation()
		var service:Node=world._cross_map_prefetch
		var deadline:=Time.get_ticks_msec()+30000
		while service._packet==null and Time.get_ticks_msec()<deadline:await process_frame
		check(service._packet!=null,"approaching saved UI/MCP transfer automatically prepares native target")
		check(world._map_root==source and not world._transfer_pending and not world._player.input_locked and world._player.global_position.distance_to(position)<.05,"preparation preserves source world, physics and playable input")
		if service._packet!=null:
			check(service._packet.restored.read_profile.threads_started==0,"speculative hydration uses its one admitted worker with no nested reader threads")
		hits=service.profile.hits
	await super.trigger(id,destination)
	if cross:
		check(editor._event_panel.transfer_hint.text.contains("预读"),"UI explains automatic approach preparation")
		var discovery:=await rpc("tools/list");var documented:=false
		for tool:Dictionary in discovery.result.tools:
			if tool.name=="create_event_template":documented=str(tool.description).contains("预读")
		check(documented,"real current 3D MCP discovery explains the same preparation")
		var profile:Dictionary=world._map_root.get_meta("load_profile",{})
		check(world._cross_map_prefetch.profile.hits==hits+1 and profile.get("source_prefetch_hit",false) and profile.get("hydration_prefetch_hit",false),"confirmed real cross-map transfer consumes speculative snapshot and hydration")
		check(world._cross_map_prefetch._ledger==null and world._cross_map_prefetch._thread==null,"real handoff retires all speculative lease and worker ownership")
		evidence.prefetch.append({"service":world._cross_map_prefetch.profile.duplicate(),"load":profile})
