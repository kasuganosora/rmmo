extends "res://tools/test_residential_bridges_http.gd"
const CurveMath=preload("res://scripts/world_editor/residential_curve_connection.gd")

func verify_curve(original:Dictionary,result:Dictionary)->void:
	var c:Dictionary=result.road_connection;var graph:Dictionary=City.resolve(editor._doc.map_meta).roads
	var nodes:Dictionary={};for n:Dictionary in graph.nodes:nodes[n.id]=n
	var source:Dictionary=original.map_meta.editor_layout.roads.edges.filter(func(e):return e.id=="main_lane")[0]
	var source_nodes:Dictionary={};for n:Dictionary in original.map_meta.editor_layout.roads.nodes:source_nodes[n.id]=n
	var parts:Array=graph.edges.filter(func(e):return e.id in c.child_edge_ids)
	check(parts.size()==2 and parts.all(func(e):return e.has("controls")),"both persisted subedges remain editable cubic curves")
	if parts.size()!=2:return
	var split:=CurveMath.subcurves(source,source_nodes,c.parameter)
	check(saved_equal(parts[0].controls,split.controls[0]) and saved_equal(parts[1].controls,split.controls[1]) and saved_equal(nodes[c.join_node_id].position,split.position),"authoring join and handles preserve double-precision subdivision")
	check(absf(parts[0].width_end-lerpf(source.width_start,source.width_end,c.parameter))<1e-10 and parts[0].width_end==parts[1].width_start,"tapered widths agree at curved junction")
	check(City.analyze(graph).ok and City.analyze(graph).diagnostics.is_empty(),"final curved graph has no topology diagnostics")
	for edge:Dictionary in original.map_meta.editor_layout.roads.edges:
		if edge.id==source.id:continue
		var matches:Array=graph.edges.filter(func(e):return e.id==edge.id)
		check(matches.size()==1 and Placement._same(edge,matches[0]),"out-of-scope road edge unchanged: "+edge.id)

func run()->void:
	create_timer(600).timeout.connect(func():push_error("Residential curve HTTP timeout");quit(2))
	rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var source_report:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--source-report="):source_report=arg.trim_prefix("--source-report=")
	if source_report.is_empty():check(false,"validated source report required");await finish();return
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.failures==0 and FileAccess.get_sha256(source.fixture)==source.map_sha256,"verified mixed-bridge source remains read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__residential_curves_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_curves_%d"%OS.get_process_id(),"name":"临时弯路住宅回归"}))
	map_path=directory.path_join("maps/test/map.gltf")
	var doc=Doc.open_file(source.fixture)
	var loaded:Dictionary=Placement.Prefabs.read({"prefab_path":source.source_path});check(loaded.ok,"validated frozen house read without regeneration")
	if not loaded.ok:await finish();return
	var saved:Dictionary=Placement.Prefabs.capture(loaded.records,Library.new(directory.path_join("assets")),"弯路回归住宅",loaded.building_instances)
	check(saved.ok,"house resource copy confined to temporary pack");if not saved.ok:await finish();return
	doc.records=doc.records.filter(func(r):return r.uuid not in source.plan.house_ids and not r.has("road_source"));doc.map_meta.building_instances.erase(source.plan.building_id)
	var data:=City.resolve(doc.map_meta);data.erase("road_surface")
	data.roads.nodes=data.roads.nodes.filter(func(n):return not str(n.id).begins_with("home_"));data.roads.edges=data.roads.edges.filter(func(e):return not str(e.id).begins_with("home_"))
	for e:Dictionary in data.roads.edges:
		if e.id=="main_lane":e.to="main_b";e.width_start=3.2;e.width_end=3.5;e.controls=[[-8.,0.,-12.],[8.,0.,-16.]]
	doc.map_meta.editor_layout=data;check(doc.save(map_path)==OK,"temporary curved street baseline saved")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=33410
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"independent current 3D HTTP server starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(d):return d.name=="preview_residential_placement" and d.description.contains("贝塞尔")) and not definitions.any(func(d):return d.name=="paint_tile"),"discovery documents cubic capability without enabling 2D")
	kerbs_mode=true;var material:=await kerb_material()
	var made:=await call_tool("generate_road_surface",{"follow_terrain":true,"kerb_enabled":true,"kerb_material_id":material})
	if not made.get("ok",false):manifest.last_failure=made;await finish();return
	await call_tool("save_world");var original:Dictionary=editor._doc.recovery_snapshot()
	var args:Dictionary=Placement.defaults().merged({"asset_id":saved.entry.prefab_path,"position":[0.,0.,0.],"road_edge_id":"main_lane"},true)
	manifest.merge({"source_path":saved.entry.prefab_path,"source_sha256":FileAccess.get_sha256(saved.entry.prefab_path),"asset_id":saved.entry.prefab_path,"request":args,"source_graph":data.roads},true)
	var before:=snapshot();var plan:=await call_tool("preview_residential_placement",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	same_snapshot(before,"cubic preview does not mutate graph/history/selection/dirty")
	check(plan.road_connection.kind=="cubic" and plan.road_connection.split and plan.bridges.binding_count==2,"preview exposes curved junction with both bridge contexts preserved")
	var again:=await call_tool("preview_residential_placement",args);check(again.plan_token==plan.plan_token and equivalent(again.road_connection,plan.road_connection),"same input reuses exact curved candidate")
	await call_tool("discard_residential_placement",{"plan_token":plan.plan_token});await reject("apply_residential_placement",{"plan_token":plan.plan_token},"candidate_missing")
	await reject("preview_residential_placement",args.merged({"width":0.},true))
	await reject("preview_residential_placement",args.merged({"road_edge_id":"crossing"},true),"unsupported")
	for property:String in ["locked","hidden"]:
		var altered:=original.duplicate(true);var layout:Dictionary=altered.map_meta.editor_layout
		for e:Dictionary in layout.roads.edges:
			if e.id=="main_lane":e[property]=true
		layout.road_surface.graph_token=City.token(layout.roads);restore(altered)
		await reject("preview_residential_placement",args,"protected_scope");restore(original)
	plan=await call_tool("preview_residential_placement",args)
	var stale:=original.duplicate(true)
	for e:Dictionary in stale.map_meta.editor_layout.roads.edges:
		if e.id=="main_lane":e.controls[0][2]-=.1
	restore(stale);await reject("apply_residential_placement",{"plan_token":plan.plan_token},"base_changed");await reject("preview_residential_placement",args,"stale_road_surface");restore(original)
	var blocker:String=editor._doc.add_box("block",Vector3(-3.,1.,-11.),Vector3(10.,2.,1.))
	await reject("preview_residential_placement",args,"search_exhausted");check(not blocker.is_empty(),"corridor blocker is a real authored object");restore(original)
	# The combined service inherits the same curve operation after explicit grading.
	var site_args:Dictionary={"residential":args,"terrain":{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":18.,"plot_depth":18.,"target_height":0.,"strength":1.,"blend_margin":1.,"cross_tiles":true}]}}
	var site_before:=snapshot();var site:=await call_tool("preview_residential_site",site_args)
	if not site.get("ok",false):manifest.last_failure=site;await finish();return
	check(site.road_connection.kind=="cubic" and site.checks.final_combined_save,"combined grading candidate also supports the exact curved road")
	await call_tool("apply_residential_site",{"plan_token":site.plan_token});await call_tool("undo")
	check(same_authored_state(site_before.state,editor._doc.recovery_snapshot()),"combined curved site undoes as one transaction")
	var panel=editor._building_panel.residential;panel.refresh_catalogs()
	check(choose(panel.asset_choice,args.asset_id) and choose(panel.road_choice,"main_lane") and panel.road_choice.get_item_text(panel.road_choice.selected).contains("弯路"),"UI offers and labels the curved ground road")
	var values:=args.duplicate(true);values.erase("asset_id");values.erase("road_edge_id");panel.form.update_values(values)
	plan=await call_tool("preview_residential_placement",args);before=snapshot();panel.preview_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and equivalent(plan.road_connection,panel.last_result.get("road_connection",{})) and equivalent(result_geometry(plan),result_geometry(panel.last_result)),"real UI and HTTP return identical curve geometry and connection")
	same_snapshot(before,"actual UI curved preview is private")
	check(panel.feedback.text.contains("接入弯路") and panel.feedback.text.contains("可编辑路段"),"UI explains curve junction and preserved editable subdivision")
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._building_panel):editor._dock_tabs.current_tab=i
	(panel.get_child(0) as CheckButton).button_pressed=true
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0.,0.,-9.],"distance":38.,"pitch":-48.,"yaw":-155.});await settle();await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var screenshot:=report_path.get_base_dir().path_join("ui.webp");image.save_webp(screenshot,true,.9)
	FileAccess.open(report_path.get_base_dir().path_join("compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(screenshot),"lossy":true,"quality":90,"width":image.get_width(),"height":image.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
	panel.apply_button.pressed.emit();await settle();check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before.undo+1,"UI applies complete curved candidate once")
	verify_curve(original,plan);preserve(original,plan,"UI curved apply");await call_tool("undo")
	check(same_authored_state(before.state,editor._doc.recovery_snapshot()),"one undo restores original unsplit curve")
	plan=await call_tool("preview_residential_placement",args);await call_tool("apply_residential_placement",{"plan_token":plan.plan_token})
	var after:Dictionary=editor._doc.recovery_snapshot();check_kerbs("applied",plan.changed_ids)
	await call_tool("undo");await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"redo restores curve, house and access IDs exactly")
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	manifest.editor_batch_stats=editor._ground_batches.stats();check(manifest.editor_batch_stats.pending_groups==0 and manifest.editor_batch_stats.source_surfaces>manifest.editor_batch_stats.render_surfaces,"native static batches actually reduce rendered surfaces")
	check(plan.house_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id))),"house components retain independent identity")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(saved_equal(after.records,editor._doc.records) and saved_equal(after.map_meta,editor._doc.map_meta),"save/reopen retains curve and authoring data within native serialization precision")
	verify_curve(original,plan);preserve(original,plan,"curve reopen");check_kerbs("reopened",plan.changed_ids)
	check(editor._doc.validate_save()==OK,"reopened curve map passes full native validation")
	check(FileAccess.get_sha256(source.fixture)==source.map_sha256,"original mixed bridge fixture remains byte-identical")
	manifest.plan=plan;manifest.road_points=plan.road_points;manifest.persistence={"max_numeric_delta":persistence_max_delta,"differences":persistence_differences}
	await finish()
