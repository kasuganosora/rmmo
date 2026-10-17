extends "res://tools/test_residential_bridges_http.gd"
## Uses the previously validated mixed-bridge fixture and frozen house read-only.
## All authored edits and copied house resources belong to a new temporary pack.
const Site=preload("res://scripts/world_editor/residential_site_tools.gd")

func same_site(a:Dictionary,b:Dictionary)->bool:
	for key:String in ["position","adjustment","road_points","changes","earthwork","terrain_operation_count","checks"]:
		if not equivalent(a.get(key),b.get(key)):return false
	return true

func run()->void:
	create_timer(600).timeout.connect(func():push_error("Residential site timeout");quit(2))
	rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var source_report:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--source-report="):source_report=argument.trim_prefix("--source-report=")
	if source_report.is_empty():check(false,"--source-report is required");await finish();return
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.failures==0 and FileAccess.get_sha256(source.fixture)==source.map_sha256,"prior mixed bridge fixture is verified read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__residential_site_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_site_%d"%OS.get_process_id(),"name":"临时整地住宅联合回归"}))
	map_path=directory.path_join("maps/test/map.gltf")
	var doc=Doc.open_file(source.fixture)
	var source_house:Dictionary=Placement.Prefabs.read({"prefab_path":source.source_path})
	check(source_house.ok,"validated frozen house read without regeneration")
	if not source_house.ok:await finish();return
	var saved:Dictionary=Placement.Prefabs.capture(source_house.records,Library.new(directory.path_join("assets")),"联合候选回归住宅",source_house.building_instances)
	check(saved.get("ok",false),"native prefab copy and resources confined to new pack")
	if not saved.get("ok",false):await finish();return
	doc.records=doc.records.filter(func(r):return r.uuid not in source.plan.house_ids and not r.has("road_source"))
	doc.map_meta.building_instances.erase(source.plan.building_id)
	var layout:=City.resolve(doc.map_meta);layout.erase("road_surface")
	layout.roads.nodes=layout.roads.nodes.filter(func(n):return not str(n.id).begins_with("home_"))
	layout.roads.edges=layout.roads.edges.filter(func(e):return not str(e.id).begins_with("home_"))
	for edge:Dictionary in layout.roads.edges:
		if edge.id=="main_lane":edge.to="main_b";edge.width_end=3.5
	doc.map_meta.editor_layout=layout
	var ground:Dictionary=doc._find("residential_ground")
	for z in int(ground.terrain_mesh.rows)+1:
		for x in int(ground.terrain_mesh.columns)+1:
			var point:Vector3=Site.Layout.T.transform(ground)*Site.Layout.T.point(ground,x,z)
			if absf(point.x)<9. and point.z> -7. and point.z<9.:ground.terrain_mesh.heights[z*(int(ground.terrain_mesh.columns)+1)+x]=1.2
	check(doc.save(map_path)==OK,"temporary hill and mixed bridge baseline saved")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=33150
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"independent 3D loopback HTTP starts")
	var names:Array=(await rpc("tools/list")).result.tools.map(func(d):return d.name)
	check(["preview_residential_site","apply_residential_site","discard_residential_site"].all(func(n):return n in names) and "paint_tile" not in names,"all three site tools discovered without retired 2D tools")
	var kerb_id:=await kerb_material()
	var generated:=await call_tool("generate_road_surface",{"follow_terrain":true,"kerb_enabled":true,"kerb_material_id":kerb_id})
	if not generated.get("ok",false):await finish();return
	await call_tool("save_world")
	var asset_id:String=saved.entry.prefab_path
	var residential:Dictionary=Placement.defaults().merged({"asset_id":asset_id,"position":[0.,0.,0.],"road_edge_id":"main_lane"},true)
	var plain:=await reject("preview_residential_placement",residential)
	check(str(plain.get("code","")).begins_with("residential_support"),"ungraded hill fails continuous residential support, not an unrelated precondition")
	var stroke:Dictionary={"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,1.]],"plot_width":24.,"plot_depth":22.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":.25,"strength":1.,"blend_margin":2.,"cross_tiles":true}
	var ramp:Dictionary={"id":"residential_ground","start":[-3.316,.25,-8.],"end":[-3.316,0.,-16.],"width":2.,"blend_margin":1.,"cross_tiles":true}
	var args:Dictionary={"residential":residential,"terrain":{"strokes":[stroke],"ramp":ramp,"road_nodes":[{"id":"far_a","position":[78.,.1,-12.]}],"expected_road_token":City.token(City.resolve(editor._doc.map_meta).roads)}}
	manifest.merge({"source_path":asset_id,"asset_id":asset_id,"source_sha256":FileAccess.get_sha256(asset_id),"request":args},true)
	var original:=snapshot();var plan:=await call_tool("preview_residential_site",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	same_snapshot(original,"terrain, house and road preview leaves live map/history/selection/dirty unchanged")
	check(plan.checks.final_terrain and plan.checks.final_combined_save and plan.bridges.binding_count==2,"complete combined candidate passes native terrain, house, road and bridge checks")
	check(plan.earthwork.cut_m3>0 and plan.earthwork.fill_m3>0 and "residential_ground" in plan.changes.updated,"preview exposes real cut/fill and the changed terrain")
	check(plan.terrain.ramp.max_height_error<=.0002 and plan.terrain.ramp.max_grade<=.15001,"final combined terrain retains full-width endpoint ramp proof")
	check(plan.house_ids.size()>32 and plan.changes.road_ids.size()>0,"preview contains complete house and actual access road changes")
	var again:=await call_tool("preview_residential_site",args);check(again.plan_token==plan.plan_token and same_site(plan,again),"identical source and request reuse the same candidate")
	await call_tool("discard_residential_site",{"plan_token":plan.plan_token});same_snapshot(original,"discard keeps all live state unchanged")
	await reject("apply_residential_site",{"plan_token":plan.plan_token},"candidate_missing")
	await reject("preview_residential_site",args.merged({"residential":residential.merged({"asset_id":"missing"},true)},true))
	await reject("preview_residential_site",{"residential":residential,"terrain":{"strokes":[]}})
	var invalid:Dictionary=args.duplicate(true);invalid.terrain.strokes=[]
	for i in 65:invalid.terrain.strokes.append(stroke.duplicate(true))
	await reject("preview_residential_site",invalid)
	for property:String in ["editor_locked","editor_hidden"]:
		editor._doc._find("residential_ground")[property]=true;await reject("preview_residential_site",args);restore(original.state)
	editor._doc._find("fixture_bridge").editor_locked=true;await reject("preview_residential_site",args);restore(original.state)
	var blocked:String=editor._doc.add_box("block",Vector3(0.,1.,-11.),Vector3(16.,2.,1.))
	var blocked_args:=args.duplicate(true);blocked_args.residential.setback_min=3.;blocked_args.residential.setback_max=3.
	await reject("preview_residential_site",blocked_args);restore(original.state)
	check(not blocked.is_empty(),"final-state obstruction was a real temporary object")
	# More than 32 genuine stamp evaluations, not just 34 house components.
	var many:=args.duplicate(true);many.terrain.strokes=[]
	for i in 33:
		var stamp:=stroke.duplicate(true);stamp.target_height=.25 if i%2==0 else .2;many.terrain.strokes.append(stamp)
	for i in 35:editor._doc.checkpoint_recovery()
	var full_history:=snapshot();var many_plan:=await call_tool("preview_residential_site",many)
	if not many_plan.get("ok",false):manifest.last_failure=many_plan;await finish();return
	check(full_history.undo==32 and many_plan.terrain_operation_count==34 and same_site(plan,many_plan)==false,"34 terrain steps prepare despite full 32-entry live history")
	same_snapshot(full_history,"34 private steps do not consume live history")
	await call_tool("apply_residential_site",{"plan_token":many_plan.plan_token})
	await call_tool("undo");check(same_authored_state(full_history.state,editor._doc.recovery_snapshot()),"single undo restores the outer start after 34 internal steps")
	# A late failure must not discard the original start or overwrite later edits.
	var bad_last:=many.duplicate(true);bad_last.residential.asset_id="missing_after_34_steps"
	await reject("preview_residential_site",bad_last)
	plan=await call_tool("preview_residential_site",args)
	editor._residential_site._candidate.after.records[0].size[0]=-1.
	await reject("apply_residential_site",{"plan_token":plan.plan_token},"candidate_invalid")
	await call_tool("set_object_properties",{"ids":["far_ground"],"name":"later edit survives failed publication"})
	await reject("apply_residential_site",{"plan_token":plan.plan_token},"candidate_missing")
	check(editor._doc._find("far_ground").editor_name=="later edit survives failed publication","failed candidate never rolls back a subsequent edit")
	await call_tool("undo")
	plan=await call_tool("preview_residential_site",args)
	await call_tool("set_object_properties",{"ids":["far_ground"],"name":"stale version"})
	await reject("apply_residential_site",{"plan_token":plan.plan_token},"base_changed");await call_tool("undo")
	plan=await call_tool("preview_residential_site",args)
	var bytes:=FileAccess.get_file_as_bytes(asset_id);FileAccess.open(asset_id,FileAccess.WRITE).store_buffer(bytes+PackedByteArray([32]))
	await reject("apply_residential_site",{"plan_token":plan.plan_token},"source_changed");FileAccess.open(asset_id,FileAccess.WRITE).store_buffer(bytes)
	check(FileAccess.get_sha256(asset_id)==manifest.source_sha256,"copied house source restored exactly; original asset never edited")
	var panel=editor._building_panel.residential;panel.refresh_catalogs()
	editor._dock_tabs.current_tab=8;panel.get_child(0).button_pressed=true;await settle()
	check(choose(panel.asset_choice,asset_id) and choose(panel.road_choice,"main_lane"),"UI selects the same house and ground road")
	var values:=residential.duplicate(true);values.erase("asset_id");values.erase("road_edge_id");panel.form.update_values(values)
	panel.site_enabled.button_pressed=true
	var draft=panel.site_draft
	for field in draft.plots:field.get_parent().queue_free()
	draft.plots.clear();draft.add_plot(stroke);draft.add_node(args.terrain.road_nodes[0]);draft.ramp_enabled.button_pressed=true;draft.ramp_form.update_values(ramp)
	manifest.ui_request=panel.request()
	check(equivalent(panel.request(),args),"actual UI emits the same plot and endpoint ramp request as MCP")
	plan=await call_tool("preview_residential_site",args);var ui_before:=snapshot()
	panel.preview_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and same_site(plan,panel.last_result),"real UI preview agrees with HTTP final geometry and changes")
	same_snapshot(ui_before,"UI combined preview is private")
	check(is_instance_valid(panel.ghost) and panel.changes_view.visible and panel.feedback.text.contains("挖方"),"UI shows combined geometry, earthwork and explicit change list")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0.,1.,-8.],"distance":38.,"pitch":-32.,"yaw":30.})
	var scroll:ScrollContainer=editor._building_panel.get_parent();scroll.ensure_control_visible(panel.feedback);await settle();await RenderingServer.frame_post_draw
	var output:String=report_path.get_base_dir();DirAccess.make_dir_recursive_absolute(output)
	var screen:=root.get_texture().get_image();check(screen.save_webp(output+"/site_ui.webp",true,.9)==OK,"UI screenshot uses actual lossy WebP quality 90")
	FileAccess.open(output+"/site_ui_compression.json",FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(output+"/site_ui.webp"),"path":output+"/site_ui.webp","lossy":true,"quality":90,"width":screen.get_width(),"height":screen.get_height(),"encoder":"Godot Image.save_webp(lossy=true, quality=0.9)","avatar":"not instantiated"},"\t"))
	draft.plots[0].fields.target_height.value=.24
	check(panel.plan_token.is_empty() and panel.apply_button.disabled and not is_instance_valid(panel.ghost),"editing a terrain field invalidates the whole candidate")
	draft.plots[0].fields.target_height.value=.25
	panel.preview_button.pressed.emit();await settle();panel.apply_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false),"actual UI applies the full site once")
	await call_tool("undo");check(same_authored_state(ui_before.state,editor._doc.recovery_snapshot()),"single HTTP undo restores UI terrain, house and road transaction")
	var before_apply:=snapshot();plan=await call_tool("preview_residential_site",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	editor._ground_batches.flush();editor._ground_batches.set_process(false)
	await call_tool("apply_residential_site",{"plan_token":plan.plan_token})
	check(editor._doc._undo.size()==mini(32,before_apply.undo+1),"HTTP commits exactly one outer history entry")
	var published:=snapshot();var batch=editor._ground_batches
	while not batch._preparation.is_empty():batch._prepare_step(0)
	var fallback_groups:Array=batch.groups.values().filter(func(g):return not is_instance_valid(g.get("visual")))
	check(not fallback_groups.is_empty(),"publication has pending derived groups with independent source geometry")
	if not fallback_groups.is_empty():
		var group:Dictionary=fallback_groups[0];batch._commit(group,{},Time.get_ticks_usec())
		check(not is_instance_valid(group.get("visual")) and group.members.all(func(n):return is_instance_valid(n) and n.mesh.get_surface_count()>0),"empty derived worker result keeps real independent source meshes")
	same_snapshot(published,"derived failure never rolls back accepted authoring or history")
	await call_tool("set_object_properties",{"ids":["far_ground"],"name":"later edit after derived failure"});await settle()
	check(editor._doc._find("far_ground").editor_name=="later edit after derived failure" and editor._doc.has_uuid(plan.house_ids[0]),"later edit survives after failed derived publication")
	await call_tool("undo");batch.set_process(true)
	var after:Dictionary=editor._doc.recovery_snapshot()
	for record:Dictionary in before_apply.state.records:
		if record.uuid in plan.changed_ids:continue
		check(Placement._same(record,editor._doc._find(record.uuid)),"out-of-scope record preserved: "+record.uuid)
	check(Placement._same(original.state.map_meta.editor_layout.waterways,editor._doc.map_meta.editor_layout.waterways) and Placement._same(original.state.records.filter(func(r):return r.uuid=="fixture_bridge")[0],editor._doc._find("fixture_bridge")),"grading and access retain bridge and waterway authored identity")
	await call_tool("undo");check(same_authored_state(before_apply.state,editor._doc.recovery_snapshot()),"undo restores complete site baseline")
	await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"redo restores exact complete site identities")
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	manifest.editor_batch_stats=editor._ground_batches.stats()
	check(manifest.editor_batch_stats.pending_groups==0 and manifest.editor_batch_stats.source_surfaces>manifest.editor_batch_stats.render_surfaces,"native shared batching completes and reduces surfaces")
	check(plan.house_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id))),"house components retain independent identities after publication")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(saved_equal(after.records,editor._doc.records,"records") and saved_equal(after.map_meta,editor._doc.map_meta,"metadata"),"complete site survives native save/reopen within serialization precision")
	manifest.persistence={"max_numeric_delta":persistence_max_delta,"differences":persistence_differences}
	check(editor._doc.validate_save()==OK,"reopened site passes full native validation")
	check(FileAccess.get_sha256(source.fixture)==source.map_sha256,"source mixed-bridge fixture stays byte-identical")
	manifest.plan=plan;manifest.road_points=plan.road_points
	await finish()
