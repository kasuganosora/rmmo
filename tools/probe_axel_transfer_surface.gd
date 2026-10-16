extends "res://tools/review_axel_town_fortifications.gd"
## Read-only diagnosis: compare authored surface with a small standing clearance.
func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output="D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016/transfer_surface_probe"
	DirAccess.make_dir_recursive_absolute(output)
	report={"phase":"metadata","checks":[],"screenshots":[],"probes":[],"map_path":map_path,"map_sha256":FileAccess.get_sha256(map_path)}
	create_timer(600).timeout.connect(func():
		if not finished:check(false,"probe timeout");finish(2))
	if not check(DisplayServer.get_name()!="headless","actual background runtime required"):finish();return
	document=Document.open_file(map_path)
	if not check(document!=null,"native candidate opens read-only"):finish();return
	for r:Dictionary in document.records:records[r.uuid]=r
	Engine.max_fps=60;root.size=Vector2i(1200,800)
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"production loader"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"loading error",{"error":world.get_meta("entry_loading_error")});finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	for xz:Array in [[329.,45.701754386],[156.,209.],[234.306107,54.042273]]:
		var point:=terrain_point(Vector3(xz[0],0,xz[1]));var row:={"terrain_feet":xyz(point),"attempts":[]}
		for clearance:float in [0.,.04]:
			var at:=point+Vector3.UP*clearance;var ok:bool=await world.transfer_map(map_path,at+Vector3.UP*.9)
			for tick in 12:await physics_frame
			row.attempts.append({"clearance":clearance,"ok":ok,"transfer":world.get_meta("transfer_loading_profile",{}),"surface":ray_surface(at,1.,2.),"settled_feet":xyz(feet()),"support":support(feet(),.8,.3)})
		report.probes.append(row);save_report()
	check(FileAccess.get_sha256(map_path)==report.map_sha256,"map unchanged")
	report.phase="complete";finish()
