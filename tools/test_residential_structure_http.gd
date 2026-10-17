extends "res://tools/test_residential_relocation_http.gd"
const Structure=preload("res://tools/test_residential_structure.gd")
const G=preload("res://scripts/world3d/building_geometry.gd")

func raised_plan()->Dictionary:
	var plan:=Blueprint.generate({"layout":"townhouse","template":"house","width":9.,"depth":11.,"floors":1,"base_height":.3,"front_canopy":false,"chimney":false,"style":"plaster"})
	plan.records=plan.records.filter(func(r):return r.building.role!="foundation")
	for r:Dictionary in plan.records:r.position[1]+=2.2;r.building.floor_y+=2.2
	for x in [-4.,4.]:
		for z in [-5.,5.]:G.box(plan,"f0/pier_%s_%s"%[x,z],Vector3(x,.79,z),Vector3(1.,2.98,1.),[.5,.5,.5],0,"foundation")
	var steps:Array=plan.records.filter(func(r):return r.building.part.begins_with("f0/north/entry_step"))
	var outer:float=steps.map(func(r):return r.position[2]-r.size[2]*.5).min()
	for i in 15:
		var top:float=2.2*(15-i)/15.
		G.box(plan,"f0/exterior_step%d"%i,Vector3(-3.3,top*.5,outer-.19-.38*i),Vector3(2.15,top,.38),[.5,.5,.5],0,"entry_step")
	plan.position=[0.,0.,0.];plan.yaw=0.
	return plan

func run()->void:
	create_timer(900).timeout.connect(func():push_error("Structure HTTP timeout");quit(2));rpc_timeout_ms=120000;Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	directory=Paths.external_root().path_join("__residential_structure_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(directory)
	FileAccess.open(directory.path_join("metadata.json"),FileAccess.WRITE).store_string(JSON.stringify({"id":"residential_structure_%d"%OS.get_process_id(),"name":"临时住宅结构回归"}))
	map_path=directory.path_join("maps/test/map.gltf");var doc:=Doc.new();doc.records=[terrain()];doc.map_meta.editor_layout=City.defaults()
	doc.map_meta.editor_layout.roads={"nodes":[{"id":"a","position":[-15.,0.,-16.]},{"id":"b","position":[15.,0.,-16.]}],"edges":[{"id":"lane","from":"a","to":"b","width_start":3.5,"width_end":3.5,"kind":"ground"}]}
	check(doc.save(map_path)==OK,"private test map saves")
	Net.session().world3d_editor_path=map_path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");editor._material_directory=directory.path_join("materials");root.add_child(editor);await settle();editor._safety.enabled=false
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=34010
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"private current 3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(d):return d.name=="inspect_residential_entrances") and not definitions.any(func(d):return d.name=="paint_tile"),"current discovery contains entrance inspection only on active 3D")
	for name_ in ["preview_residential_placement","preview_residential_site","preview_residential_relocation","preview_residential_block"]:
		var schema:Dictionary=definitions.filter(func(d):return d.name==name_)[0].inputSchema
		var properties:Dictionary=schema.properties
		if name_.ends_with("block"):properties=properties.homes.items.properties.residential.properties
		elif name_!="preview_residential_placement":properties=properties.residential.properties
		check(properties.has("entrance_id") and properties.has("support_mode"),"shared entrance/support schema: "+name_)
	await reject("inspect_residential_entrances",{},"invalid_arguments")
	await reject("inspect_residential_entrances",{"building_id":"x","asset_id":"y"},"invalid_arguments")
	await call_tool("generate_road_surface",{"follow_terrain":true});await call_tool("save_world")
	var base:Dictionary=editor._doc.recovery_snapshot();manifest.cases=[]
	for kind in ["arch","multi","piers"]:
		restore(base)
		var made:Dictionary={}
		if kind=="piers":made=editor._buildings.commit([raised_plan()])
		else:
			var p:Dictionary=Structure.arch_parameters() if kind=="arch" else {"layout":"townhouse","template":"house","width":11.,"depth":14.,"floors":2,"compound":"rear_workshop","annex_floors":1,"base_height":.3,"front_canopy":false}
			made=await call_tool("generate_buildings",{"parameters":p,"placements":[{"position":[0.,0.,0.]}]})
		check(made.get("ok",false),kind+" regression fixture freezes through native building pipeline")
		if not made.get("ok",false):manifest.last_failure=made;await finish();return
		var id:String=made.building_ids[0];var member:String=editor._doc.map_meta.building_instances[id].parts.values()[0]
		await call_tool("select_objects",{"ids":[member]});var saved:=await call_tool("save_prefab",{"name":"临时结构 "+kind,"pack_root":directory})
		if not saved.get("ok",false):await finish();return
		await call_tool("delete_building",{"id":id})
		var inspect_args:Dictionary={"asset_id":saved.asset_id}
		if kind=="piers":inspect_args.support_mode="piers"
		var before:=snapshot();var inspected:=await call_tool("inspect_residential_entrances",inspect_args)
		same_snapshot(before,kind+" inspection does not change authoring/history/selection")
		check(inspected.entrances.size()>=1 and inspected.support.ok,kind+" actual entrances and support domains inspect successfully")
		var entrance_id:String=inspected.entrances.filter(func(e):return e.id=="f0/north/entrance/door" or e.id=="f0/north/entrance")[0].id
		var args:Dictionary=Placement.defaults().merged({"asset_id":saved.asset_id,"position":[0.,0.,0.],"road_edge_id":"lane","entrance_id":entrance_id},true)
		if kind=="piers":args.support_mode="piers";args.setback_min=7.;args.setback_max=8.
		await reject("preview_residential_placement",args.merged({"entrance_id":"missing"},true),"entrance_not_found")
		if kind=="multi":
			var ambiguous:=args.duplicate(true);ambiguous.erase("entrance_id");await reject("preview_residential_placement",ambiguous,"unsupported")
		var plan:=await call_tool("preview_residential_placement",args)
		if not plan.get("ok",false):manifest.last_failure=plan;manifest.case=kind;await finish();return
		check(plan.access.entrance_id==entrance_id,kind+" preview connects the explicit entrance")
		if kind=="multi":
			var block:=await call_tool("preview_residential_block",{"homes":[{"id":"explicit_entry","residential":args}]})
			check(block.get("ok",false) and block.homes[0].access.entrance_id==entrance_id,"block final validation reuses the explicit multi-door selection")
			if block.get("ok",false):await call_tool("discard_residential_block",{"plan_token":block.plan_token})
			var site:=await call_tool("preview_residential_site",{"residential":args,"terrain":{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":16.,"plot_depth":24.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":0.,"strength":1.,"blend_margin":1.,"cross_tiles":true}]}})
			check(site.get("ok",false) and site.access.entrance_id==entrance_id,"joint grading forwards explicit multi-door selection")
			if site.get("ok",false):await call_tool("discard_residential_site",{"plan_token":site.plan_token})
		var panel=editor._building_panel.residential;panel.refresh_catalogs();check(choose(panel.asset_choice,saved.asset_id) and choose(panel.road_choice,"lane"),kind+" UI selects source and road")
		choose(panel.support_choice,args.get("support_mode","auto"));panel.refresh_entrances();check(choose(panel.entrance_choice,entrance_id),kind+" UI selects same actual entrance")
		var form_args:=args.duplicate(true)
		for key in ["asset_id","road_edge_id","entrance_id","support_mode"]:form_args.erase(key)
		panel.form.update_values(form_args);check(equivalent(panel.request(),args),kind+" UI and HTTP share complete request")
		panel.preview_button.pressed.emit();await settle();check(panel.last_result.get("ok",false) and equivalent(result_geometry(panel.last_result),result_geometry(plan)),kind+" UI and HTTP preview same geometry")
		before=snapshot();panel.apply_button.pressed.emit();await settle();check(panel.last_result.get("ok",false) and editor._doc._undo.size()==before.undo+1,kind+" UI applies one transaction")
		plan=panel.last_result;var after:Dictionary=editor._doc.recovery_snapshot()
		await call_tool("undo");check(same_authored_state(before.state,editor._doc.recovery_snapshot()),kind+" one undo restores complete map")
		await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),kind+" redo preserves identities and semantic hints")
		var saved_path:=directory.path_join("maps/"+kind+"/map.gltf")
		check(editor._doc.save(saved_path)==OK,kind+" native atomic save succeeds")
		var reopened=Doc.open_file(saved_path);check(saved_equal(after.records,reopened.records) and saved_equal(after.map_meta,reopened.map_meta),kind+" native reopen preserves exact semantics and geometry")
		var proof:=Placement.Access.entrance(reopened.records.filter(func(r):return r.uuid in plan.house_ids),reopened.map_meta.building_instances[plan.building_id].yaw,entrance_id)
		check(proof.ok,kind+" saved selected entrance remains verifiable")
		if kind=="piers":
			check(reopened.map_meta.building_instances[plan.building_id].residential_support_mode=="piers" and plan.support.components.size()==4, "saved raised house retains four real pier domains")
			await reject("preview_terrain_layout",{"strokes":[{"id":"residential_ground","mode":"flatten","shape":"rectangle","points":[[0.,0.]],"plot_width":2.,"plot_depth":2.,"plot_yaw":0.,"plot_grade":[0.,0.],"target_height":1.,"strength":1.,"blend_margin":.5,"cross_tiles":true}]},"residential_support_height_limit")
			var moved:=await call_tool("preview_residential_relocation",{"residential":{"building_id":plan.building_id,"position":plan.building_position,"road_edge_id":"lane","entrance_id":entrance_id,"old_access":"remove_owned","setback_min":7.,"setback_max":8.}})
			check(moved.get("ok",false) and moved.support.support_mode=="piers","existing raised home inherits saved support mode during reliable relocation")
			if moved.get("ok",false):await call_tool("discard_residential_relocation",{"plan_token":moved.plan_token})
		if kind=="arch":
			await call_tool("select_objects",{"ids":plan.house_ids});await call_tool("focus_selection")
			for i in editor._dock_tabs.get_tab_count():
				if editor._dock_tabs.get_tab_control(i).is_ancestor_of(editor._building_panel):editor._dock_tabs.current_tab=i
			for toggle:Node in panel.find_children("","CheckButton",true,false):
				if toggle.text=="冻结住宅与入户路":toggle.button_pressed=true
			await call_tool("set_editor_camera",{"projection":"perspective","center":[-2.,1.,-5.],"distance":32.,"pitch":-25.,"yaw":-155.})
			await settle();await RenderingServer.frame_post_draw
			var parent:Node=panel.get_parent()
			while parent!=null:
				if parent is ScrollContainer:parent.ensure_control_visible(panel.entrance_choice);break
				parent=parent.get_parent()
			await settle();await RenderingServer.frame_post_draw
			var screenshot:=report_path.get_base_dir().path_join("ui.webp");var capture:=root.get_texture().get_image()
			check(capture.save_webp(screenshot,true,.9)==OK,"private UI screenshot saved as lossy Q90 WebP")
			FileAccess.open(report_path.get_base_dir().path_join("compression.json"),FileAccess.WRITE).store_string(JSON.stringify({"sha256":FileAccess.get_sha256(screenshot),"lossy":true,"quality":90,"width":capture.get_width(),"height":capture.get_height(),"encoder":"Godot Image.save_webp(lossy=true,quality=0.9)"},"\t"))
			manifest.screenshot=screenshot
		manifest.cases.append({"kind":kind,"fixture":saved_path,"map_sha256":FileAccess.get_sha256(saved_path),"source_path":saved.entry.prefab_path,"source_sha256":FileAccess.get_sha256(saved.entry.prefab_path),"request":args,"plan":plan})
	manifest.scope="Temporary native geometry fixtures only; no production models/maps changed. Exterior entrance and actual pier domains; no structural load rating."
	await finish()
