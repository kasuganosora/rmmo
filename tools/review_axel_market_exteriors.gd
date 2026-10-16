extends "res://tools/review_axel_town_houses.gd"
## Six new exterior entrances only. Run via run_godot_background.py.
## Full candidate and source receipt are pinned; no scene or model is saved.
const MARKET_OUT="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016"
const IMAGE_PREP="C:/Users/luna/.codex/skills/rmmo-model-review/scripts/prepare_review_image.py"
const PYTHON="C:/Users/luna/AppData/Local/Programs/Python/Python312/python.exe"
var expected_map_sha:=""
var expected_build_sha:=""
var capture_directory:=""
var capture_fov:=58.0

func layout_view_anchor(target:Vector3)->Dictionary:
	# Ordinary stalls/foliage use near-player streaming, unlike whole houses.
	# Prepare the view through a real nearby road arrival before moving the camera.
	var graph:Dictionary=City.resolve(document.map_meta).roads;var analysis:Dictionary=City.analyze(graph)
	if not analysis.ok:return analysis
	var nearest:=Vector3.ZERO;var distance_squared:=INF;var edge_id:=""
	for edge:Dictionary in graph.edges:
		if edge.kind!="ground" or minf(edge.width_start,edge.width_end)<2.4:continue
		var points:Array=analysis.paths[edge.id]
		for index in points.size()-1:
			var a:=Vector2(points[index].x,points[index].z);var b:=Vector2(points[index+1].x,points[index+1].z)
			var query:=Vector2(target.x,target.z);var delta:=b-a
			var fraction:=clampf((query-a).dot(delta)/delta.length_squared(),0.,1.) if delta.length_squared()>.000001 else 0.
			var point:=a.lerp(b,fraction);var distance:=point.distance_squared_to(query)
			if distance<distance_squared:nearest=Vector3(point.x,0,point.y);distance_squared=distance;edge_id=edge.id
	if edge_id.is_empty():return {"ok":false,"error":"No native ground road near layout view"}
	nearest=ground_point(nearest)
	return {"ok":is_finite(nearest.y) and distance_squared<=3600.,"position":xyz(nearest),"edge_id":edge_id,"distance_m":sqrt(distance_squared)}

func capture(label:String,eye:Vector3,target:Vector3)->void:
	await await_visual_residency(label)
	var model:Node3D=world._player.get_node("CharacterModel3D");var visible_before:=model.visible;var processing_before:bool=world.is_processing()
	var camera:Camera3D=world._camera.camera;var pose:=camera.global_transform;var fov:=camera.fov;var layers:Array=[]
	for child in world.get_children():
		if child is CanvasLayer:layers.append([child,child.visible]);child.hide()
	world.set_process(false);camera.global_position=eye;camera.look_at(target);camera.fov=capture_fov;model.hide()
	for tick in 10:await process_frame
	await RenderingServer.frame_post_draw
	var img:=camera.get_viewport().get_texture().get_image();var raw:=capture_directory.path_join(label+".png");var error:=img.save_png(raw)
	camera.global_transform=pose;camera.fov=fov;world.set_process(processing_before);model.visible=visible_before
	for layer:Array in layers:layer[0].visible=layer[1]
	check(error==OK,"outdoor source image captured "+label)
	check(not world._player.get_node("CollisionShape3D").disabled and model.visible==visible_before,"capture restores actor rendering and collision "+label)
	if error!=OK:return
	var stdout:Array=[];var code:=OS.execute(PYTHON,PackedStringArray([IMAGE_PREP,raw]),stdout,true,false);var receipt:Dictionary={}
	if code==0:
		for line:String in "\n".join(stdout).split("\n"):
			if line.strip_edges().is_empty():continue
			var parsed:Variant=JSON.parse_string(line)
			if parsed is Dictionary and parsed.has("path"):receipt=parsed
	var good:bool=code==0 and receipt.get("quality",0)==90 and receipt.get("lossless",true)==false and FileAccess.get_sha256(receipt.get("path",""))==receipt.get("sha256","")
	check(good,"skill quality90 WebP SHA receipt "+label,{"encoder_exit":code})
	if good:report.screenshots.append({"id":label,"path":receipt.path,"sha256":receipt.sha256,"dimensions":receipt.dimensions,"quality":90,"lossless":false,"eye":xyz(eye),"target":xyz(target),"fov_vertical":capture_fov,"receipt":receipt})

func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output=MARKET_OUT+"/market_exterior_runtime";build_path=MARKET_OUT+"/market_build.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=").replace("\\","/").simplify_path()
		elif arg.begins_with("--out="):output=arg.trim_prefix("--out=").replace("\\","/").simplify_path()
		elif arg.begins_with("--build="):build_path=arg.trim_prefix("--build=").replace("\\","/").simplify_path()
		elif arg.begins_with("--expected-map-sha="):expected_map_sha=arg.trim_prefix("--expected-map-sha=")
		elif arg.begins_with("--expected-build-sha="):expected_build_sha=arg.trim_prefix("--expected-build-sha=")
	report={"scope":"Only six new market/street house exterior doorsteps, two new commercial entrance paths, and three market layout views","not_tested":["old 21 houses","house interiors","indoor fixtures","old bridges","whole-town performance","shop trading"],"checks":[],"screenshots":[],"houses":[],"routes":[],"map_path":map_path,"phase":"metadata"}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	create_timer(1000).timeout.connect(func():
		if not finished:check(false,"market exterior review timeout",{"phase":report.phase});finish(2))
	if not check(DisplayServer.get_name()!="headless","actual renderer required") or not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path),"saved final candidate exists"):finish();return
	if not check(Paths.allowed(build_path) and FileAccess.file_exists(build_path),"native market receipt exists"):finish();return
	report.map_sha256=FileAccess.get_sha256(map_path);report.build_sha256=FileAccess.get_sha256(build_path)
	if not check(not expected_map_sha.is_empty() and report.map_sha256==expected_map_sha,"exact final candidate SHA") or not check(not expected_build_sha.is_empty() and report.build_sha256==expected_build_sha,"exact source market build SHA"):finish();return
	build_receipt=JSON.parse_string(FileAccess.get_file_as_string(build_path))
	if not check(build_receipt.get("phase")=="native_market_complete_review_pending" and build_receipt.get("saved",false) and int(build_receipt.get("failures",-1))==0,"successful native market receipt"):finish();return
	document=Document.open_file(map_path)
	if not check(document!=null,"final candidate opens read-only"):finish();return
	for record:Dictionary in document.records:records[str(record.uuid)]=record
	terrain_records=document.records.filter(func(r):return r.has("terrain_mesh"))
	var content:Dictionary=build_receipt.get("content",{});var houses:Array=content.get("houses",[])
	if not check(houses.size()==6,"exact six new native house placements"):finish();return
	if not check(City.token(document.map_meta.get("town_reference",{}).get("market_functional_layout",{}).get("houses",[]))==City.token(houses),"final candidate preserves recorded market house identities"):finish();return
	if not check(City.analyze(City.resolve(document.map_meta).roads).ok,"saved final road graph remains natively valid"):finish();return
	house_recipe={"houses":[]}
	for h:Dictionary in houses:
		var native:Dictionary=document.map_meta.get("building_instances",{}).get(str(h.building_id),{})
		check(not native.is_empty() and City.token(native.get("parameters",{}))==City.token(h.parameters),"native saved house identity and parameters "+str(h.id))
		var members:Array=document.records.filter(func(r):return r.get("building",{}).get("id","")==str(h.building_id))
		check(members.size()==h.component_ids.size() and members.all(func(r):return r.uuid in h.component_ids),"native complete frozen house membership "+str(h.id))
		if h.id in ["commercial_apothecary","commercial_general"]:
			house_recipe.houses.append({"id":h.id,"access_points":[[h.access_tip[0],h.access_tip[2]],[195,h.access_tip[2]]]})
	var stalls:Array=content.get("props",[]).filter(func(p):return str(p.key).begins_with("market/stall/"))
	check(stalls.size()==4,"exact four reduced-budget market stalls")
	for prop:Dictionary in stalls:
		var native:Dictionary=records.get(str(prop.id),{})
		check(not native.is_empty() and native.get("asset_path","")==prop.asset_path and FileAccess.get_sha256(prop.asset_path)==prop.asset_sha256,"saved stall source identity "+str(prop.key))
	if failures:finish();return
	capture_directory=output.path_join("images_"+expected_map_sha.left(12)+"_"+str(Time.get_unix_time_from_system()).replace(".","_"))
	if not check(DirAccess.make_dir_recursive_absolute(capture_directory)==OK,"fresh review image directory"):finish();return
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading"
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"runtime loading failed",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	check(canonical_path(world._map_path)==canonical_path(map_path),"runtime loaded exact final candidate")
	for h:Dictionary in houses:await audit_house(h)
	for h:Dictionary in houses:
		if h.id in ["commercial_apothecary","commercial_general"]:await audit_access(h)
	for camera:Dictionary in content.get("metadata",{}).get("cameras",[]):
		var anchor:=layout_view_anchor(vector(camera.target))
		if not check(anchor.ok,"native road anchor for streamed layout view "+str(camera.id),anchor):continue
		if not await relocate(vector(anchor.position)+Vector3.UP*.04,"layout view "+str(camera.id)):continue
		capture_fov=float(camera.get("fov",58));await capture(str(camera.id),vector(camera.position),vector(camera.target))
	check(report.houses.size()==6 and report.routes.size()==2,"six outdoor doorways and two new paths reviewed")
	check(report.screenshots.size()==5,"two doorway and three locally streamed layout views captured")
	check(FileAccess.get_sha256(map_path)==expected_map_sha and FileAccess.get_sha256(build_path)==expected_build_sha,"review leaves pinned map and build receipt unchanged")
	report.phase="complete";finish()
