extends "res://tools/test_residential_placement_http.gd"
## E1-C uses the already validated frozen residential fixture, read-only.
## --source-report points to a passing residential HTTP report from that fixture.
const Placement=preload("res://scripts/world_editor/residential_placement_tools.gd")
const BridgeContext=preload("res://scripts/world_editor/residential_bridge_context.gd")
const Library=preload("res://scripts/world_editor/asset_library.gd")
var bridge_texture:=""
var persistence_max_delta:=0.
var persistence_differences:Array=[]

func saved_equal(a:Variant,b:Variant,path:String="")->bool:
	if (a is float or a is int) and (b is float or b is int):
		persistence_max_delta=maxf(persistence_max_delta,absf(float(a)-float(b)))
		if absf(float(a)-float(b))<=1e-10:return true
	elif a is Array and b is Array and a.size()==b.size():
		var same:=true
		for i in a.size():same=saved_equal(a[i],b[i],path+"/%d"%i) and same
		return same
	elif a is Dictionary and b is Dictionary and a.size()==b.size():
		var same:=true
		for key:Variant in a:same=(b.has(key) and saved_equal(a[key],b[key],path+"/"+str(key))) and same
		return same
	elif a==b:return true
	if persistence_differences.size()<10:persistence_differences.append({"path":path,"before":str(a).left(120),"after":str(b).left(120)})
	return false

func prism(at:Vector3,radius:float=.15)->Dictionary:
	var points:Array[Vector3]=[]
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:points.append(at+Vector3(x,y,z)*radius)
	return Placement.Foot.from_points(points)

func kerb_guard_cases(bridge:Dictionary)->void:
	var open:=prism(Vector3(17.,.2,-16.))
	check(Placement.Foot.overlaps(open,Placement.Foot.record_shape(bridge)) and not Placement._kerb_bridge_intersects(open,bridge,{}),"kerb volume inside broad bridge bounds can use actual open approach space")
	check(Placement._kerb_bridge_intersects(prism(Vector3(24.,.2,-16.)),bridge,{}),"kerb volume entering bridge body keeps conservative rejection")
	var unknown:=bridge.duplicate(true);unknown.erase("house_prefab")
	check(Placement._kerb_bridge_intersects(open,unknown,{}),"unknown frozen bridge collision cannot waive a kerb conflict")
	var face_found:=false;var blocked:=false
	for face:Dictionary in Placement.BridgeApproach.collision_faces(bridge).faces:
		var center:Vector3=(face.points[0]+face.points[1]+face.points[2])/3.
		if center.x>30.3:
			face_found=true;blocked=Placement._kerb_bridge_intersects(prism(center),bridge,{})
			if blocked:break
	check(face_found and blocked,"kerb volume touching actual frozen wing geometry remains rejected")

func restore(state:Dictionary)->void:
	editor._doc.apply_recovery(state)

func preserve(before:Dictionary,plan:Dictionary,label:String)->void:
	var data:=City.resolve(editor._doc.map_meta)
	var all_unchanged:=true
	for r:Dictionary in before.records:
		if r.has("road_source") and float(r.position[0])<70.:continue
		all_unchanged=all_unchanged and Placement._same(r,editor._doc._find(r.uuid)) and not plan.changed_ids.has(r.uuid)
	check(all_unchanged,label+": terrain, bridge, waterway and distant road values and identities preserved")
	check(Placement._same(data.waterways,before.map_meta.editor_layout.waterways),label+": waterway recipe and ownership preserved")
	var binding:Dictionary=data.roads.edges.filter(func(e):return e.id=="crossing")[0]
	check(Placement._same(binding,before.map_meta.editor_layout.roads.edges.filter(func(e):return e.id=="crossing")[0]),label+": native bridge binding and source signature preserved")

func run()->void:
	create_timer(420).timeout.connect(func():push_error("Residential bridges timeout");quit(2))
	rpc_timeout_ms=120000;Engine.max_fps=60
	root.size=Vector2i(1280,900);root.content_scale_size=root.size
	var source_report:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):report_path=argument.trim_prefix("--report=")
		if argument.begins_with("--source-report="):source_report=argument.trim_prefix("--source-report=")
	if source_report.is_empty():check(false,"--source-report is required; reuse a validated frozen house");await finish();return
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_report))
	check(source.get("failures",-1)==0 and FileAccess.file_exists(source.get("source_path","")),"passing residential fixture is available read-only")
	if failed:await finish();return
	directory=Paths.external_root().path_join("__residential_placement_bridges_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_bridges_%d"%OS.get_process_id(),"name":"临时含桥住宅回归"}))
	map_path=directory.path_join("maps/test/map.gltf")
	var doc:=Doc.new();var ground:=terrain();ground.position=[16.,0.,-2.];ground.size=[80.,1.,40.]
	doc.records=[ground]
	var far:=terrain();far.uuid="far_ground";far.position=[90.,0.,-2.];far.terrain_mesh.columns=16;far.terrain_mesh.rows=16;far.terrain_mesh.heights.resize(289);far.terrain_mesh.holes.resize(256);doc.records.append(far)
	var river_ground:=doc.add_box("ground",Vector3(160.,-.25,0.),Vector3(60.,.5,60.))
	doc.map_meta.editor_layout=City.defaults()
	doc.map_meta.editor_layout.roads={"nodes":[{"id":"main_a","position":[-12.,0.,-16.]},{"id":"main_b","position":[12.,0.,-16.]},{"id":"bridge_b","position":[36.,0.,-16.]},{"id":"far_a","position":[78.,0.,-12.]},{"id":"far_b","position":[102.,0.,-12.]}],"edges":[{"id":"main_lane","from":"main_a","to":"main_b","width_start":3.5,"width_end":3.5,"kind":"ground"},{"id":"crossing","from":"main_b","to":"bridge_b","width_start":4.,"width_end":4.,"kind":"bridge"},{"id":"far_lane","from":"far_a","to":"far_b","width_start":3.5,"width_end":3.5,"kind":"ground"}]}
	check(doc.save(map_path)==OK,"disposable native map saved outside scene checkout")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials")
	root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var source_assets:String=source.source_path.get_base_dir().get_base_dir()
	editor._shared_assets=[Library.new(source_assets)]
	var probe:=TCPServer.new();port=32550
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"independent loopback HTTP service starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var definitions:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	check(["preview_residential_placement","apply_residential_placement","discard_residential_placement"].all(func(name_):return definitions.any(func(d):return d.name==name_)) and not definitions.any(func(d):return d.name=="paint_tile"),"current 3D residential tools discovered; retired 2D stays absent")
	var image:=Image.create(8,8,false,Image.FORMAT_RGB8);image.fill(Color(.7,.67,.6))
	var texture:=directory.path_join("fixture.png");image.save_png(texture)
	var imported:=await call_tool("import_surface_material",{"path":texture,"name":"临时桥梁回归材质"})
	if not imported.get("ok",false):await finish();return
	bridge_texture=editor._material_tool.library.find(imported.material_id).texture_path
	var made:=await call_tool("generate_bridge",{"id":"fixture_bridge","road_edge_id":"crossing","prefab_id":"stone_segmental","start":[18.,.025,-16.],"end":[30.,.025,-16.],"width":5.2,"depth":2.,"camber":.25,"arches":1,"wing_length":1.5,"deck_material_id":imported.material_id,"masonry_material_id":imported.material_id,"trim_material_id":imported.material_id})
	if not made.get("ok",false):await finish();return
	check(editor._doc._find("fixture_bridge").has("house_prefab"),"existing native bridge recipe uses frozen geometry")
	kerb_guard_cases(editor._doc._find("fixture_bridge"))
	await call_tool("generate_waterway",{"id":"river","ground_ids":[river_ground],"points":[[160.,-24.],[160.,24.]],"bridges":[{"id":"crossing","segment":0,"t":.5,"width":5.,"approach":3.,"rail_height":1.1}],"water_drop":1.2})
	var river_link:=await call_tool("connect_waterway_bridge",{"waterway_id":"river","bridge_id":"crossing"})
	if not river_link.get("ok",false):await finish();return
	kerbs_mode=true;var kerb_id:=await kerb_material()
	var road:=await call_tool("generate_road_surface",{"follow_terrain":true,"kerb_enabled":true,"kerb_material_id":kerb_id})
	if not road.get("ok",false):await finish();return
	check_kerbs("generated")
	await call_tool("save_world")
	var baseline:=snapshot();var original:Dictionary=baseline.state
	var args:Dictionary={"asset_id":source.asset_id,"position":[0.,0.,0.],"road_edge_id":"main_lane","setback_min":.8,"setback_max":3.,"width":1.6}
	manifest.merge({"source_path":source.source_path,"source_sha256":FileAccess.get_sha256(source.source_path),"asset_id":source.asset_id,"request":args,"bridge_texture":bridge_texture},true)
	var plan:=await call_tool("preview_residential_placement",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	same_snapshot(baseline,"preview of mixed stone_bridge and bridge_ref graph has no authored side effects")
	check(plan.bridges.binding_count==2 and plan.bridges.waterway_count==1 and plan.checks.bridge_context,"preview reports verified mixed bridge ownership")
	check(not plan.changed_ids.has("fixture_bridge") and not plan.changed_ids.any(func(id):return plan.bridges.preserved_ids.has(id)),"bridge and river records are excluded from write set")
	await reject("preview_residential_placement",args.merged({"road_edge_id":"crossing"},true),"unsupported")
	await reject("preview_residential_placement",args.merged({"road_edge_id":river_link.edge_id},true),"unsupported")
	# Align the entrance's projected join with the native bridge's original node.
	var entry_x:float=plan.road_points[1][0]
	var bridgehead:=await reject("preview_residential_placement",args.merged({"position":[12.-entry_x,0.,0.],"setback_min":3.,"setback_max":3.},true),"search_exhausted")
	check(bridgehead.get("last_failure",{}).get("code")=="bridgehead_target","direct bridgehead join is explained, not silently replanned")
	for field:String in ["editor_locked","editor_hidden"]:
		editor._doc._find("fixture_bridge")[field]=true
		await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!="fixture_bridge")
	await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	editor._doc._find("fixture_bridge").position[0]+=.1
	await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	var river_part:String=original.map_meta.editor_layout.waterways[0].parts[0].id
	editor._doc._find(river_part).editor_locked=true
	await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	editor._doc._find(river_part).position[1]+=.1
	await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	for mutation:String in ["endpoint","width"]:
		var data:Dictionary=editor._doc.map_meta.editor_layout
		if mutation=="endpoint":data.roads.nodes.filter(func(n):return n.id=="main_b")[0].position[0]+=.1
		else:data.roads.edges.filter(func(e):return e.id==river_link.edge_id)[0].width_start+=1.
		data.road_surface.graph_token=City.token(data.roads)
		await reject("preview_residential_placement",args,"bridge_context_invalid");restore(original)
	# Test actual bridge-only external dependencies; roads use a separate default.
	var texture_bytes:=FileAccess.get_file_as_bytes(bridge_texture)
	plan=await call_tool("preview_residential_placement",args)
	FileAccess.open(bridge_texture,FileAccess.WRITE).store_buffer(texture_bytes+PackedByteArray([0]))
	await reject("apply_residential_placement",{"plan_token":plan.plan_token},"source_changed")
	FileAccess.open(bridge_texture,FileAccess.WRITE).store_buffer(texture_bytes)
	check(FileAccess.get_sha256(source.source_path)==manifest.source_sha256,"validated residential source remains unchanged")
	var blocked:String=editor._doc.add_box("block",Vector3(0.,1.,-10.),Vector3(16.,2.,1.))
	var blocked_result:=await reject("preview_residential_placement",args.merged({"setback_min":3.,"setback_max":3.},true))
	check(not blocked_result.get("ok",false),"real obstacle across new access corridor still rejects")
	check(not blocked.is_empty(),"blocker is a real temporary authored record");restore(original)
	var panel=editor._building_panel.residential;panel.refresh_catalogs()
	check(choose(panel.asset_choice,source.asset_id) and choose(panel.road_choice,"main_lane"),"UI offers ordinary ground target inside mixed bridge graph")
	check(not choose(panel.road_choice,"crossing") and not choose(panel.road_choice,river_link.edge_id),"UI filters both bound bridge target kinds using shared predicate")
	var ui_args:Dictionary=Placement.defaults().merged(args,true);ui_args.erase("asset_id");ui_args.erase("road_edge_id");panel.form.update_values(ui_args)
	plan=await call_tool("preview_residential_placement",args)
	var before_ui:=snapshot();panel.preview_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and equivalent(result_geometry(plan),result_geometry(panel.last_result)) and equivalent(plan.bridges,panel.last_result.get("bridges",{})),"actual UI preview and HTTP share geometry and bridge checks")
	same_snapshot(before_ui,"UI bridge-aware preview stays private")
	check(panel.feedback.text.contains("2 处桥梁"),"UI reports preserved bridge bindings")
	panel.apply_button.pressed.emit();await settle()
	check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before_ui.undo+1,"UI commits house and access road once")
	preserve(original,plan,"UI apply")
	await call_tool("undo");check(same_authored_state(before_ui.state,editor._doc.recovery_snapshot()),"HTTP undo reverses UI transaction including road graph")
	var before_apply:=snapshot();plan=await call_tool("preview_residential_placement",args)
	if not plan.get("ok",false):manifest.last_failure=plan;await finish();return
	await call_tool("apply_residential_placement",{"plan_token":plan.plan_token})
	check(editor._doc._undo.size()==before_apply.undo+1,"HTTP commits one native transaction")
	preserve(original,plan,"HTTP apply");check_kerbs("applied",plan.changed_ids)
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(same_authored_state(before_apply.state,editor._doc.recovery_snapshot()),"undo restores full mixed bridge graph")
	await call_tool("redo");check(Placement._same(after,editor._doc.recovery_snapshot()),"redo restores exact identities and values")
	editor._ground_batches.flush();await settle()
	var deadline:=Time.get_ticks_msec()+60000
	while editor._ground_batches.stats().get("pending_groups",0)>0 and Time.get_ticks_msec()<deadline:await process_frame
	manifest.editor_batch_stats=editor._ground_batches.stats()
	check(manifest.editor_batch_stats.pending_groups==0 and manifest.editor_batch_stats.source_surfaces>manifest.editor_batch_stats.render_surfaces,"shared static rendering completes with actual surface reduction")
	check(plan.house_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id))),"all house members retain editable identity after batching")
	await call_tool("save_world");await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(saved_equal(after.records,editor._doc.records,"records") and saved_equal(after.map_meta,editor._doc.map_meta,"metadata"),"native save/reopen retains house, road, bridge and river authored values within 1e-10 serialization precision")
	manifest.persistence={"max_numeric_delta":persistence_max_delta,"differences":persistence_differences}
	preserve(original,plan,"reopen");check_kerbs("reopened",plan.changed_ids)
	check(editor._doc.validate_save()==OK,"reopened mixed bridge map passes native save validation")
	manifest.plan=plan;manifest.road_points=plan.road_points
	await finish()
