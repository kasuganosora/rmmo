extends "res://tools/test_world3d_buildings.gd"

func run() -> void:
	create_timer(480).timeout.connect(func(): push_error("Urban building test timeout"); quit(2))
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("urban_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(45,-.1,15),Vector3(160,.2,100)); check(doc.save(path)==OK,"create isolated urban fixture")
	Net.session().world3d_editor_path=path; Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await physics(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"real HTTP MCP starts")
	var discovery:=await rpc("tools/list"); var names: Array=discovery.result.tools.map(func(tool): return tool.name)
	check(names.size()==109 and not names.has("paint_tile"),"109 current tools, retired 2D stays unregistered")
	var templates:=await call_tool("list_building_templates")
	check(templates.urban_presets.size()==2 and templates.parameters_schema.properties.layout.enum.has("urban_village"),"discover urban family presets and schema")
	check(not templates.parameters_schema.properties.has("rental_units"),"contract contains no subdivision or tenancy rules")
	var base: Dictionary=templates.urban_presets[0].parameters
	var fixtures: Array=[{"parameters":base,"position":[0,0,0],"yaw":0.0},
		{"parameters":base.merged({"template":"shop","floors":6,"width":11,"depth":15,"bedrooms":3,"balcony":"corner","facade_color":"cream"},true),"position":[27,0,0],"yaw":37.0},
		{"parameters":base.merged({"width":9.5,"depth":11,"floor_height":4,"floors":2,"bedrooms":1,"balcony":"none","roof_canopy":false,"roof_tank":false},true),"position":[55,0,0],"yaw":-23.0}]
	var placements: Array=[]
	for fixture in fixtures:
		fixture.plan=Blueprint.generate(fixture.parameters); placements.append({"parameters":fixture.parameters,"position":fixture.position,"yaw":fixture.yaw})
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	var preview:=await call_tool("preview_buildings",{"placements":placements})
	check(preview.buildings.size()==3 and preview.buildings[0].terraces.size()==3 and preview.buildings[0].service_zones.size()==6 and doc.recovery_snapshot()==before,"preview exposes terraces and services without mutations")
	await call_tool("generate_buildings",{"parameters":{"layout":"urban_village","rental_units":4},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":base.merged({"width":7},true),"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":base.merged({"width":25,"depth":30,"floor_height":4,"floors":6,"bedrooms":3,"balcony":"corner"},true),"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"placements":[placements[0],placements[0]]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"illegal schema, layout and collisions fail atomically")
	var made:=await call_tool("generate_buildings",{"placements":placements})
	if not made.ok: print(made); quit(1); return
	check(doc._undo.size()==history+1,"all family buildings are one undo transaction")
	await call_tool("undo"); check(editor._buildings.instances().is_empty(),"undo entire generated batch")
	await call_tool("redo"); check(editor._buildings.instances().size()==3,"redo restores building IDs")
	var id: String=made.building_ids[0]; var floor_id: String=editor._buildings.instances()[id].parts["f0/floor"]
	await call_tool("update_building",{"id":id,"parameters":{"facade_color":"rose","balcony":"corner"}})
	check(editor._buildings.instances()[id].parts["f0/floor"]==floor_id,"appearance changes preserve structural identity")
	await call_tool("undo")
	await call_tool("set_object_properties",{"ids":[floor_id],"locked":true}); before=doc.recovery_snapshot()
	await call_tool("update_building",{"id":id,"parameters":{"floors":4}},false)
	check(doc.recovery_snapshot()==before,"locked member protects complete urban building"); await call_tool("undo")
	var street:={"parameters":{"layout":"urban_village","floors":1,"bedrooms":1},"points":[[-10,0,38],[48,0,38]],"max_buildings":2}
	var street_preview:=await call_tool("preview_street_buildings",street)
	check(street_preview.buildings.size()==2 and street_preview.buildings[0].parameters.roof=="flat","street uses urban defaults and footprint including balconies")
	await call_tool("generate_street_buildings",street); await call_tool("undo")
	# Old version 2 recipes did not store the newly introduced family fields.
	var old:=await call_tool("generate_buildings",{"parameters":Blueprint.medieval_presets()[0].parameters,"placements":[{"position":[85,0,0]}]})
	var old_id: String=old.building_ids[0]
	doc.map_meta.building_instances[old_id].version=2
	for key in Blueprint.defaults():
		if not Blueprint.medieval_defaults().has(key): doc.map_meta.building_instances[old_id].parameters.erase(key)
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(doc.map_meta.building_instances[old_id].version==2 and editor._buildings.conflicts(old_id).is_empty(),"version 2 opens unchanged without added parameters")
	check(editor._buildings.conflicts(id).is_empty(),"urban version 3 and cylinder geometry reopen without false conflicts")
	# Switching from the old layout must not retain its hidden gable or jetty fields.
	editor._building_panel.refresh_list(old_id)
	editor._building_panel.set_values({"layout":"urban_village","template":"inn","width":10,"depth":12},[85,0,0],0)
	var ui_parameters: Dictionary=editor._building_panel.parameters()
	check(ui_parameters.template=="house" and ui_parameters.roof=="flat" and not editor._building_panel.form.fields.has("roof"),"UI switches to valid family fields and resets hidden style defaults")
	await call_tool("update_building",{"id":old_id,"parameters":ui_parameters})
	check(editor._buildings.instances()[old_id].parameters.layout=="urban_village","UI parameters and MCP share cross-layout replacement")
	await call_tool("undo")
	await call_tool("save_editor_draft"); var drafts:=await call_tool("list_editor_drafts")
	await call_tool("delete_building",{"id":id}); await call_tool("restore_editor_draft",{"draft_id":drafts.drafts[0].draft_id,"discard_changes":true}); doc=editor._doc
	check(editor._buildings.instances().has(id),"draft restores urban blueprint, six-storey metadata and equipment")
	editor._dock_tabs.current_tab=8; editor._building_panel.refresh_list(id)
	check(editor._building_panel.form.fields.has("bedrooms") and not editor._building_panel.form.fields.has("rooms_per_floor") and not editor._building_panel.form.fields.has("compound"),"UI exposes family fields and hides unrelated layouts")
	before=doc.recovery_snapshot(); editor._building_panel.preview(); await physics()
	check(is_instance_valid(editor._building_panel.ghost) and doc.recovery_snapshot()==before,"UI preview shares read-only business plan")
	await capture("preview"); editor._building_panel.clear_preview(); editor._building_panel.focus(); await physics(); await capture("exterior")
	await call_tool("set_floor_view",{"isolation":true,"base_height":base.floor_height,"floor_height":base.floor_height}); editor._top_view(); await physics(); await capture("family_floor")
	await call_tool("set_floor_view",{"isolation":true,"base_height":6*base.floor_height,"floor_height":base.floor_height})
	var high_id: String=made.building_ids[1]; var roof_id: String=editor._buildings.instances()[high_id].parts["roof/floor/left"]
	check(editor._record_editable(doc._find(roof_id)) and not editor._record_editable(doc._find(floor_id)),"sixth roof level isolates correctly")
	await call_tool("set_floor_view",{"isolation":false}); editor._building_panel.refresh_list(high_id); editor._building_panel.focus(); await physics(); await capture("six_storey")
	await call_tool("save_world")
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array=await loader.finished; check(loaded[0]!=null,"runtime loads saved urban map")
	if loaded[0]!=null: await runtime_checks(loaded[0],fixtures)
	if failed==0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_urban: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func capture(name_: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_urban/"+name_+".png"))

func runtime_checks(scene: Node3D, fixtures: Array) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
	var space:=host.get_world_3d().direct_space_state
	for fixture in fixtures:
		var plan: Dictionary=fixture.plan; var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
		Stream.sync(scene,host,origin); await physics(); var openings_ok:=true
		for o in plan.openings:
			var y: float=o.floor_y+o.bottom+o.height/2
			var center:=origin+basis*(Vector3(o.u,y,o.fixed) if o.axis=="x" else Vector3(o.fixed,y,o.u))
			var normal:=basis*(Vector3(0,0,.4) if o.axis=="x" else Vector3(.4,0,0))
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center-normal,center+normal))
			if (o.type=="door" and not hit.is_empty()) or (o.type=="window" and (hit.is_empty() or hit.position.distance_to(center)>.04)):
				openings_ok=false; print("opening mismatch ",fixture.yaw," ",o.wall," ",o.id," ",hit)
		check(openings_ok,"every actual door/window aperture agrees with shared plan")
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); nav.agent_height=2.1; host.add_child(nav); nav.build(scene.get_meta("stream_library"))
	var deadline:=Time.get_ticks_msec()+40000
	while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(nav.fully_ready,"saved map navigation completes")
	if nav.fully_ready:
		for fixture in fixtures:
			var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
			for destination in fixture.plan.rooms+fixture.plan.terraces:
				var route: Dictionary=nav.find_path(origin+basis*Blueprint.vec(fixture.plan.entrance),origin+basis*Blueprint.vec(destination.center))
				check(route.ok,"saved entrance reaches %s (%s degrees)"%[destination.id,fixture.yaw])
				if not route.ok:print("SAVED_ROUTE_FAILURE ",route)
	var body:=WalkBody.new(); body.floor_snap_length=.2; var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=1.8; shape.shape=capsule; body.add_child(shape); host.add_child(body)
	var walk_nav:=WalkNavigation.new(); host.add_child(walk_nav)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	for fixture in [fixtures[0],fixtures[2]]:
		var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
		Stream.sync(scene,host,origin); await physics()
		for f in fixture.parameters.floors:
			var stairs: Array=fixture.plan.stairs.filter(func(s): return s.floor==f)
			body.position=origin+basis*Blueprint.vec(stairs[0].bottom)+Vector3(0,.905,0); body.velocity=Vector3.ZERO; authority.mount(body,walk_nav,"urban-stair")
			var sequence:=0
			for ascending in [true,false]:
				var targets: Array=[stairs[0].top,stairs[1].bottom,stairs[1].top] if ascending else [stairs[1].bottom,stairs[0].top,stairs[0].bottom]
				for target in targets:
					var world_target:=origin+basis*Blueprint.vec(target)
					for tick in 200:
						var delta:=world_target-body.position; delta.y=0
						if delta.length()<.13: break
						await physics_frame; sequence+=1; authority.move_intent(sequence,delta.normalized(),2.5)
				var goal:=origin+basis*Blueprint.vec(targets[-1])
				var reached:=absf(body.position.y-goal.y-.9)<.15 and Vector2(body.position.x-goal.x,body.position.z-goal.z).length()<.2
				check(reached,"capsule %s both flights and turns on platform %d / %s degrees"%["climbs" if ascending else "descends",f,fixture.yaw])
				if not reached: print("stuck at ",body.position," target ",goal)
			authority.release()
	host.free()
