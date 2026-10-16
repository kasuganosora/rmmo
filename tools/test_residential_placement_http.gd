extends "res://tools/test_world3d_mcp.gd"
## Disposable integration fixture. Run graphical verification only on the private desktop.
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const City = preload("res://scripts/world3d/city_layout.gd")
const Net = preload("res://scripts/net/net.gd")
const Kerb = preload("res://scripts/world3d/road_kerb.gd")
const Paint = preload("res://scripts/world3d/surface_materials.gd")
var directory := ""
var map_path := ""
var report_path := ""
var checks: Array = []
var manifest: Dictionary = {}
var started_ms:=Time.get_ticks_msec()
var kerbs_mode:=false

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	super.check(ok,label)

func terrain() -> Dictionary:
	var heights: Array = []; heights.resize(65*65); heights.fill(0.0)
	var holes: Array = []; holes.resize(64*64); holes.fill(false)
	return {"uuid":"residential_ground","kind":"box","surface_id":"ground","position":[0.0,0.0,-2.0],"rotation":[0,0,0],"size":[40.0,1.0,40.0],"color":[.3,.4,.2],"collision":"walk","terrain_mesh":{"version":1,"columns":64,"rows":64,"floor":-8.0,"heights":heights,"holes":holes}}

func snapshot() -> Dictionary:
	return {"state":editor._doc.recovery_snapshot(),"undo":editor._doc._undo.size(),"redo":editor._doc._redo.size(),"history":history_signature(),"selection":editor._selection_tools.ids.duplicate(),"dirty":editor._doc.editor_dirty}

func history_signature() -> String:
	var hashing:=HashingContext.new(); hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes([editor._doc._undo,editor._doc._redo]))
	return hashing.finish().hex_encode()

func same_snapshot(before: Dictionary, label: String) -> void:
	check(equivalent(before.state,editor._doc.recovery_snapshot()) and before.undo==editor._doc._undo.size() and before.redo==editor._doc._redo.size() and before.history==history_signature() and before.selection==editor._selection_tools.ids and before.dirty==editor._doc.editor_dirty,label)

func same_authored_state(a: Dictionary, b: Dictionary) -> bool:
	# Native undo deliberately never reuses allocated object IDs.
	var first:=a.duplicate(true); var second:=b.duplicate(true)
	first.erase("next"); second.erase("next")
	return equivalent(first,second)

func reject(name_: String, args: Dictionary, code: String = "") -> Dictionary:
	var before := snapshot()
	var result := await call_tool(name_,args,false)
	if not code.is_empty():
		check(result.get("code","")==code,"specific rejection: "+code)
		if result.get("code","")!=code: print("REJECTION_DIAGNOSTIC ",JSON.stringify(result))
	same_snapshot(before,"rejection is atomic: "+name_)
	return result

func result_geometry(result: Dictionary) -> Dictionary:
	var value: Dictionary = {}
	for key in ["position","adjustment","road_points","setback","width","support","checks","bounds"]:
		value[key]=result.get(key)
	return value

func choose(menu: OptionButton, id: String) -> bool:
	for index in menu.item_count:
		if str(menu.get_item_metadata(index))==id: menu.select(index); return true
	return false

func kerb_material() -> String:
	# Only this disposable editor library changes lookup scope. Shared native
	# materials are read-only; a fallback is imported inside the unique pack.
	editor._material_tool.library.include_shared=true
	var id:String=Kerb.defaults().kerb_material_id
	var material:Dictionary=editor._material_tool.library.find(id)
	if not material.is_empty() and Paint.material_valid(material) and material.color[3]==1 and Paint.missing([{"road_kerb_material":material}]).is_empty():
		manifest.kerb_material={"id":id,"source":"native_default"}
		return id
	var image:=Image.create(8,8,false,Image.FORMAT_RGB8);image.fill(Color(.7,.67,.6))
	var source:=directory.path_join("kerb_fixture.png")
	check(image.save_png(source)==OK,"fallback kerb texture is confined to the unique temporary pack")
	var imported:=await call_tool("import_surface_material",{"path":source,"name":"临时住宅路缘材质"})
	if not imported.get("ok",false):return ""
	id=str(imported.material_id)
	manifest.kerb_material={"id":id,"source":"temporary_fixture","texture":source}
	return id

func check_kerbs(stage:String,changed_ids:Array=[]) -> void:
	if not kerbs_mode:return
	var roads:Array=editor._doc.records.filter(func(record):return not record.get("road_mesh",{}).get("kerbs",[]).is_empty())
	var profiles:=0;var vertices:=0;var details:Array=[]
	for record:Dictionary in roads:
		var arrays:Array=Kerb.arrays(record)
		var count:int=arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX]!=null else 0
		profiles+=record.road_mesh.kerbs.size();vertices+=count
		details.append({"id":record.uuid,"kerbs":record.road_mesh.kerbs,"material":record.get("road_kerb_material",{}),"vertices":count})
	details.sort_custom(func(a,b):return a.id<b.id)
	check(City.resolve(editor._doc.map_meta).road_surface.settings.get("kerb_enabled",false) and profiles>0 and vertices>0,stage+" retains actual native kerb profiles and mesh vertices")
	check(not roads.is_empty() and roads.all(func(record):return Paint.material_valid(record.get("road_kerb_material",{})) and Paint.missing([record]).is_empty()),stage+" retains valid kerb material dependencies")
	if not changed_ids.is_empty():check(roads.any(func(record):return changed_ids.has(record.uuid)),stage+" includes kerbs in the changed house-approach road scope")
	if not manifest.has("kerb_stages"):manifest.kerb_stages={}
	manifest.kerb_stages[stage]={"records":details,"profiles":profiles,"vertices":vertices}
	if stage=="reopened":check(equivalent(manifest.kerb_stages.applied,manifest.kerb_stages.reopened),"native save/reopen preserves actual kerb geometry and material identity")

func finish() -> void:
	manifest.merge({"failures":failed,"checks":checks,"fixture":map_path,"directory":directory,"graphical":DisplayServer.get_name()!="headless","kerbs_mode":kerbs_mode,"runtime_verified":false,"elapsed_ms":Time.get_ticks_msec()-started_ms},true)
	if not map_path.is_empty() and FileAccess.file_exists(map_path): manifest.map_sha256=FileAccess.get_sha256(map_path)
	if report_path.is_empty(): report_path=directory.path_join("http_result.json")
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(manifest,"  ")); file.close()
	if is_instance_valid(editor):
		if editor._mcp!=null: editor._mcp.stop()
		editor.queue_free(); await settle()
	Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""
	print("RESIDENTIAL_PLACEMENT_HTTP ",report_path," failures=",failed)
	quit(1 if failed else 0)

func run() -> void:
	create_timer(420).timeout.connect(func():push_error("Residential HTTP timeout");quit(2))
	rpc_timeout_ms=120000; Engine.max_fps=60
	root.size=Vector2i(1280,900); root.content_scale_size=root.size
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path=argument.trim_prefix("--report=")
		elif argument=="--kerbs":kerbs_mode=true
	directory=Paths.external_root().path_join("__residential_placement_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata:=FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"id":"residential_test_%d"%OS.get_process_id(),"name":"临时住宅可靠安放测试"})); metadata.close()
	map_path=directory.path_join("maps/test/map.gltf")
	var doc:=Doc.new(); doc.records=[terrain()]
	var far_ground:=terrain(); far_ground.uuid="untouched_ground"; far_ground.position=[60.,0.,-2.]
	far_ground.terrain_mesh.columns=16; far_ground.terrain_mesh.rows=16
	far_ground.terrain_mesh.heights.resize(17*17); far_ground.terrain_mesh.holes.resize(16*16)
	doc.records.append(far_ground)
	var sentinel:String=doc.add_box("block",Vector3(60,1,10),Vector3(2,2,2))
	doc.map_meta.editor_layout=City.defaults()
	doc.map_meta.editor_layout.roads={"nodes":[{"id":"main_a","position":[-12.,0.,-16.]},{"id":"main_b","position":[12.,0.,-16.]},{"id":"far_a","position":[48.,0.,-12.]},{"id":"far_b","position":[72.,0.,-12.]}],"edges":[{"id":"main_lane","from":"main_a","to":"main_b","width_start":3.5,"width_end":3.5,"kind":"ground"},{"id":"untouched_lane","from":"far_a","to":"far_b","width_start":3.5,"width_end":3.5,"kind":"ground"}]}
	check(doc.save(map_path)==OK,"unique temporary pack and map saved")
	Net.session().world3d_editor_path=map_path; Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts"); editor._material_directory=directory.path_join("materials")
	root.add_child(editor); await settle(); editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active: await process_frame
	var probe:=TCPServer.new(); port=32150
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real 3D loopback HTTP starts")
	await rpc("initialize",{"protocolVersion":"2025-03-26"})
	var definitions:Array=(await rpc("tools/list")).get("result",{}).get("tools",[])
	var names:Array=definitions.map(func(value):return value.name)
	check(["preview_residential_placement","apply_residential_placement","discard_residential_placement"].all(func(value):return names.has(value)) and not names.has("paint_tile"),"all residential tools discovered on current 3D service")
	if not names.has("preview_residential_placement"): await finish(); return
	var road_options:={"follow_terrain":true}
	if kerbs_mode:
		road_options.kerb_enabled=true;road_options.kerb_material_id=await kerb_material()
		if road_options.kerb_material_id.is_empty():await finish();return
	var generated:=await call_tool("generate_road_surface",road_options)
	if not generated.get("ok",false):await finish();return
	check_kerbs("generated")
	var parameters:Dictionary=Blueprint.defaults().merged({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"floor_height":3.5,"base_height":.3,"foundation_depth":1.,"style":"plaster","roof_axis":"depth","roof_pitch":36.,"chimney":false,"front_canopy":false},true)
	var made:=await call_tool("generate_buildings",{"parameters":parameters,"placements":[{"position":[0.,0.,0.]}]})
	if not made.get("ok",false): await finish(); return
	var author_id:String=made.building_ids[0]
	var member:String=editor._doc.map_meta.building_instances[author_id].parts.values()[0]
	await call_tool("select_objects",{"ids":[member]})
	var saved:=await call_tool("save_prefab",{"name":"临时可靠住宅","pack_root":directory})
	if not saved.get("ok",false): await finish(); return
	await call_tool("delete_building",{"id":author_id})
	var args:Dictionary={"asset_id":saved.asset_id,"position":[0.,0.,0.],"road_edge_id":"main_lane","yaw":0.,"elevation_min":-.5,"elevation_max":.5,"setback_min":.8,"setback_max":3.,"width":1.6}
	manifest.merge({"asset_id":saved.asset_id,"source_path":saved.entry.prefab_path,"request":args},true)
	await call_tool("save_world")
	var baseline:=snapshot()
	var far_records:Array=editor._doc.records.filter(func(value):return float(value.position[0])>40.).duplicate(true)
	check(far_records.any(func(value):return value.has("road_source")),"scope sentinel includes actual generated distant road records")
	var original_terrain:Dictionary=editor._doc._find("residential_ground").duplicate(true)
	var plan:=await call_tool("preview_residential_placement",args)
	if not plan.get("ok",false): manifest.last_failure=plan;await finish(); return
	manifest.first_search=plan.search
	manifest.house_component_count=plan.house_ids.size()
	check(plan.house_ids.size()>32,"candidate preserves more than 32 house components for a single private-document publication")
	same_snapshot(baseline,"preview does not mutate map or history")
	check(not str(plan.get("source_sha256","")).is_empty() and not str(plan.get("plan_token","")).is_empty() and plan.get("road_points",[]).size()==2,"preview returns source identity and a concrete house-road plan")
	var again:=await call_tool("preview_residential_placement",args)
	check(equivalent(result_geometry(plan),result_geometry(again)),"same inputs produce the same constrained geometry")
	await call_tool("discard_residential_placement",{"plan_token":again.plan_token})
	await reject("apply_residential_placement",{"plan_token":again.plan_token})
	await reject("preview_residential_placement",args.merged({"asset_id":"missing_asset"},true))
	await reject("preview_residential_placement",args.merged({"road_edge_id":"missing_edge"},true))
	await reject("preview_residential_placement",args.merged({"width":-1.},true))
	await reject("apply_residential_placement",{"plan_token":"unknown","changed_ids":[sentinel]})
	var ordinary_graph:Dictionary=editor._doc.recovery_snapshot()
	var locked_graph:Dictionary=ordinary_graph.duplicate(true)
	for edge:Dictionary in locked_graph.map_meta.editor_layout.roads.edges:
		if edge.id=="main_lane":edge.locked=true
	editor._doc.apply_recovery(locked_graph)
	await reject("preview_residential_placement",args,"stale_road_surface")
	check(editor._residential._target(locked_graph.map_meta.editor_layout.roads,"main_lane").get("code")=="protected_scope","pure target check refuses a locked edge before any geometry work")
	editor._doc.apply_recovery(ordinary_graph)
	var curved_graph:Dictionary=ordinary_graph.duplicate(true)
	for edge:Dictionary in curved_graph.map_meta.editor_layout.roads.edges:
		if edge.id=="main_lane":edge.controls=[[-4.,0.,-16.],[4.,0.,-16.]]
	editor._doc.apply_recovery(curved_graph)
	await reject("preview_residential_placement",args,"stale_road_surface")
	check(editor._residential._target(curved_graph.map_meta.editor_layout.roads,"main_lane").get("code")=="unsupported","pure target check identifies curved roads as unsupported")
	editor._doc.apply_recovery(ordinary_graph)
	var city_state:=await call_tool("get_city_layout")
	await call_tool("update_planning_zones",{"expected_token":city_state.zone_token,"zones":[{"id":"residential_access_reserve","purpose":"no_build","polygon":[[-4.4,-11.],[-2.4,-11.],[-2.4,-9.],[-4.4,-9.]],"min_y":-1.,"max_y":3.}]})
	var zone_failure:=await reject("preview_residential_placement",args,"search_exhausted")
	check(zone_failure.get("last_failure",{}).get("code","")=="reserved_zone","candidate connector respects the reserved area outside the house")
	await call_tool("undo")
	var stale:=await call_tool("preview_residential_placement",args)
	if not stale.get("ok",false): manifest.last_failure=stale;await finish();return
	await call_tool("set_object_properties",{"ids":[sentinel],"name":"version changes outside the proposal"})
	await reject("apply_residential_placement",{"plan_token":stale.plan_token},"base_changed")
	await call_tool("undo")
	var aba:=await call_tool("preview_residential_placement",args)
	if not aba.get("ok",false): manifest.last_failure=aba;await finish();return
	var before_aba:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("set_object_properties",{"ids":[sentinel],"name":"ABA history must invalidate an old candidate"})
	await call_tool("undo")
	check(same_authored_state(before_aba,editor._doc.recovery_snapshot()),"edit then undo restores authored input before stale-candidate check")
	await reject("apply_residential_placement",{"plan_token":aba.plan_token},"base_changed")
	var history_aba:=await call_tool("preview_residential_placement",args)
	if not history_aba.get("ok",false): manifest.last_failure=history_aba;await finish();return
	var before_history_aba:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo"); await call_tool("redo")
	check(same_authored_state(before_history_aba,editor._doc.recovery_snapshot()),"undo then redo restores identical authored content")
	await reject("apply_residential_placement",{"plan_token":history_aba.plan_token},"base_changed")
	var switched:=await call_tool("preview_residential_placement",args)
	if not switched.get("ok",false): manifest.last_failure=switched;await finish();return
	var old_document:int=editor._doc.get_instance_id()
	await call_tool("open_world",{"path":map_path,"discard_changes":true})
	while editor._load_job!=null and editor._load_job.active:await process_frame
	check(editor._doc.get_instance_id()!=old_document,"reopening the same source creates a distinct document instance")
	await reject("apply_residential_placement",{"plan_token":switched.plan_token},"base_changed")
	var changed_source:=await call_tool("preview_residential_placement",args)
	if not changed_source.get("ok",false): manifest.last_failure=changed_source;await finish();return
	var source_path:String=saved.entry.prefab_path
	var source_bytes:=FileAccess.get_file_as_bytes(source_path)
	var altered:=FileAccess.open(source_path,FileAccess.WRITE); altered.store_buffer(source_bytes); altered.store_string("\n"); altered.close()
	await reject("apply_residential_placement",{"plan_token":changed_source.plan_token},"source_changed")
	var restored:=FileAccess.open(source_path,FileAccess.WRITE); restored.store_buffer(source_bytes); restored.close()
	check(FileAccess.get_sha256(source_path)==changed_source.source_sha256,"source fixture restored byte for byte")
	# Deliberate fixture ingress: a single interior terrain cell, away from corners.
	var intact:Dictionary=editor._doc.recovery_snapshot()
	var punctured:Dictionary=intact.duplicate(true)
	for record:Dictionary in punctured.records:
		if record.uuid=="residential_ground": record.terrain_mesh.holes[37*64+34]=true
	editor._doc.apply_recovery(punctured)
	var hole_failure:=await reject("preview_residential_placement",args.merged({"elevation_min":0.,"elevation_max":0.},true),"residential_support_coverage_gap")
	check(float(hole_failure.get("uncovered_area",hole_failure.get("missing_area",0.)))>0. and hole_failure.get("terrain_id","")=="residential_ground","narrow interior hole reports a positive uncovered area and the actual terrain")
	editor._doc.apply_recovery(intact)
	await reject("preview_residential_placement",args.merged({"position":[0.,-4.,0.],"elevation_min":0.,"elevation_max":0.},true),"residential_support_height_limit")
	var before_elevation:=snapshot()
	var elevated:=await call_tool("preview_residential_placement",args.merged({"position":[0.,.4,0.]},true))
	if not elevated.get("ok",false):manifest.last_failure=elevated;await finish();return
	check(float(elevated.adjustment[1])<0. and float(elevated.position[1])>=-.100001 and float(elevated.position[1])<.4 and elevated.checks.entrance_corridor,"a high request is lowered within its allowed interval to meet the actual doorstep")
	same_snapshot(before_elevation,"bounded elevation correction is preview-only")
	manifest.elevation_correction={"requested_y":.4,"position":elevated.position,"adjustment":elevated.adjustment,"support":elevated.support}
	var panel=editor._building_panel.residential
	panel.refresh_catalogs()
	check(choose(panel.asset_choice,saved.asset_id) and choose(panel.road_choice,"main_lane"),"UI exposes the same native source and target road")
	var ui_values:Dictionary=args.duplicate(true); ui_values.erase("asset_id"); ui_values.erase("road_edge_id")
	panel.form.update_values(ui_values)
	panel.preview_button.pressed.emit(); await settle()
	check(panel.last_result.get("ok",false) and equivalent(result_geometry(panel.last_result),result_geometry(plan)),"actual UI preview button agrees with HTTP for identical inputs")
	check(not panel.plan_token.is_empty() and is_instance_valid(panel.ghost),"UI owns an inspectable preview without authored geometry")
	panel.discard_button.pressed.emit(); await settle()
	check(panel.plan_token.is_empty() and panel.apply_button.disabled and not is_instance_valid(panel.ghost),"UI discard removes ghost and apply authority")
	panel.preview_button.pressed.emit(); await settle()
	var width_control:SpinBox=panel.form.fields.width
	width_control.value=1.7
	check(panel.plan_token.is_empty() and panel.apply_button.disabled and not is_instance_valid(panel.ghost),"editing a real UI field invalidates the candidate immediately")
	width_control.value=1.6
	var before_ui:=snapshot()
	panel.preview_button.pressed.emit(); await settle()
	panel.apply_button.pressed.emit(); await settle()
	check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before_ui.undo+1 and panel.plan_token.is_empty() and not is_instance_valid(panel.ghost),"actual UI apply button commits the complete transaction once")
	await call_tool("undo")
	check(same_authored_state(before_ui.state,editor._doc.recovery_snapshot()),"UI-applied candidate is undone by the same HTTP undo operation")
	var before_apply:=snapshot()
	var far_before_apply:Array=editor._doc.records.filter(func(value):return float(value.position[0])>40.).duplicate(true)
	var far_before_bytes:=var_to_bytes(far_before_apply)
	plan=await call_tool("preview_residential_placement",args)
	if not plan.get("ok",false): manifest.last_failure=plan;await finish();return
	var applied:=await call_tool("apply_residential_placement",{"plan_token":plan.plan_token})
	if not applied.get("ok",false): await finish(); return
	check(editor._doc._undo.size()==before_apply.undo+1,"house and complete approach are one undo transaction")
	check(equivalent(original_terrain,editor._doc._find("residential_ground")),"automatic placement leaves every terrain sample and hole unchanged")
	check(equivalent(far_records,editor._doc.records.filter(func(value):return float(value.position[0])>40.)),"scope-external objects and native distant roads preserve authored values across reopen")
	check(far_before_bytes==var_to_bytes(editor._doc.records.filter(func(value):return float(value.position[0])>40.)),"scope-external loaded records remain identical in memory including numeric types")
	check(far_before_apply.all(func(value):return not plan.changed_ids.has(value.uuid)),"candidate changed_ids exclude every scope-external object and road")
	var graph:Dictionary=City.resolve(editor._doc.map_meta).roads
	check(equivalent(graph.edges.filter(func(value):return value.id=="untouched_lane"),baseline.state.map_meta.editor_layout.roads.edges.filter(func(value):return value.id=="untouched_lane")),"scope-external authored road edge remains unchanged")
	check(editor._buildings.instances().has(plan.building_id),"committed house keeps native building identity")
	check_kerbs("applied",plan.changed_ids)
	var after:Dictionary=editor._doc.recovery_snapshot()
	await reject("apply_residential_placement",{"plan_token":plan.plan_token})
	await call_tool("undo"); check(same_authored_state(before_apply.state,editor._doc.recovery_snapshot()),"undo restores complete map, graph and metadata without reusing object IDs")
	await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores exact house, road and stable identities")
	editor._ground_batches.flush(); await settle(); await physics_frame; await physics_frame
	var house_member:String=plan.house_ids[0]
	await call_tool("select_objects",{"ids":[house_member]})
	check(plan.house_ids.all(func(value):return editor._selection_tools.ids.has(value)),"picking identity expands into whole-house selection")
	var door_records:Array=editor._doc.records.filter(func(value):return value.get("building",{}).get("id")==plan.building_id and value.get("fixture",{}).get("kind")=="door")
	check(not door_records.is_empty(),"native moving doors remain independent semantic records")
	check(plan.house_ids.all(func(id):return is_instance_valid(editor._view.get_node_or_null(id))),"every house member retains an independent editor node after batching")
	check(door_records.all(func(record):return is_instance_valid(editor._view.get_node_or_null(record.uuid)) and not editor._bodies_by_uuid.get(record.uuid,[]).is_empty()),"moving door nodes keep their own collision identities")
	if DisplayServer.get_name()!="headless":
		await call_tool("focus_selection")
		await settle(); await physics_frame
		var picked:=false
		for id:String in plan.house_ids:
			var record:Dictionary=editor._doc._find(id)
			for point:Vector3 in Geometry.corners(record):
				var pixel:Vector2=editor._camera.unproject_position(point)
				if plan.house_ids.has(editor._pick_object(pixel)): picked=true; break
			if picked: break
		check(picked,"actual editor camera ray picks committed house geometry")
	var batch_deadline:=Time.get_ticks_msec()+60000
	while int(editor._ground_batches.stats().get("pending_groups",0))>0 and Time.get_ticks_msec()<batch_deadline:await process_frame
	var batch_stats:Dictionary=editor._ground_batches.stats()
	check(int(batch_stats.get("pending_groups",-1))==0,"editor static preparation finishes before measuring batching")
	check(batch_stats.get("enabled",false) and int(batch_stats.get("groups",0))>0 and int(batch_stats.get("source_surfaces",0))>int(batch_stats.get("render_surfaces",0)),"actual editor batching reduces render surfaces with independent members retained")
	manifest.editor_batch_stats=batch_stats
	await call_tool("save_world")
	await call_tool("open_world",{"path":map_path})
	while editor._load_job!=null and editor._load_job.active: await process_frame
	check(equivalent(after.records,editor._doc.records) and equivalent(after.map_meta,editor._doc.map_meta),"native save/reopen preserves full transaction")
	check_kerbs("reopened",plan.changed_ids)
	manifest.merge({"plan":plan,"asset_id":saved.asset_id,"source_path":source_path,"house_id":plan.building_id,"house_ids":plan.house_ids,"road_points":plan.road_points,"parameters":parameters},true)
	await finish()
