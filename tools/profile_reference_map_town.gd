extends "res://tools/test_reference_map_http.gd"
## Read-only formal town input; every edit and save targets a unique temp map.

func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900);root.content_scale_size=root.size;rpc_timeout_ms=90000
	create_timer(2400).timeout.connect(func():persist();quit(2))
	var source:="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
	var signature:=FileAccess.get_sha256(source)
	var model_sha:=FileAccess.get_sha256(MODEL_PATH);var library_sha:=FileAccess.get_sha256(LIBRARY_PATH)
	directory=Paths.cache_directory("reference_town_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	map_path=directory.path_join("map.gltf");output_path=Art.review_path("reference_map_town_20261007.json")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
	if not Paths.allowed(output_path,Art.review_path("")):quit(1);return
	var source_file:=FileAccess.open(source,FileAccess.READ)
	report={"runs":[],"source":source,"source_sha256":signature,"source_bytes":source_file.get_length() if source_file!=null else 0,
		"output":map_path,"model":{"name":MODEL_NAME,"path":MODEL_PATH,"sha256":model_sha}}
	source_file=null;persist()
	print("REFERENCE_TOWN_OPEN ",source)
	var started:=Time.get_ticks_usec()
	# Explicit migration read mode is confined to this test input. Normal editor
	# and runtime access still require the current reference format.
	var doc=Doc.open_file(source,{},Callable(),true)
	report.source_open_ms=(Time.get_ticks_usec()-started)/1000.
	check(doc!=null,"formal town opens in explicit legacy migration read mode")
	if doc==null:persist();quit(1);return
	report.initial_records=doc.records.size();persist()
	started=Time.get_ticks_usec();await attach_editor(doc)
	report.editor_init_ms=(Time.get_ticks_usec()-started)/1000.;persist()
	editor._camera.position=Vector3(280,7,137)
	editor._camera.look_at(Vector3(317,3,166),Vector3.UP)
	await settle();await RenderingServer.frame_post_draw
	var screenshot:=output_path.get_basename()+"_editor.png"
	check(root.get_texture().get_image().save_png(screenshot)==OK,"reference authoring town screenshot captured on private desktop")
	report.screenshot=screenshot;persist()
	var asset_id:=await model_asset_id()
	if asset_id.is_empty():persist();await detach_editor();quit(1);return
	await save_phase("baseline_migration")
	var ordinary:Dictionary={}
	for record:Dictionary in doc.records:
		if record.get("kind")=="asset" and not record.has("house_prefab") and not record.has("bridge_mesh") and not record.has("building") and not record.get("editor_locked",false) and not record.get("editor_hidden",false):
			ordinary=record;break
	check(not ordinary.is_empty(),"existing unlocked model available for pose-only measurement")
	if not ordinary.is_empty():
		await call_tool("set_object_transform",{"id":ordinary.uuid,"position":[ordinary.position[0],ordinary.position[1]+1.,ordinary.position[2]]})
		await save_phase("move_existing_model",true)
	started=Time.get_ticks_usec()
	var placed:=await call_tool("place_asset",{"asset_id":asset_id,"position":[20,0,20]})
	report.add_endpoint_ms=(Time.get_ticks_usec()-started)/1000.
	var ids:Array=placed.get("ids",[])
	check(ids.size()==1,"real new stone-window model placed through HTTP")
	if ids.size()!=1:persist();await detach_editor();quit(1);return
	var model_id:String=ids[0];report.new_uuid=model_id
	report.live_model=material_evidence(editor._view.get_node_or_null(NodePath(model_id)))
	check(report.live_model.valid,"town editor new model has actual mesh and readable PBR textures")
	await save_phase("add_real_model")
	await call_tool("undo");check(doc._find(model_id).is_empty(),"town undo removes new model")
	await save_phase("undo_real_model",true)
	await call_tool("redo");check(not doc._find(model_id).is_empty(),"town redo restores same model UUID")
	await save_phase("redo_real_model",true)
	await call_tool("select_objects",{"ids":[model_id]});await call_tool("delete_selection")
	check(doc._find(model_id).is_empty(),"town delete removes model")
	await save_phase("delete_real_model",true)
	await call_tool("undo");check(not doc._find(model_id).is_empty(),"restore new model for runtime material verification")
	await save_phase("restore_for_game",true)
	var expected:Array=doc.records
	var meta:Dictionary=doc.map_meta
	await detach_editor()
	print("REFERENCE_TOWN_AUTHOR_REOPEN ",map_path)
	started=Time.get_ticks_usec();var reopened=Doc.open_file(map_path)
	report.author_reopen_ms=(Time.get_ticks_usec()-started)/1000.
	check(reopened!=null and Pose.same(reopened.records,expected) and Pose.same(reopened.map_meta,meta),"temporary reference town reopens with complete author state")
	external_proxies(expected.size());persist()
	print("REFERENCE_TOWN_GAME_LOAD ",map_path)
	report.game=await game_check(expected,meta,model_id)
	report.source_sha256_after=FileAccess.get_sha256(source)
	check(report.source_sha256_after==signature,"formal town remains byte-for-byte unchanged")
	check(FileAccess.get_sha256(MODEL_PATH)==model_sha and FileAccess.get_sha256(LIBRARY_PATH)==library_sha,"real source model and asset catalog unchanged")
	persist();print("REFERENCE_TOWN_FINISHED failures=",failed," report=",output_path)
	quit(0 if failed==0 else 1)
