extends "res://tools/test_world3d_buildings.gd"
const Street = preload("res://scripts/world_editor/building_street.gd")

func run() -> void:
	create_timer(540).timeout.connect(func(): push_error("Medieval building test timeout"); quit(2))
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("medieval_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(65,-.1,30),Vector3(240,.2,200))
	check(doc.save(path)==OK,"create isolated medieval fixture")
	Net.session().world3d_editor_path=path; Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await physics(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real HTTP for medieval editing")
	var discovery:=await rpc("tools/list"); check(discovery.result.tools.size()==118,"discover 118 current 3D tools")
	var templates:=await call_tool("list_building_templates"); check(templates.presets.size()==7,"discover medieval presets and parameters")
	check(templates.parameters_schema.properties.has("timber_width") and templates.parameters_schema.properties.has("chimney"),"HTTP discovers structural timber and roof stack controls")
	var fixtures: Array=[]; var placements: Array=[]
	for i in 4:
		var p: Dictionary=templates.presets[i].parameters
		fixtures.append({"parameters":p,"position":[i*26.0,0,0],"yaw":0.0})
	fixtures.append({"parameters":Blueprint.medieval_presets()[1].parameters.merged({"compound":"left_wing","roof_pitch":40.0},true),"position":[104,0,0],"yaw":0.0})
	fixtures.append({"parameters":Blueprint.medieval_presets()[0].parameters.merged({"width":5.5,"floors":3,"roof_axis":"width","jetty":.65},true),"position":[130,0,0],"yaw":37.0})
	for fixture in fixtures:
		var plan:=Blueprint.generate(fixture.parameters)
		check(plan.ok,"generate layout "+str(fixture.parameters.layout)+" / "+str(fixture.parameters.compound))
		if not plan.ok: print(plan); quit(1); return
		fixture.plan=plan; placements.append({"parameters":fixture.parameters,"position":fixture.position,"yaw":fixture.yaw})
		var unique:={}
		for record in plan.records:
			if unique.has(record.building.part): check(false,"duplicate part "+record.building.part)
			unique[record.building.part]=true
		check(plan.records.size()<2000,"recipe fits persistent component limits")
		for opening_ in plan.openings:
			var jamb_key: String=opening_.wall+"/"+opening_.id+"/jamb1"
			var jambs: Array=plan.records.filter(func(r):return r.building.part==jamb_key)
			if jambs.is_empty():continue
			var tangent_axis: int=0 if opening_.axis=="x" else 2
			var jamb: Dictionary=jambs[0]
			# Roof-axis rotation can reverse jamb1 and swap its local X/Z axes.
			var frame:=Transform3D(Basis.from_euler(Blueprint.vec(jamb.rotation)*PI/180),Blueprint.vec(jamb.position))
			var bounds: AABB=frame*AABB(-Blueprint.vec(jamb.size)/2,Blueprint.vec(jamb.size))
			var inner: float=absf(bounds.get_center()[tangent_axis]-opening_.u)-bounds.size[tangent_axis]/2
			check(is_equal_approx(inner,opening_.width/2-.05),"jamb overlaps reveal without a coplanar inner face")
			var heads: Array=plan.records.filter(func(r):return r.building.part==opening_.wall+"/"+opening_.id+"/head")
			check(not heads.is_empty() and is_equal_approx(heads[0].position[1]-heads[0].size[1]/2,opening_.floor_y+opening_.bottom+opening_.height-.05),"lintel overlaps the upper reveal without coplanar flicker")
		for joint in plan.frame_joints:
			for endpoint in 2:
				var support: Dictionary=plan.records.filter(func(r):return r.building.part==joint.supports[endpoint])[0]
				var size:=Blueprint.vec(support.size)
				var local:=Blueprint.vec(joint.start if endpoint==0 else joint.end)-Blueprint.vec(support.position)
				check(AABB(-size/2,size).grow(.001).has_point(local),"brace endpoint is seated inside its supporting post or beam")
		if fixture.parameters.style=="plaster":
			check(plan.frame_joints.is_empty() and plan.records.all(func(r):return r.building.role!="brace" and r.building.role!="post"),"masonry facade never inherits a timber grid")
	check(not Blueprint.generate({"layout":"townhouse","width":5.5,"depth":10,"floor_height":4}).ok,"impossible stair and room packing fails")
	check(not Blueprint.generate({"layout":"hall","jetty":.3}).ok,"unsupported jetty over a void fails")
	check(not Blueprint.generate({"layout":"townhouse","compound":"courtyard","width":8}).ok,"narrow courtyard cannot squeeze away circulation")
	var party:=Blueprint.generate({"layout":"townhouse","width":6.5,"left_wall":"party","right_wall":"party"})
	check(party.ok and party.openings.all(func(o): return o.axis=="x"),"party facades have no side windows")
	var single:=Blueprint.generate({"layout":"townhouse","rooms_per_floor":1,"compound":"rear_workshop"})
	var room_ids: Array=single.rooms.map(func(room_): return room_.id)
	check(single.ok and single.connections.all(func(link): return room_ids.has(link.from) and room_ids.has(link.to)),"annex connections reference existing rooms even with one-room floors")
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	var preview:=await call_tool("preview_buildings",{"placements":placements})
	check(preview.buildings.size()==6 and doc.recovery_snapshot()==before,"all medieval layouts preview without side effects")
	await call_tool("generate_buildings",{"parameters":{"layout":"townhouse","roof_pitch":80},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":{"layout":"townhouse","timber_width":.01},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":{"layout":"townhouse","chimney":"yes"},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"placements":[placements[0],placements[0]]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid medieval batches preserve document and undo history")
	var made:=await call_tool("generate_buildings",{"placements":placements})
	if not made.get("ok",false): print(made); quit(1); return
	await call_tool("undo"); check(editor._buildings.instances().is_empty(),"undo removes complete medieval compounds")
	await call_tool("redo"); check(editor._buildings.instances().size()==6,"redo retains all medieval building identities")
	var id: String=made.building_ids[0]; var first: String=editor._buildings.instances()[id].parts["f0/floor"]
	var initial_parts: Dictionary=editor._buildings.instances()[id].parts.duplicate()
	await call_tool("update_building",{"id":id,"parameters":{"roof_axis":"width","jetty":.6,"chimney":false,"timber_width":.28}})
	check(editor._buildings.instances()[id].parts["f0/floor"]==first,"new roof and jetty preserve stable structural IDs")
	check(editor._buildings.instances()[id].parts.keys().all(func(k):return not k.contains("/chimney/")),"HTTP regeneration removes the complete roof chimney")
	await call_tool("undo"); check(editor._buildings.instances()[id].parts==initial_parts,"undo restores dimensions and semantic mapping")
	await call_tool("set_object_properties",{"ids":[first],"hidden":true})
	before=doc.recovery_snapshot()
	await call_tool("update_building",{"id":id,"parameters":{"roof_pitch":40}},false)
	check(doc.recovery_snapshot()==before,"hidden medieval member blocks whole-building regeneration")
	await call_tool("undo")
	var street_args:={"points":[[-20,0,60],[10,0,60],[45,0,80]],"max_buildings":8,"parameters":Blueprint.medieval_presets()[0].parameters}
	var street_a:=await call_tool("preview_street_buildings",street_args)
	var street_b:=await call_tool("preview_street_buildings",street_args)
	check(street_a==street_b and street_a.buildings.size()>2,"street preview is deterministic with usable frontage")
	var widths:={}; var sides:={}; var angles:={}
	for house in street_a.buildings: widths[house.parameters.width]=true; sides[signf(house.position[2]-60)]=true; angles[house.yaw]=true
	check(widths.size()>1 and sides.size()==2 and angles.size()>2,"street layout varies widths on both sides and follows the bend")
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("generate_street_buildings",street_args.merged({"points":[[0,0,0],[50,1,0]]},true),false)
	await call_tool("generate_street_buildings",street_args.merged({"points":[[0,0,0],[50,0,0],[10,0,0]]},true),false)
	await call_tool("generate_street_buildings",street_args.merged({"points":[[0,0,0],[30,0,30],[0,0,30],[30,0,0]]},true),false)
	await call_tool("generate_street_buildings",street_args.merged({"points":[[-20,0,0],[140,0,0]]},true),false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"slope and existing-building conflict fail atomically")
	var street_made:=await call_tool("generate_street_buildings",street_args)
	check(street_made.building_ids.size()==street_a.buildings.size() and doc._undo.size()==history+1,"HTTP generates entire street in one transaction")
	await call_tool("undo"); check(editor._buildings.instances().size()==6,"street undo leaves existing buildings intact")
	await call_tool("redo")
	# The UI dispatches the same street plan and displays every ghost without writing records.
	editor._dock_tabs.current_tab=8; editor._building_panel.set_values(street_args.parameters,[0,0,0],0)
	editor._building_panel.street.enabled.button_pressed=true
	editor._building_panel.street.drawing=true
	editor._building_panel.frame({"position":[-10,0,40],"size":[20,2,20]}); await physics()
	var picked:=Vector3(0,0,50); var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true
	click.position=editor._canvas.global_position+editor._camera.unproject_position(picked)
	before=doc.recovery_snapshot(); editor._input(click)
	check(editor._building_panel.street.points.size()==1 and Blueprint.vec(editor._building_panel.street.points[0]).distance_to(picked)<.15 and doc.recovery_snapshot()==before,"viewport click adds a centerline point without document edits")
	var escape:=InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; editor._input(escape)
	check(not editor._building_panel.street.drawing,"Escape exits street point picking")
	editor._building_panel.street.points=street_args.points.duplicate(true); editor._building_panel.street.enabled.button_pressed=true
	editor._building_panel.street.refresh()
	await call_tool("undo")
	before=doc.recovery_snapshot(); editor._building_panel.preview(); await physics()
	check(is_instance_valid(editor._building_panel.ghost) and doc.recovery_snapshot()==before,"UI street preview uses shared planner without mutations")
	await capture("street_preview")
	editor._building_panel.clear_preview(); editor._building_panel.street.enabled.button_pressed=false
	await call_tool("redo")
	await call_tool("save_world"); await call_tool("save_editor_draft")
	var drafts:=await call_tool("list_editor_drafts")
	await call_tool("delete_building",{"id":id})
	await call_tool("restore_editor_draft",{"draft_id":drafts.drafts[0].draft_id,"discard_changes":true})
	check(editor._buildings.instances().has(id),"draft restores compound recipes and components")
	await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(editor._buildings.conflicts(id).is_empty(),"saved medieval recipes reopen without false manual-edit conflicts")
	# Version 3 had no facade-width/chimney fields. Reading never regenerates it.
	var old_snapshot: Array=doc.records.duplicate(true)
	doc.map_meta.building_instances[id].version=3
	doc.map_meta.building_instances[id].parameters.erase("timber_width")
	doc.map_meta.building_instances[id].parameters.erase("chimney")
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(equivalent(doc.records,old_snapshot) and editor._buildings.conflicts(id).is_empty(),"version 3 opens without new required fields or geometry changes")
	# A genuinely old recipe omits all added parameters and uses version 1.
	var legacy:=await call_tool("generate_buildings",{"placements":[{"position":[160,0,0]}]})
	var legacy_id: String=legacy.building_ids[0]
	doc.map_meta.building_instances[legacy_id].version=1
	doc.map_meta.building_instances[legacy_id].parameters=Blueprint.legacy_defaults()
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(editor._buildings.conflicts(legacy_id).is_empty(),"version 1 map stays readable with original geometry baseline")
	await call_tool("update_building",{"id":legacy_id,"parameters":{"seed":2}})
	check(doc.map_meta.building_instances[legacy_id].version==Blueprint.VERSION,"editing upgrades only the chosen legacy recipe")
	await call_tool("save_world")
	editor._building_panel.refresh_list(id); editor._building_panel.focus(); await physics(); await capture("townhouse")
	editor._building_panel.refresh_list(made.building_ids[2]); editor._building_panel.focus()
	editor._camera.position=editor._orbit_center+Vector3(1,.9,1).normalized()*32; editor._camera.look_at(editor._orbit_center)
	await physics(); await capture("courtyard")
	await call_tool("set_floor_view",{"isolation":true,"base_height":0,"floor_height":3})
	editor._top_view(); await physics(); await capture("courtyard_interior")
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array=await loader.finished
	check(loaded[0]!=null,"runtime loads saved medieval street and every compound")
	if loaded[0]!=null: await runtime_checks(loaded[0],fixtures)
	if failed==0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_medieval: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func capture(name_: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_medieval/"+name_+".png"))

func runtime_checks(scene: Node3D, fixtures: Array) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3(60,0,0)); await physics()
	var space:=host.get_world_3d().direct_space_state
	for fixture in fixtures:
		var plan: Dictionary=fixture.plan; var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
		Stream.sync(scene,host,origin); await physics()
		for o in plan.openings:
			var y: float=o.floor_y+o.bottom+o.height/2
			var local:=Vector3(o.u,y,o.fixed) if o.axis=="x" else Vector3(o.fixed,y,o.u)
			var center:=origin+basis*local; var normal:=basis*(Vector3(0,0,.4) if o.axis=="x" else Vector3(.4,0,0))
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center-normal,center+normal))
			if (o.type=="door" and not hit.is_empty()) or (o.type=="window" and (hit.is_empty() or hit.position.distance_to(center)>.04)):
				check(false,"opening mismatch %s / %s / %s"%[fixture.parameters.compound,o.wall,o.id])
		check(true,"checked all real door/window apertures for "+fixture.parameters.compound)
		if fixture.parameters.layout=="hall":
			var at:=origin+Blueprint.vec(plan.rooms[0].center)
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3(0,3.3,0),at+Vector3(0,.1,0)))
			check(hit.is_empty(),"hall is physically open through the first-floor void")
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); host.add_child(nav); nav.build(scene.get_meta("stream_library"))
	var started:=Time.get_ticks_msec(); var deadline:=started+40000; var progress:=started+15000
	while not nav.fully_ready and Time.get_ticks_msec()<deadline:
		await process_frame
		if Time.get_ticks_msec()>progress:
			print("navigation progress: phase=%s cursor=%d sources=%d elapsed=%dms"%[nav._phase,nav._cursor,nav.full_source_count,Time.get_ticks_msec()-started]); progress+=15000
	print("navigation completed=%s elapsed=%dms"%[nav.fully_ready,Time.get_ticks_msec()-started])
	check(nav.fully_ready,"medieval navmesh bake completes")
	check(nav.face_extractions<nav.full_source_count/5,"building navigation reuses cube geometry instead of reading each box from GPU")
	if nav.fully_ready:
		for fixture in fixtures:
			var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
			for room_ in fixture.plan.rooms:
				var route: Dictionary=nav.find_path(origin+basis*Blueprint.vec(fixture.plan.entrance),origin+basis*Blueprint.vec(room_.center))
				check(route.ok,"entry reaches %s / %s"%[fixture.parameters.compound,room_.id])
				if not route.ok: print("ROUTE_FAILURE ",fixture.position," ",room_.id," ",route)
	var body:=WalkBody.new(); body.floor_snap_length=.2; var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=1.8; shape.shape=capsule; body.add_child(shape); host.add_child(body)
	var walk_nav:=WalkNavigation.new(); host.add_child(walk_nav)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	for fixture in [fixtures[0],fixtures[5]]:
		var basis:=Basis(Vector3.UP,deg_to_rad(fixture.yaw)); var origin:=Blueprint.vec(fixture.position)
		Stream.sync(scene,host,origin); await physics()
		for stair in fixture.plan.stairs:
			body.position=origin+basis*Blueprint.vec(stair.bottom)+Vector3(0,.905,0); body.velocity=Vector3.ZERO; authority.mount(body,walk_nav,"medieval-test")
			var target:=origin+basis*Blueprint.vec(stair.top)
			for tick in 250:
				await physics_frame; authority.move_intent(tick,basis*Vector3.BACK,2.5)
				if (basis.inverse()*(body.position-target)).z>-.1: break
			check(body.position.y>target.y+.8 and (basis.inverse()*(body.position-target)).z>-.2,"capsule climbs narrow/rotated medieval stair %d"%stair.floor)
		authority.release()
	host.free()
