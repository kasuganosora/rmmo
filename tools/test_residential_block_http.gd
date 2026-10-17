extends "res://tools/test_residential_relocation_http.gd"
const Block=preload("res://scripts/world_editor/residential_block_tools.gd")

func run()->void:
	create_timer(900).timeout.connect(func():push_error("Block HTTP timeout");quit(2));rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var source_report:="review_artifacts/residential_curves_20261017/http.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--source-report="):source_report=arg.trim_prefix("--source-report=")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.failures==0 and FileAccess.get_sha256(source.fixture)==source.map_sha256,"verified frozen source map remains read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__residential_block_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_block_%d"%OS.get_process_id(),"name":"临时街区联合候选回归"}))
	map_path=directory.path_join("maps/test/map.gltf");var doc=Doc.open_file(source.fixture)
	var dependency:=isolate_dependency(doc.records.filter(func(r):return r.get("building",{}).get("id")==source.plan.building_id))
	for record:Dictionary in doc.records:
		if record.get("building",{}).get("id")==source.plan.building_id:
			if record.get("fixture",{}).get("kind")=="window":record.fixture.open=.35
			preload("res://scripts/world3d/house_prefab.gd").retarget_materials(record)
	var road_settings:Dictionary=doc.map_meta.editor_layout.road_surface.settings.duplicate(true)
	doc.records=doc.records.filter(func(r):return not r.has("road_source"));doc.map_meta.editor_layout.erase("road_surface")
	doc.map_meta.editor_layout.roads=source.source_graph.duplicate(true)
	check(doc.save(map_path)==OK,"private mixed-house baseline saved")
	if failed:await finish();return
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._material_tool.library.include_shared=true;editor._shared_assets=[Library.new(source.source_path.get_base_dir().get_base_dir())]
	var probe:=TCPServer.new();port=33910
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private 3D loopback server starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.filter(func(d):return str(d.name).ends_with("residential_block")).size()==3 and not definitions.any(func(d):return d.name=="paint_tile"),"current 3D discovers all block tools without retired 2D")
	var made:=await call_tool("generate_road_surface",road_settings)
	if not made.get("ok",false):manifest.last_failure=made;await finish();return
	var id:String=source.plan.building_id;var original:Dictionary=editor._doc.recovery_snapshot()
	var args:Dictionary={"homes":[{"id":"home_1","residential":Placement.defaults().merged({"building_id":id,"position":[-8.,.12,1.],"road_edge_id":"main_lane","setback_min":2.5},true)},{"id":"home_2","residential":Placement.defaults().merged({"asset_id":source.asset_id,"position":[8.,.12,1.],"road_edge_id":"main_lane","setback_min":2.5},true)}],"terrain":{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,1.]],"plot_width":30.,"plot_depth":19.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":.12,"strength":1.,"blend_margin":2.,"cross_tiles":true}]}}
	manifest.request=args;manifest.source_graph=source.source_graph;manifest.source_path=source.source_path
	await reject("preview_residential_block",{"homes":[]})
	var invalid:=args.duplicate(true);invalid.homes.resize(17)
	for i in 17:invalid.homes[i]=args.homes[0].duplicate(true)
	await reject("preview_residential_block",invalid)
	invalid=args.duplicate(true);invalid.homes[1].id=invalid.homes[0].id
	await reject("preview_residential_block",invalid,"invalid_arguments")
	invalid=args.duplicate(true);invalid.homes[1].residential.building_id=id
	await reject("preview_residential_block",invalid,"invalid_arguments")
	invalid=args.duplicate(true);invalid.homes[1].residential=args.homes[0].residential.duplicate(true)
	await reject("preview_residential_block",invalid,"invalid_arguments")
	invalid=args.duplicate(true);invalid.homes[0].residential.old_access="remove_owned"
	await reject("preview_residential_block",invalid,"access_unowned")
	invalid=args.duplicate(true);invalid.homes[1].residential.road_edge_id="crossing"
	await reject("preview_residential_block",invalid,"unsupported")
	invalid=args.duplicate(true);invalid.terrain.road_nodes=[{"id":"main_a","position":[-12.,0.,-16.]}];invalid.terrain.expected_road_token="stale"
	await reject("preview_residential_block",invalid,"stale_road_surface")
	for flag:String in ["editor_locked","editor_hidden"]:
		editor._doc._find(source.plan.house_ids[0])[flag]=true
		await reject("preview_residential_block",args,"protected_scope");restore(original)
	invalid=args.duplicate(true);invalid.homes[1].residential.position=invalid.homes[0].residential.position.duplicate()
	var rejection:=await reject("preview_residential_block",invalid,"placement_conflict")
	check(rejection.get("home_id")=="home_2" and rejection.get("home_index")==1 and rejection.get("diagnostic",{}).get("items",[]).any(func(item):return item.locatable),"last-house conflict identifies the row and a locatable witness after private grading/first placement")
	var before:=snapshot();var plan:=await call_tool("preview_residential_block",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	same_snapshot(before,"mixed block preview preserves authoring, history and selection")
	check(plan.homes.size()==2 and plan.homes[0].operation=="relocate" and plan.homes[1].operation=="place","mixed new and existing houses share one result")
	check(plan.earthwork.fill_m3>0 and plan.terrain_operation_count==1,"both houses use shared real grading")
	check(plan.road_lineage.main_lane.size()==3 and plan.homes[1].road_connection.edge_id==plan.homes[0].road_connection.child_edge_ids[1],"second home connects to correct descendant of same original cubic")
	var again:=await call_tool("preview_residential_block",args);check(again.plan_token==plan.plan_token,"unchanged block request reuses one token")
	await call_tool("discard_residential_block",{"plan_token":plan.plan_token});await reject("apply_residential_block",{"plan_token":plan.plan_token},"candidate_missing")
	plan=await call_tool("preview_residential_block",args)
	# Simulate a later participant occupying an earlier door corridor. Final
	# validation must find it even though that house's initial preview passed.
	var stage:=Block.Context.new();stage.setup(editor);stage._doc.apply_recovery(editor._residential_block._candidate.after)
	var members:Array=stage._doc.records.filter(func(r):return r.uuid in plan.homes[0].house_ids)
	var entry:=Placement.Access.entrance(members,stage._doc.map_meta.building_instances[plan.homes[0].building_id].yaw)
	var obstruct:Vector3=entry.position+entry.outward*2.1;obstruct.y=.9
	stage._doc.add_box("block",obstruct,Vector3(.25,1.5,.25))
	var final_check:=Block.verify_final(stage,plan.homes.duplicate(true),args.homes)
	check(not final_check.ok and final_check.home_id=="home_1" and final_check.stage=="final_entrance","final gate catches a later object obstructing the earlier house's exterior corridor")
	stage._doc.apply_recovery(editor._residential_block._candidate.after)
	for road:Dictionary in stage._doc.records:
		for kerb:Dictionary in road.get("road_mesh",{}).get("kerbs",[]):
			for point:Array in kerb.a+kerb.b:point[1]+=1.
	final_check=Block.verify_final(stage,plan.homes.duplicate(true),args.homes)
	check(not final_check.ok and final_check.get("code")=="kerb_conflict","final gate rejects raised kerbs above controller step limit")
	stage._doc.apply_recovery(editor._residential_block._candidate.after)
	var far_roads:Array=stage._doc.records.filter(func(r):return r.has("road_source") and r.position[0]>70. and r.position[0]<110. and not r.get("road_mesh",{}).get("kerbs",[]).is_empty())
	check(not far_roads.is_empty(),"scope regression uses an actual distant kerb")
	if not far_roads.is_empty():
		var at:Vector3=Placement._kerb_shapes(far_roads[0])[0].bounds.get_center();at.y=.8
		stage._doc.add_box("block",at,Vector3(.2,1.6,.2))
		check(Block.verify_final(stage,plan.homes.duplicate(true),args.homes).ok,"final per-house proof does not turn an unrelated distant road/object pair into a new block restriction")
	stage.free();same_snapshot(before,"final corridor failure remains private")
	editor._doc.add_box("unrelated",Vector3(48.,1.,12.),Vector3.ONE)
	await reject("apply_residential_block",{"plan_token":plan.plan_token},"base_changed");restore(original)
	plan=await call_tool("preview_residential_block",args)
	var bytes:=FileAccess.get_file_as_bytes(dependency);FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes+PackedByteArray([0]))
	await reject("apply_residential_block",{"plan_token":plan.plan_token},"source_changed");FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes)
	plan=await call_tool("preview_residential_block",args);editor._residential_block._candidate.after.records[0].position[1]+=.01
	await reject("apply_residential_block",{"plan_token":plan.plan_token},"candidate_invalid")
	var panel=editor._building_panel.residential;panel.block_enabled.button_pressed=true;panel.refresh_catalogs()
	for row:Dictionary in args.homes:
		var p:Dictionary=row.residential.duplicate(true);panel.relocation_enabled.button_pressed=p.has("building_id")
		check(choose(panel.road_choice,p.road_edge_id),"UI chooses shared existing road")
		if p.has("building_id"):check(choose(panel.building_choice,p.building_id),"UI chooses existing frozen house")
		else:check(choose(panel.asset_choice,p.asset_id),"UI chooses frozen asset")
		for key in ["asset_id","building_id","road_edge_id"]:p.erase(key)
		panel.form.update_values(p);press(panel.block_draft,"加入此户")
	panel.site_enabled.button_pressed=true
	panel.site_draft.plots[0].update_values(args.terrain.strokes[0].merged({"center":args.terrain.strokes[0].points[0]},true))
	# UI makes the default old-road policy explicit; use that very same public
	# request for HTTP, then activate the real preview/apply buttons.
	args=panel.request();manifest.request=args
	check(args.homes.size()==2 and args.homes[0].id=="home_1" and args.homes[1].id=="home_2","real UI queue stores mixed rows with stable IDs")
	press(panel.block_draft,"上移");check(panel.block_draft.homes[0].id=="home_2","UI can reorder rows")
	press(panel.block_draft,"下移");check(panel.block_draft.homes[0].id=="home_1","UI reorder restores original identities")
	press(panel.block_draft,"载入选中户");press(panel.block_draft,"更新选中户")
	check(equivalent(args,panel.request()),"load/update roundtrip preserves row parameters and shared terrain")
	plan=await call_tool("preview_residential_block",args);before=snapshot();panel.preview_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and equivalent(plan.homes,panel.last_result.get("homes",[])),"real UI and HTTP share identical per-house candidate results")
	same_snapshot(before,"UI block ghost has no authored effects")
	if not panel.last_result.get("ok",false):manifest.last_failure=panel.last_result;await finish();return
	check(panel.feedback.text.contains("街区共 2 栋") and panel.feedback.text.contains("home_1") and panel.feedback.text.contains("home_2"),"UI reports per-house results and shared scope")
	press(panel.block_draft,"移除选中户");check(panel.plan_token.is_empty() and panel.apply_button.disabled and panel.block_draft.homes.size()==1,"editing the queue invalidates its preview")
	press(panel.block_draft,"加入此户");panel.block_draft.homes[1].id="home_2";panel.block_draft.refresh(1)
	plan=await call_tool("preview_residential_block",panel.request());panel.preview_button.pressed.emit();await settle()
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._building_panel):editor._dock_tabs.current_tab=i
	(panel.get_child(0) as CheckButton).button_pressed=true
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0.,0.,-5.],"distance":55.,"pitch":-48.,"yaw":-155.});await settle();await RenderingServer.frame_post_draw
	var container:Node=panel.block_draft.get_parent()
	while container!=null and not container is ScrollContainer:container=container.get_parent()
	if container is ScrollContainer:container.ensure_control_visible(panel.block_draft)
	await settle();await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var screenshot:=report_path.get_base_dir().path_join("ui.webp");image.save_webp(screenshot,true,.9)
	FileAccess.open(report_path.get_base_dir().path_join("compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(screenshot),"lossy":true,"quality":90,"width":image.get_width(),"height":image.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
	before=snapshot();panel.apply_button.pressed.emit();await settle();check(panel.last_result.get("ok",false),"actual UI apply publishes the block")
	identities(original,plan.homes[0].merged({"changes":plan.changes,"changed_ids":plan.changed_ids},true),"block relocation")
	check(editor._doc._undo.size()==before.undo+1,"whole block produces exactly one undo entry")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(same_authored_state(before.state,editor._doc.recovery_snapshot()),"one undo restores every house, terrain and road")
	await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"one redo restores exactly the same block identities")
	# Both occupied sites are vacated before placing either relocated house.
	var swap:Dictionary={"homes":[{"id":"swap_first","residential":Placement.defaults().merged({"building_id":plan.homes[0].building_id,"position":plan.homes[1].building_position,"old_access":"remove_owned","road_edge_id":plan.road_lineage.main_lane.back(),"setback_min":2.5},true)},{"id":"swap_second","residential":Placement.defaults().merged({"building_id":plan.homes[1].building_id,"position":plan.homes[0].building_position,"old_access":"remove_owned","road_edge_id":"main_lane","setback_min":2.5},true)}]}
	invalid=swap.duplicate(true);invalid.homes[1].residential.road_edge_id=plan.homes[0].access_binding.edge.id
	await reject("preview_residential_block",invalid,"invalid_arguments")
	var swapped:=await call_tool("preview_residential_block",swap)
	if not swapped.get("ok",false):manifest.last_failure=swapped;await finish();return
	await call_tool("apply_residential_block",{"plan_token":swapped.plan_token})
	check(City.vec(swapped.homes[0].building_position).distance_to(City.vec(plan.homes[1].building_position))<.00001 and City.vec(swapped.homes[1].building_position).distance_to(City.vec(plan.homes[0].building_position))<.00001,"two occupied homes swap positions without copies or collisions against their former sites")
	for home:Dictionary in swapped.homes:
		var migrated:Dictionary=editor._doc.map_meta.building_instances[home.building_id]
		check(Placement._same(migrated.parts,after.map_meta.building_instances[home.building_id].parts),"swap retains part IDs for "+home.id)
		var graph:Dictionary=City.resolve(editor._doc.map_meta).roads
		var old_receipt:Dictionary=after.map_meta.building_instances[home.building_id].residential_access
		check(home.relocation.old_access.removed_edge_ids==[old_receipt.edge.id] and home.relocation.old_access.removed_node_ids==[old_receipt.door.id],"old-access summary lists the exact removed edge and leaf for "+home.id)
		check(home.relocation.old_access.removed_edge_ids.all(func(id_):return not graph.edges.any(func(e):return e.id==id_)) and graph.nodes.any(func(n):return n.id==home.relocation.old_access.retained_join_id),"swap removes only owned terminal edges and retains public joins")
	await call_tool("undo");check(same_authored_state(after,editor._doc.recovery_snapshot()),"one swap undo restores both homes and their owned roads")
	kerbs_mode=true;check_kerbs("applied",plan.changed_ids)
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	manifest.editor_batch_stats=editor._ground_batches.stats();check(manifest.editor_batch_stats.pending_groups==0 and manifest.editor_batch_stats.source_surfaces>manifest.editor_batch_stats.render_surfaces,"whole block participates in actual shared static batches")
	check(plan.house_ids.all(func(uuid):return is_instance_valid(editor._view.get_node_or_null(uuid))),"all components remain individually addressable")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(saved_equal(after.records,editor._doc.records) and saved_equal(after.map_meta,editor._doc.map_meta),"native save/reopen preserves all houses, shared terrain, road lineage and receipts")
	for home:Dictionary in plan.homes:check(Relocation.Binding.removal(City.resolve(editor._doc.map_meta).roads,editor._doc.map_meta.building_instances[home.building_id],editor._doc.map_meta.building_instances).ok,"reopened access ownership remains usable for "+home.id)
	check_kerbs("reopened",plan.changed_ids)
	check(editor._doc.validate_save()==OK and FileAccess.get_sha256(source.fixture)==source.map_sha256,"final save validation and source map preservation")
	manifest.plan=plan;manifest.swap=swapped;manifest.persistence={"max_numeric_delta":persistence_max_delta,"differences":persistence_differences};await finish()

func press(node:Node,label:String)->void:
	for child:Node in node.get_children():
		if child is Button and child.text==label:child.pressed.emit();return
		press(child,label)
