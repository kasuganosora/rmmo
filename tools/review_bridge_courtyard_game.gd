extends "res://tools/test_medieval_town_houses.gd"
const Fix=preload("res://tools/correct_bridge_spire_courtyard.gd")
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900);output_directory=Fix.FIX_OUT
	if "--setback" in OS.get_cmdline_user_args():output_directory=preload("res://tools/setback_bridge_courtyard.gd").SET_OUT
	if "--residential" in OS.get_cmdline_user_args():output_directory="D:/code/rmmo_runtime/review_artifacts/bridge_residential_street_20261007"
	if "--lamps" in OS.get_cmdline_user_args():output_directory="D:/code/rmmo_runtime/review_artifacts/bridge_residential_lamps_20261007"
	if "--complete" in OS.get_cmdline_user_args():output_directory="D:/code/rmmo_runtime/review_artifacts/bridge_residential_complete_20261007"
	var published:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/published.json"))
	check(published.failures==0 and published.sha256==FileAccess.get_sha256(Fix.FORMAL),"published map matches reviewed correction")
	var plan:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/plan.json"))
	var h:Dictionary=plan.metadata.building_instances[Fix.HOUSE];var at:=B.vec(h.position);var basis:=Basis(Vector3.UP,deg_to_rad(h.yaw))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=Fix.FORMAL;session.world3d_spawn=at+basis*Vector3(plan.gate_x,.9,-12)
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(Fix.FORMAL)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"native game loader")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	world._request_environment({"time_hours":12.,"time_speed":0.})
	var outside:=at+basis*Vector3(plan.gate_x,.025,-18 if plan.get("setback_m",0)>0 else -12)
	var threshold:=at+basis*Vector3(plan.gate_x,.025,-7.9)
	await teleport(outside)
	await walk(threshold,"walk through exterior courtyard gate")
	await walk(outside,"return through exterior courtyard gate")
	if plan.has("new_home"):
		var home:Dictionary=plan.metadata.building_instances[plan.new_home];var hb:=Basis(Vector3.UP,deg_to_rad(home.yaw));var hp:=B.vec(home.position)
		var riverside:=Vector3(293,.025,192)
		var front:=hp+hb*Vector3(-home.parameters.width/2+1.2,.025,-home.parameters.depth/2-1.2)
		await teleport(riverside);await walk(front,"riverside path to new house exterior doorstep")
		await walk(riverside,"new house exterior doorstep to riverside path");await teleport(outside)
	world._player.hide();world._camera.camera.fov=60
	world._weather.wind_objects.refresh()
	for tree:Dictionary in plan.props.filter(func(p):return p.source=="tree"):
		check(world._weather.wind_objects.receivers.values().any(func(r):return r.node.get_ref()!=null and str(r.node.get_ref().name).begins_with(tree.id+"__")),"courtyard tree retains wind "+tree.id)
	var bridge:Dictionary=plan.records.filter(func(r):return r.uuid==plan.bridge_id)[0]
	var center:=B.vec(bridge.position);var bb:=Basis(Vector3.UP,deg_to_rad(bridge.rotation[1]))
	var resident:Dictionary=world._map_root.get_meta("stream_meshes")
	check(resident.keys().filter(func(id):return str(id).begins_with(Fix.SPIRE+"__")).size()==6,"moved distant spire complete in game")
	await capture("game_bridge",center+bb*Vector3(4,5.2,12),center+bb*Vector3(53,4,0))
	await capture("game_courtyard",Vector3(304,7,164),Vector3(323,1,157))
	await capture("game_courtyard_back",Vector3(336,9,137),Vector3(326,1,154))
	if plan.has("new_home"):
		var home:Dictionary=plan.metadata.building_instances[plan.new_home];var hb:=Basis(Vector3.UP,deg_to_rad(home.yaw));var hp:=B.vec(home.position)
		await capture("game_infill_home",hp+hb*Vector3(-2,4,-17),hp+hb*Vector3(0,2,-4))
	world._weather.streetlamps.refresh()
	check(world._weather.streetlamps.fixtures.values().all(func(r):return not r.lit),"relocated lamps off by day")
	var batcher=world._map_root.get_node_or_null("GroundRenderBatches")
	var batching:Dictionary=batcher.stats() if batcher!=null else {}
	check(not batching.is_empty() and batching.source_surfaces>batching.render_surfaces,"native automatic batches reduce actual submitted surfaces")
	world._request_environment({"time_hours":22.,"time_speed":0.});world._weather.streetlamps.refresh()
	var visible:=0;var lit:=0
	for lamp:Dictionary in world._weather.streetlamps.fixtures.values():
		if lamp.get("warm",false) and lamp.node.get_ref().is_visible_in_tree():
			visible+=1
			if lamp.lit and lamp.light.visible:lit+=1
	check(visible>0 and lit==visible,"visible door lamps illuminate at night: "+str(lit)+"/"+str(visible))
	await capture("game_bridge_night",center+bb*Vector3(4,5.2,12),center+bb*Vector3(53,4,0))
	FileAccess.open(output_directory+"/game_result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"formal_sha256":FileAccess.get_sha256(Fix.FORMAL),"interior_tests":"omitted at user request","batching":batching,"night_door_lamps":lit},"\t"))
	print("COURTYARD_GAME failures=",failures);world.free();quit(failures)
