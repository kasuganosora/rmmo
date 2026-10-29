extends "res://tools/test_transfer_experience_http.gd"
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
var held:Array[Node]=[]
var first:=true
var stopped_wind:=false
func run()->void:
	directory="D:/code/rmmo_runtime/review_artifacts/wind_cutout_20261018"
	var callback:=func(node:Node):
		if first and node.get_script()==Navigation:
			node.process_mode=Node.PROCESS_MODE_DISABLED;held.append(node)
	node_added.connect(callback)
	preload("res://scripts/world3d/world_3d.gd").wind_background_enabled=true
	await super.run()
func trigger(id:String,destination:Vector3)->void:
	var state:Dictionary=await call_tool("playtest_state")
	check(state.preparation.policy.mode=="staged" and state.preparation.playable,"real HTTP publishes automatically selected playable policy")
	if first:
		check(not state.preparation.navigation.ready and state.preparation.navigation.state=="preparing","HTTP never equates keyboard readiness with navigation readiness")
		var world:Node=editor._playtest.world;world._preparation_sample_at=0;world._update_preparation_hint()
		check(world._preparation_hint.visible,"UI and HTTP expose the same pending capability")
		var blocked:bool=world._player.geometry_blocked;world._player.geometry_blocked=true;world._preparation_sample_at=0;world._update_preparation_hint()
		check(not world._preparation_hint.text.contains("可用键盘移动"),"UI does not promise movement while physical preparation blocks it")
		world._player.geometry_blocked=blocked
		var wind:Node3D=world._weather.wind_objects
		var receiver:=MeshInstance3D.new();var mesh:=PlaneMesh.new();var material:=StandardMaterial3D.new()
		material.texture_repeat=false;material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST;material.cull_mode=BaseMaterial3D.CULL_DISABLED
		mesh.material=material;receiver.mesh=mesh;receiver.position=world._player.global_position+Vector3(2,1,0)
		receiver.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}});world.add_child(receiver)
		preload("res://scripts/world3d/wind_response.gd").register(receiver);wind.refresh()
		var start:Vector3=world._player.global_position
		state=await call_tool("playtest_state")
		check(not state.preparation.wind.ready and state.preparation.wind.pending_receivers==1,"real HTTP exposes newly streamed wind material as pending")
		var until:=Time.get_ticks_msec()+60000
		while not world.has_meta("wind_recovery_profile") and Time.get_ticks_msec()<until:await process_frame
		state=await call_tool("playtest_state")
		check(state.preparation.wind.ready and state.preparation.wind.last_recovery.cold_variants==1,"real production world automatically completes pending wind after a drawn cover")
		var receipt:Dictionary=world.get_meta("wind_recovery_profile",{})
		check(receipt.get("ok",false) and receipt.get("phase")=="revealed" and int(receipt.get("drawn_frame",-1))>=0,"wind recovery records actual opaque draw and first-frame reveal")
		check(not world._player.input_locked and not world._transfer_pending and world._player.global_position.distance_to(start)<.15,"wind recovery restores gameplay at the original position")
		check(receiver.get_active_material(0) is ShaderMaterial,"streamed receiver actually uses the prepared wind shader")
		receiver.free()
		first=false
		for nav:Node in held:nav.process_mode=Node.PROCESS_MODE_INHERIT
		held.clear()
		var deadline:=Time.get_ticks_msec()+60000
		while not world._navigation.ready_for_queries and Time.get_ticks_msec()<deadline:await process_frame
		state=await call_tool("playtest_state");check(state.preparation.navigation.ready,"HTTP observes actual background navigation completion")
	await super.trigger(id,destination)
	if not stopped_wind:
		stopped_wind=true
		var world:Node=editor._playtest.world;var viewport:SubViewport=editor._playtest.viewport
		var node:=MeshInstance3D.new();var mesh:=PlaneMesh.new();var material:=StandardMaterial3D.new()
		material.texture_repeat=false;material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR;material.cull_mode=BaseMaterial3D.CULL_FRONT
		mesh.material=material;node.mesh=mesh;node.position=world._player.global_position+Vector3(2,1,0);node.set_meta("extras",{"rmmo_wind":{"profile":"foliage","shelter":false}})
		world.add_child(node);preload("res://scripts/world3d/wind_response.gd").register(node);world._weather.wind_objects.refresh()
		world._preparation_sample_at=0;world._update_preparation_hint()
		var until:=Time.get_ticks_msec()+5000
		while not world._transfer_pending and Time.get_ticks_msec()<until:await process_frame
		check(world._wind_recovery_pending and world._transfer_pending and world._player.input_locked,"wind stop probe reaches actual guarded production recovery")
		await call_tool("stop_playtest");await wait_phase("idle")
		check(not is_instance_valid(world) and not is_instance_valid(viewport),"stopping wind cover destroys its coroutine owner and private viewport safely")
		await call_tool("start_playtest");await wait_phase("running")
