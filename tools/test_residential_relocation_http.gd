extends "res://tools/test_residential_bridges_http.gd"
const Relocation=preload("res://scripts/world_editor/residential_relocation_tools.gd")

func isolate_dependency(value:Variant)->String:
	if value is Dictionary:
		for key:Variant in value:
			if value[key] is String and str(key).ends_with("_path") and FileAccess.file_exists(value[key]):
				var path:=directory.path_join("source_dependency."+str(value[key]).get_extension())
				if DirAccess.copy_absolute(value[key],path)!=OK:return ""
				value[key]=path;return path
			if value[key] is Dictionary or value[key] is Array:
				var path:=isolate_dependency(value[key])
				if not path.is_empty():return path
	elif value is Array:
		for item:Variant in value:
			var path:=isolate_dependency(item)
			if not path.is_empty():return path
	return ""

func identities(original:Dictionary,plan:Dictionary,label:String,requested_yaw:float=0.)->void:
	var id:String=plan.building_id;var before:Dictionary=original.map_meta.building_instances[id];var after:Dictionary=editor._doc.map_meta.building_instances[id]
	check(Placement._same(before.parts,after.parts) and Placement._same(before.parameters,after.parameters),label+": building, part, recipe identities retained")
	var expected:=Relocation.Motion.new().proposal([{"id":id,"value":before,"records":original.records.filter(func(r):return r.uuid in plan.house_ids)}],City.vec(after.position)-City.vec(before.position),Basis(Vector3.UP,deg_to_rad(requested_yaw)),City.vec(before.position))
	check(expected.ok and expected.plans[0].records.all(func(r):return Placement._same(r,editor._doc._find(r.uuid))),label+": exact shared rigid motion preserves all fixture, event, resource and floor fields")
	check(plan.house_ids.all(func(uuid):return uuid in before.parts.values()) and plan.changes.added.all(func(uuid):return uuid not in plan.house_ids) and plan.changes.removed.all(func(uuid):return uuid not in plan.house_ids),label+": no building copy/delete identity substitution")
	check(editor._doc.records.any(func(r):return r.uuid in plan.house_ids and r.get("fixture",{}).get("open")==.35),label+": authored open window state survives")
	check(original.records.filter(func(r):return r.has("road_source") and float(r.position[0])>=70.).all(func(r):return Placement._same(r,editor._doc._find(r.uuid)) and r.uuid not in plan.changed_ids),label+": distant road authoring and IDs untouched")
	check(after.signatures.values().size()==before.signatures.size() and editor._buildings.conflicts(id).is_empty(),label+": moved geometry signatures remain valid")
	var bridges:=BridgeContext.capture(editor,City.resolve(editor._doc.map_meta))
	check(bridges.ok and bridges.summary.binding_count==2,label+": both bridge contexts remain valid")
	for record:Dictionary in original.records:
		if record.get("building",{}).get("id")==id or record.has("road_source") or record.uuid in plan.changes.terrain_ids:continue
		check(Placement._same(record,editor._doc._find(record.uuid)),label+": unrelated object preserved "+record.uuid)

func run()->void:
	create_timer(720).timeout.connect(func():push_error("Relocation HTTP timeout");quit(2));rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var source_report:="review_artifacts/residential_curves_20261017/http.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
		if arg.begins_with("--source-report="):source_report=arg.trim_prefix("--source-report=")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.failures==0 and FileAccess.get_sha256(source.fixture)==source.map_sha256,"source curved residential fixture verified read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__residential_relocation_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_relocation_%d"%OS.get_process_id(),"name":"临时住宅迁移回归"}))
	map_path=directory.path_join("maps/test/map.gltf");var doc=Doc.open_file(source.fixture)
	var dependency:=isolate_dependency(doc.records.filter(func(r):return r.get("building",{}).get("id")==source.plan.building_id))
	check(not dependency.is_empty(),"resource mutation fixture copies one dependency into the private pack")
	for record:Dictionary in doc.records:
		if record.get("building",{}).get("id")==source.plan.building_id and record.get("fixture",{}).get("kind")=="window":record.fixture.open=.35
		if record.get("building",{}).get("id")==source.plan.building_id:preload("res://scripts/world3d/house_prefab.gd").retarget_materials(record)
	check(doc.save(map_path)==OK,"disposable relocation map saved")
	if failed:await finish();return
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	editor._material_tool.library.include_shared=true
	var probe:=TCPServer.new();port=33510
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"isolated loopback 3D MCP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.filter(func(d):return str(d.name).ends_with("residential_relocation")).size()==3 and not definitions.any(func(d):return d.name=="paint_tile"),"current 3D discovery includes preview/apply/discard only")
	var id:String=source.plan.building_id;var original:Dictionary=editor._doc.recovery_snapshot()
	var first:Dictionary={"residential":Placement.defaults().merged({"building_id":id,"position":[-8.,0.,1.],"road_edge_id":"main_lane"},true)}
	await reject("preview_residential_relocation",{"residential":first.residential.merged({"building_id":"missing"},true)},"building_not_found")
	await reject("preview_residential_relocation",{"residential":first.residential.merged({"asset_id":"unexpected"},true)})
	await reject("preview_residential_relocation",{"residential":first.residential.merged({"old_access":"remove_owned"},true)},"access_unowned")
	for flag:String in ["editor_locked","editor_hidden"]:
		editor._doc._find(source.plan.house_ids[0])[flag]=true
		await reject("preview_residential_relocation",first,"protected_scope");restore(original)
	editor._doc._find(source.plan.house_ids[0]).position[0]+=.1
	await reject("preview_residential_relocation",first,"building_modified");restore(original)
	var before:=snapshot();var first_plan:=await call_tool("preview_residential_relocation",first)
	if not first_plan.get("ok",false):manifest.last_failure=first_plan;await finish();return
	same_snapshot(before,"legacy keep preview has no authored, selection or history effects")
	check(first_plan.relocation.old_access.policy=="keep" and first_plan.terrain_operation_count==0,"unknown old roads default to keep and no implicit grading")
	var again:=await call_tool("preview_residential_relocation",first);check(again.plan_token==first_plan.plan_token,"same relocation request reuses candidate")
	await call_tool("discard_residential_relocation",{"plan_token":first_plan.plan_token});await reject("apply_residential_relocation",{"plan_token":first_plan.plan_token},"candidate_missing")
	first_plan=await call_tool("preview_residential_relocation",first)
	await call_tool("apply_residential_relocation",{"plan_token":first_plan.plan_token});identities(original,first_plan,"legacy relocation")
	check(original.map_meta.editor_layout.roads.edges.all(func(e):return City.resolve(editor._doc.map_meta).roads.edges.any(func(n):return e.id==n.id)),"legacy keep retains every existing road edge ID")
	var receipt:Dictionary=editor._doc.map_meta.building_instances[id].residential_access
	check(Relocation.Binding.removal(City.resolve(editor._doc.map_meta).roads,editor._doc.map_meta.building_instances[id],editor._doc.map_meta.building_instances).ok,"new access owns a validated terminal-only receipt")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var migrated:Dictionary=editor._doc.recovery_snapshot()
	var args:Dictionary={"residential":Placement.defaults().merged({"building_id":id,"position":[2.,.12,2.],"yaw":5.,"road_edge_id":source.plan.road_connection.child_edge_ids[1],"old_access":"remove_owned"},true),"terrain":{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[2.,2.]],"plot_width":16.,"plot_depth":19.,"target_height":.12,"strength":1.,"blend_margin":2.,"cross_tiles":true}]}}
	manifest.request=args;manifest.source_graph=source.source_graph;manifest.source_path=source.source_path
	for flag:String in ["locked","hidden"]:
		for edge:Dictionary in editor._doc.map_meta.editor_layout.roads.edges:
			if edge.id==receipt.edge.id:edge[flag]=true
		editor._doc.map_meta.editor_layout.road_surface.graph_token=City.token(editor._doc.map_meta.editor_layout.roads)
		await reject("preview_residential_relocation",args,"protected_scope");restore(migrated)
	for edge:Dictionary in editor._doc.map_meta.editor_layout.roads.edges:
		if edge.id==receipt.edge.id:edge.width_start+=.1
	editor._doc.map_meta.editor_layout.road_surface.graph_token=City.token(editor._doc.map_meta.editor_layout.roads)
	await reject("preview_residential_relocation",args,"access_modified");restore(migrated)
	var graph:Dictionary=editor._doc.map_meta.editor_layout.roads
	graph.nodes.append({"id":"shared_terminal","position":[-18.,0.,-6.]});graph.edges.append({"id":"shared_access","from":receipt.door.id,"to":"shared_terminal","kind":"ground","width_start":1.2,"width_end":1.2})
	editor._doc.map_meta.editor_layout.road_surface.graph_token=City.token(graph)
	await reject("preview_residential_relocation",args,"access_shared");restore(migrated)
	args.terrain.road_nodes=[{"id":"main_a","position":[-12.,0.,-16.]}];args.terrain.expected_road_token=City.token(City.resolve(editor._doc.map_meta).roads)
	var invalid:=args.duplicate(true);invalid.terrain.strokes[0].target_height=8.
	await reject("preview_residential_relocation",invalid);restore(migrated)
	invalid=args.duplicate(true);invalid.terrain.expected_road_token="old"
	await reject("preview_residential_relocation",invalid,"stale_road_surface")
	var blocker:String=editor._doc.add_box("block",Vector3(2.,1.,2.),Vector3(3.,3.,3.))
	await reject("preview_residential_relocation",args);check(not blocker.is_empty(),"blocking geometry is authored in disposable map");restore(migrated)
	before=snapshot();var plan:=await call_tool("preview_residential_relocation",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	same_snapshot(before,"graded relocation preview is private")
	check(plan.relocation.old_access.removed_edge_ids==[receipt.edge.id] and plan.relocation.old_access.removed_node_ids==[receipt.door.id],"old-road summary reports exact deleted edge and terminal node")
	check(plan.earthwork.fill_m3>0. and plan.terrain_operation_count==1 and plan.road_connection.kind=="cubic","final candidate includes real grading, rotation and curved reconnect")
	var old_state:Dictionary=editor._doc.recovery_snapshot();editor._doc.add_box("unrelated",Vector3(49,1,12),Vector3.ONE)
	await reject("apply_residential_relocation",{"plan_token":plan.plan_token},"base_changed");restore(old_state)
	plan=await call_tool("preview_residential_relocation",args)
	var bytes:=FileAccess.get_file_as_bytes(dependency);FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes+PackedByteArray([0]))
	await reject("apply_residential_relocation",{"plan_token":plan.plan_token},"source_changed")
	FileAccess.open(dependency,FileAccess.WRITE).store_buffer(bytes)
	plan=await call_tool("preview_residential_relocation",args);editor._residential_relocation._candidate.after.records[0].position[1]+=.01
	await reject("apply_residential_relocation",{"plan_token":plan.plan_token},"candidate_invalid")
	var panel=editor._building_panel.residential;panel.relocation_enabled.button_pressed=true;panel.refresh_catalogs()
	check(choose(panel.building_choice,id) and choose(panel.old_access_choice,"remove_owned") and choose(panel.road_choice,args.residential.road_edge_id),"UI offers existing building, explicit old-road policy and curved target")
	var values:Dictionary=args.residential.duplicate(true);for key in ["building_id","old_access","road_edge_id"]:values.erase(key)
	panel.form.update_values(values);panel.site_enabled.button_pressed=true
	# Use the real site draft editor to supply the exact grading operation.
	panel.site_draft.plots[0].update_values(args.terrain.strokes[0].merged({"center":args.terrain.strokes[0].points[0]},true))
	panel.site_draft.add_node(args.terrain.road_nodes[0])
	plan=await call_tool("preview_residential_relocation",args);before=snapshot();panel.preview_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and equivalent(result_geometry(plan),result_geometry(panel.last_result)) and equivalent(plan.relocation,panel.last_result.get("relocation",{})),"actual UI and HTTP prepare identical migration geometry and policy")
	same_snapshot(before,"UI relocation preview leaves live state untouched")
	if not panel.last_result.get("ok",false):manifest.last_failure=panel.last_result;await finish();return
	check(panel.feedback.text.contains("保留构件") and panel.feedback.text.contains("旧路") and panel.feedback.text.contains("旧地块"),"UI explains identity, old-road and old-plot treatment")
	for i in editor._dock_tabs.get_tab_count():
		if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._building_panel):editor._dock_tabs.current_tab=i
	(panel.get_child(0) as CheckButton).button_pressed=true
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-2.,0.,-6.],"distance":45.,"pitch":-48.,"yaw":-155.});await settle();await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();var screenshot:=report_path.get_base_dir().path_join("ui.webp");image.save_webp(screenshot,true,.9)
	FileAccess.open(report_path.get_base_dir().path_join("compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(screenshot),"lossy":true,"quality":90,"width":image.get_width(),"height":image.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
	panel.apply_button.pressed.emit();await settle();check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before.undo+1,"UI publishes whole migration once")
	identities(migrated,plan,"graded migration",args.residential.yaw)
	graph=City.resolve(editor._doc.map_meta).roads
	check(not graph.edges.any(func(e):return e.id==receipt.edge.id) and not graph.nodes.any(func(n):return n.id==receipt.door.id) and graph.nodes.any(func(n):return n.id==receipt.join.id),"remove_owned deletes only old terminal branch and retains public junction")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(same_authored_state(before.state,editor._doc.recovery_snapshot()),"one undo restores old house, terrain, access and receipt")
	await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"redo restores same identities and final authoring data")
	await call_tool("undo");plan=await call_tool("preview_residential_relocation",args);await call_tool("apply_residential_relocation",{"plan_token":plan.plan_token});after=editor._doc.recovery_snapshot()
	kerbs_mode=true;check_kerbs("applied",plan.changed_ids)
	editor._ground_batches.flush();await settle();var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().pending_groups>0 and Time.get_ticks_msec()<deadline:await process_frame
	manifest.editor_batch_stats=editor._ground_batches.stats();check(manifest.editor_batch_stats.pending_groups==0 and manifest.editor_batch_stats.source_surfaces>manifest.editor_batch_stats.render_surfaces,"migration retains actual shared static batching")
	check(plan.house_ids.all(func(uuid):return is_instance_valid(editor._view.get_node_or_null(uuid))),"all moved components remain individually addressable")
	await call_tool("duplicate_selection")
	var copies:Array=editor._doc.map_meta.building_instances.keys().filter(func(key):return not after.map_meta.building_instances.has(key))
	check(copies.size()==1 and not editor._doc.map_meta.building_instances[copies[0]].has("residential_access"),"native duplicate never copies access ownership")
	await call_tool("undo");check(same_authored_state(after,editor._doc.recovery_snapshot()),"duplicate verification undo retains final migration")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(saved_equal(after.records,editor._doc.records) and saved_equal(after.map_meta,editor._doc.map_meta),"native save/reopen retains migrated authoring state")
	check(Relocation.Binding.removal(City.resolve(editor._doc.map_meta).roads,editor._doc.map_meta.building_instances[id],editor._doc.map_meta.building_instances).ok,"new access receipt remains usable after save/reopen")
	check_kerbs("reopened",plan.changed_ids)
	var captured:Dictionary=Placement.Prefabs.capture(editor._doc.records.filter(func(r):return r.uuid in plan.house_ids),Library.new(directory.path_join("assets")),"迁移复制验证",editor._doc.map_meta.building_instances)
	check(captured.ok and not Placement.Prefabs.read(captured.entry).building_instances.values()[0].has("residential_access"),"exported building never carries map-local road ownership")
	check(editor._doc.validate_save()==OK and FileAccess.get_sha256(source.fixture)==source.map_sha256,"final native validation and untouched source map")
	manifest.plan=plan;manifest.road_points=plan.road_points;manifest.persistence={"max_numeric_delta":persistence_max_delta,"differences":persistence_differences};await finish()
