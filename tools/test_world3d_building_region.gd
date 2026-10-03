extends "res://tools/test_world3d_buildings.gd"
const Region=preload("res://scripts/world_editor/building_region.gd")
const Footprint=preload("res://scripts/world_editor/building_footprint.gd")

func mouse(point: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event); await physics()

func run() -> void:
	create_timer(420).timeout.connect(func(): push_error("region test timeout"); quit(2))
	root.size=Vector2i(1440,960); root.content_scale_size=root.size
	var directory:=Paths.cache_directory("region_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground: String=doc.add_box("ground",Vector3(0,-.1,0),Vector3(100,.2,80))
	var obstacle: String=doc.add_box("block",Vector3(0,5,0),Vector3(12,10,24),Vector3(0,17,0)); doc._find(obstacle).editor_hidden=true; doc._find(obstacle).editor_locked=true
	# Imported-model bounds must also participate in avoidance.
	var source:=Node3D.new(); var mesh:=MeshInstance3D.new(); var cube:=BoxMesh.new(); cube.size=Vector3(6,8,6); mesh.mesh=cube; mesh.position=Vector3(0,4,0); source.add_child(mesh)
	check(Io.save_scene(source,directory.path_join("prop.glb"))==OK,"create model obstacle"); source.free()
	var library:=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("assets")); var imported:=library.import_file(directory.path_join("prop.glb"))
	check(imported.ok,"import obstacle fixture"); var asset: String=doc.add_asset(imported.entry,Vector3(20,0,0)); doc._find(asset).rotation=[0,43,0]; doc._find(asset).size=[1.5,1,.7]
	check(doc.save(path)==OK,"create isolated region map")
	Net.session().world3d_editor_doc=doc; Net.session().world3d_editor_path=path
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await physics(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start loopback HTTP MCP")
	var discovery:=await rpc("tools/list"); var names: Array=discovery.result.tools.map(func(tool): return tool.name)
	check(names.size()==118 and names.has("preview_region_buildings") and names.has("generate_region_buildings") and not names.has("paint_tile"),"118 tools discover both region operations and keep 2D retired")
	var args:={"from":[-35,0,-28],"to":[35,0,28],"style":"urban_village","mode":"block","seed":42,"max_buildings":3}
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	var first:=await call_tool("preview_region_buildings",args); var second:=await call_tool("preview_region_buildings",args)
	check(first==second and doc.recovery_snapshot()==before and doc._undo.size()==history,"HTTP preview is deterministic and read-only")
	check(first.plan_token==Region.plan(args,doc.records).plan_token,"UI and JSON HTTP use the same deterministic plan token")
	var occupied: Array=[]; var safe:=true
	var obstacles:=[Footprint.record_shape(doc._find(obstacle)),Footprint.record_shape(doc._find(asset))]
	for building in first.buildings:
		var plan:=Blueprint.generate(building.parameters)
		var shapes:=Footprint.components(plan.records,Blueprint.vec(building.position),Basis(Vector3.UP,deg_to_rad(building.yaw)))
		safe=safe and not Footprint.batches_overlap(shapes,obstacles) and not Footprint.batches_overlap(shapes,occupied); occupied.append_array(shapes)
	check(safe,"entire houses, balconies and canopies avoid hidden, locked and rotated model obstacles")
	for bad in [{"from":[-1,0,-1],"to":[1,0,1]},{"from":[0,0,0],"to":[20,1,20]},args.merged({"seed":-1},true),args.merged({"rental_units":2},true)]: await call_tool("generate_region_buildings",bad,false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"illegal regions fail without edits or history")
	var made:=await call_tool("generate_region_buildings",args.merged({"plan_token":first.plan_token},true))
	check(made.building_ids.size()==first.buildings.size() and doc._undo.size()==history+1,"accept exact preview in one transaction")
	await call_tool("undo"); check(equivalent(doc.records,before.records) and equivalent(doc.map_meta,before.map_meta),"undo keeps every pre-existing object and flag")
	await call_tool("redo"); check(editor._buildings.instances().has(made.building_ids[0]),"redo preserves generated identity")
	await call_tool("save_world"); await call_tool("open_world",{"path":path,"discard_changes":true}); doc=editor._doc
	check(editor._buildings.instances().size()==made.building_ids.size() and doc._find(obstacle).editor_hidden and doc._find(obstacle).editor_locked,"save/reopen preserves building recipes and protected obstacles")
	# A new object after preview must reject the frozen plan, never replace it silently.
	var fresh:={"from":[-46,0,30],"to":[-22,0,49],"seed":2}
	var frozen:=await call_tool("preview_region_buildings",fresh)
	var at:=Blueprint.vec(frozen.buildings[0].position); var added: String=doc.add_box("block",at+Vector3(0,4,0),Vector3(8,8,8)); editor._rebuild()
	before=doc.recovery_snapshot(); history=doc._undo.size()
	await call_tool("generate_region_buildings",fresh.merged({"plan_token":frozen.plan_token},true),false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history and not doc._find(added).is_empty(),"changed obstacles reject stale preview without overwriting anything")
	# GUI draw, cancellation, reroll and handoff to detailed parameters.
	editor._dock_tabs.current_tab=8; var quick: VBoxContainer=editor._building_panel.region
	editor._camera.position=Vector3(-23,55,-9); editor._camera.look_at(Vector3(-23,0,-9),Vector3.FORWARD); editor._orbit_center=Vector3(-23,0,-9); await physics()
	var from: Vector2=editor._canvas.global_position+editor._camera.unproject_position(Vector3(-43,0,-25))
	var to: Vector2=editor._canvas.global_position+editor._camera.unproject_position(Vector3(-23,0,-7))
	before=doc.recovery_snapshot(); quick.begin_draw(); await mouse(from,true)
	var state:=await call_tool("editor_state"); check(state.building_region_drawing,"MCP exposes active region drawing")
	await call_tool("save_world",{},false)
	var motion:=InputEventMouseMotion.new(); motion.position=to; motion.button_mask=MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(motion); await physics(); await mouse(to,false)
	check(not quick.drawing and quick.corners.size()==2 and doc.recovery_snapshot()==before,"real viewport drag ends without writing document")
	# Clear the generated batch so the same drawn region has no prior houses.
	for id in made.building_ids: await call_tool("delete_building",{"id":id})
	quick.preview(); check(not quick.cached.is_empty() and is_instance_valid(editor._building_panel.ghost),"release/preview produces usable ghost geometry")
	var old_token: String=quick.cached.plan_token; quick.reroll()
	check(quick.cached.plan_token!=old_token and not quick.apply.disabled,"reroll replaces only the proposal")
	await capture("quick_preview")
	quick.refine_one(); check(editor._building_panel.details.visible and editor._building_panel.form.values().layout=="urban_village","single proposal hands off to retained detailed controls")
	editor._building_panel.details_toggle.button_pressed=false
	quick.preview(); before=doc.recovery_snapshot(); history=doc._undo.size(); quick.accept()
	check(editor._buildings.instances().size()==1 and doc._undo.size()==history+1,"quick UI applies the exact proposal in one transaction")
	await call_tool("undo"); check(equivalent(doc.records,before.records) and equivalent(doc.map_meta,before.map_meta),"quick UI accept undoes without affecting existing content")
	quick.begin_draw(); await mouse(from,true); var escape:=InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; Input.parse_input_event(escape); await physics()
	check(not quick.drawing and not quick.dragging,"Escape cancels region drag")
	quick.begin_draw(); editor._dock_tabs.current_tab=0; check(not quick.drawing,"switching tab cancels picking")
	editor._dock_tabs.current_tab=8; quick.begin_draw(); editor._notification(NOTIFICATION_APPLICATION_FOCUS_OUT); check(not quick.drawing,"focus loss cancels picking")
	quick.begin_draw(); await mouse(from,true); await mouse(Vector2(10,10),false); check(not quick.drawing and not quick.dragging,"release over dock cancels without drawing behind UI")
	await call_tool("select_objects",{"ids":[ground]}); quick.use_selection()
	check(equivalent(quick.corners,[[-50,0,-40],[50,0,40]]),"selected flat ground supplies rectangular lot and height")
	if not equivalent(quick.corners,[[-50,0,-40],[50,0,40]]): print("selected corners=",quick.corners," feedback=",quick.feedback.text)
	quick.clear(); check(quick.cached.is_empty() and not is_instance_valid(quick.guide) and not is_instance_valid(editor._building_panel.ghost),"clear removes proposal and drawing overlay")
	await call_tool("save_world")
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	if failed==0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_building_region: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)

func capture(name_: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_urban/"+name_+".png"))
