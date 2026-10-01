extends "res://tools/test_world3d_mcp.gd"
const Blueprint = preload("res://scripts/world3d/building_blueprint.gd")
const Net = preload("res://scripts/net/net.gd")
const Stream = preload("res://scripts/world3d/world_stream.gd")
class WalkBody extends CharacterBody3D:
	var surface_id := "ground"
	func _sense_surface(): pass
class WalkNavigation extends Node:
	var ready_for_queries := true
	func near_surface(_point, _flat, _vertical): return true

func physics() -> void:
	await settle(); await physics_frame; await physics_frame

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Building test timeout"); quit(2))
	root.size = Vector2i(1280,800); root.content_scale_size = root.size
	var directory := Paths.cache_directory("buildings_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path := directory.path_join("map.gltf")
	var doc := Doc.new(); doc.add_box("ground",Vector3(30,-.1,0),Vector3(120,.2,80))
	check(doc.save(path)==OK,"create isolated building fixture")
	Net.session().world3d_editor_path = path; Net.session().world3d_editor_doc = doc
	editor = preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts"); editor._material_directory = directory.path_join("materials"); root.add_child(editor); await physics(); editor._safety.enabled = false
	var probe := TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real HTTP MCP")
	var discovery := await rpc("tools/list"); check(discovery.result.tools.size()==67,"discover 67 tools including eleven building operations")
	var templates := await call_tool("list_building_templates"); check(templates.templates.size()==3,"three building uses expose shared parameter schema")
	for type in Blueprint.LABELS:
		for floors in [1,2,3]:
			var plan := Blueprint.generate({"template":type,"floors":floors,"rooms_per_floor":3})
			check(plan.ok and plan.rooms.size()==floors*3 and plan.stairs.size()==floors-1,"shared plan for %s / %d storeys"%[type,floors])
	var args := {"parameters":{"template":"shop","floors":3},"placements":[{"position":[0,0,0]}]}
	var before := doc.recovery_snapshot(); var history: int = doc._undo.size()
	var preview := await call_tool("preview_buildings",args)
	check(preview.buildings[0].rooms.size()==6 and preview.buildings[0].stairs.size()==2 and doc.recovery_snapshot()==before and doc._undo.size()==history,"preview provides interior/exterior plan without changes")
	await call_tool("generate_buildings",{"parameters":{"floors":0},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"placements":[{"position":[0,0,0]},{"position":[1,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid and overlapping batch failure is atomic")
	var made := await call_tool("generate_buildings",args)
	if not made.get("ok",false): editor.free(); quit(1); return
	var id: String = made.building_ids[0]
	var instance: Dictionary = editor._buildings.instances()[id]
	var initial_ids: Dictionary = instance.parts.duplicate()
	check(instance.parts.size()>256 and doc._undo.size()==history+1,"whole-building transaction supports more than 256 components")
	await call_tool("undo"); check(doc.recovery_snapshot().records==before.records and editor._buildings.instances().is_empty(),"undo removes both recipe and all generated objects")
	await call_tool("redo"); check(editor._buildings.instances().has(id),"redo restores building identity")
	var listed := await call_tool("list_buildings"); check(listed.buildings.size()==1 and listed.buildings[0].conflicts.is_empty(),"new building is discoverable without conflicts")
	var first_record: String = instance.parts["f0/floor"]
	await call_tool("set_object_properties",{"ids":[first_record],"locked":true})
	before = doc.recovery_snapshot(); history = doc._undo.size()
	await call_tool("update_building",{"id":id,"parameters":{"width":14}},false)
	await call_tool("delete_building",{"id":id},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"locked building failure preserves all content")
	await call_tool("set_object_properties",{"ids":[first_record],"locked":false})
	await call_tool("set_floor_view",{"isolation":true,"base_height":3,"floor_height":3})
	check(editor._authoring.includes(doc._find(instance.parts["f1/floor/left"])) and not editor._authoring.includes(doc._find(instance.parts["roof/ceiling"])),"semantic floor levels show slabs and exclude ceiling")
	await call_tool("update_building",{"id":id,"parameters":{"width":14}},false)
	await call_tool("set_floor_view",{"isolation":false})
	await call_tool("configure_transform",{"component_edit":true})
	await call_tool("set_object_transform",{"id":first_record,"position":[.1,-.11,0]})
	before = doc.recovery_snapshot()
	await call_tool("update_building",{"id":id,"parameters":{"width":14}},false)
	check(doc.recovery_snapshot()==before,"regeneration never overwrites a hand-edited structural part")
	await call_tool("undo")
	await call_tool("configure_transform",{"component_edit":false})
	var image_ := Image.create(4,4,false,Image.FORMAT_RGBA8); image_.fill(Color(.7,.5,.3)); image_.save_png(directory.path_join("finish.png"))
	var finish := await call_tool("import_surface_material",{"path":directory.path_join("finish.png"),"name":"建筑测试材质"})
	var faces := await call_tool("list_object_surfaces",{"id":first_record})
	await call_tool("paint_surface",{"id":first_record,"target":faces.faces[0].target,"material_id":finish.material_id})
	before = doc.recovery_snapshot(); history = doc._undo.size()
	await call_tool("update_building",{"id":id,"parameters":{"width":14}},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"dimension changes cannot silently invalidate hand-painted faces")
	await call_tool("update_building",{"id":id,"parameters":{"seed":8}})
	check(doc._find(first_record).has("surface_paint"),"compatible regeneration preserves the painted face")
	await call_tool("undo"); await call_tool("undo")
	await call_tool("update_building",{"id":id,"parameters":{"width":14,"seed":8}})
	check(editor._buildings.instances()[id].parts["f0/floor"]==first_record,"parameter updates preserve stable part IDs")
	await call_tool("undo"); check(editor._buildings.instances()[id].parts==initial_ids,"undo restores previous recipe and IDs")
	var replacement := await call_tool("preview_buildings",{"replace_id":id,"parameters":{"width":14},"placements":[{"position":[0,0,0]}]})
	check(replacement.buildings[0].parameters.floors==3 and replacement.buildings[0].parameters.width==14,"MCP previews incremental updates using the existing recipe")
	await call_tool("save_world")
	await call_tool("save_editor_draft")
	var drafts := await call_tool("list_editor_drafts")
	await call_tool("update_building",{"id":id,"parameters":{"seed":4}})
	await call_tool("restore_editor_draft",{"draft_id":drafts.drafts[0].draft_id,"discard_changes":true})
	check(editor._buildings.instances()[id].parameters.seed==1,"draft recovery restores building recipe and generated components")
	await call_tool("open_world",{"path":path,"discard_changes":true}); doc = editor._doc
	check(editor._buildings.conflicts(id).is_empty(),"save/reopen retains recipe and regeneration baselines")
	await call_tool("update_building",{"id":id,"parameters":{"seed":2}})
	await call_tool("undo")
	var batch := await call_tool("generate_buildings",{"parameters":{"floors":1,"roof":"flat","style":"plaster"},"placements":[{"position":[24,0,0],"yaw":90},{"position":[48,0,0],"seed_offset":2}]})
	check(batch.building_ids.size()==2,"batch places independently identified buildings with orientation and seeds")
	var detached: String = batch.building_ids[0]
	var detached_parts: Array = editor._buildings.instances()[detached].parts.values()
	await call_tool("detach_building",{"id":detached})
	check(not editor._buildings.instances().has(detached) and not doc._find(detached_parts[0]).has("building"),"detach preserves editable geometry and removes ownership")
	await call_tool("undo")
	await call_tool("delete_building",{"id":detached})
	check(doc._find(detached_parts[0]).is_empty(),"delete removes only owned components")
	await call_tool("undo"); await call_tool("undo") # Remove the batch; original 3-storey shop remains.
	await call_tool("save_world")
	var old_hash := FileAccess.get_sha256(path)
	doc.map_meta.building_instances[id].version = 999
	await call_tool("save_world",{},false)
	check(FileAccess.get_sha256(path)==old_hash,"invalid recipe cannot overwrite saved map")
	doc.map_meta.building_instances[id].version = Blueprint.VERSION
	# UI uses the same planning and commit paths and supports a visible ghost preview.
	editor._dock_tabs.current_tab = 8
	editor._building_panel.refresh_list(id); editor._building_panel.preview(); await physics()
	check(is_instance_valid(editor._building_panel.ghost) and not editor._view.get_node(first_record).visible,"UI update preview replaces the source visually without editing it")
	editor._building_panel.clear_preview(); check(editor._view.get_node(first_record).visible,"clearing update preview restores source visibility")
	editor._building_panel.chooser.select(0)
	editor._building_panel.set_values(Blueprint.defaults(),[24,0,0],0)
	editor._building_panel.preview(); await physics()
	check(is_instance_valid(editor._building_panel.ghost) and editor._buildings.instances().size()==1,"UI preview renders without creating document objects")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_buildings/preview.png"))
	editor._building_panel.clear_preview(); editor._building_panel.refresh_list(id); editor._building_panel.focus()
	if DisplayServer.get_name()!="headless":
		await physics(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_buildings/exterior.png"))
		await call_tool("set_floor_view",{"isolation":true,"base_height":3,"floor_height":3})
		editor._top_view(); await physics(); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_buildings/interior.png"))
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	# Verify the actual saved runtime mesh, collisions, openings and multi-storey navigation.
	var loader := preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array = await loader.finished
	check(loaded[0]!=null,"runtime loads saved generated architecture")
	if loaded[0]!=null:
		var host := Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3.ZERO); await physics()
		var plan := Blueprint.generate(args.parameters)
		var space := host.get_world_3d().direct_space_state
		for opening in plan.openings:
			var y: float = opening.floor_y+opening.bottom+opening.height/2
			var center := Vector3(opening.u,y,opening.fixed) if opening.axis=="x" else Vector3(opening.fixed,y,opening.u)
			var normal := Vector3(0,0,.4) if opening.axis=="x" else Vector3(.4,0,0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center-normal,center+normal))
			check(hit.is_empty() if opening.type=="door" else (not hit.is_empty() and absf(hit.position.distance_to(center))<.04),"shared %s opening %s has matching runtime wall geometry"%[opening.type,opening.id])
		var nav := preload("res://scripts/world3d/world_navigation.gd").new(); host.add_child(nav); nav.build(loaded[0].get_meta("stream_library"))
		var deadline := Time.get_ticks_msec()+25000
		while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
		check(nav.fully_ready,"navigation bake completes")
		if nav.fully_ready:
			for room in plan.rooms:
				var route: Dictionary = nav.find_path(Blueprint.vec(plan.entrance),Blueprint.vec(room.center))
				check(route.ok,"entrance reaches room "+room.id+" on the actual multi-level navmesh")
		var body := WalkBody.new(); body.floor_snap_length=.2; var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius=.3; capsule.height=1.8; shape.shape=capsule; body.add_child(shape); host.add_child(body)
		var walk_nav := WalkNavigation.new(); host.add_child(walk_nav)
		var authority := preload("res://scripts/world3d/world_authority.gd").new(); authority.mount(body,walk_nav,"building-test")
		for stair in plan.stairs:
			body.position=Blueprint.vec(stair.bottom)+Vector3(0,.905,0); body.velocity=Vector3.ZERO
			authority.mount(body,walk_nav,"building-test")
			for tick in 230:
				await physics_frame; authority.move_intent(tick,Vector3.BACK,2.5)
				if body.position.z>float(stair.top[2])-.1: break
			check(body.position.y>float(stair.top[1])+.8 and body.position.z>float(stair.top[2])-.2,"real capsule climbs flight %d without hitting its floor slab"%stair.floor)
			if body.position.y<float(stair.top[1])+.8: print("stair position=",body.position," goal=",stair.top)
		authority.release(); host.free()
	if failed==0: Io._remove_tree(directory)
	else: print("fixture="+directory)
	print("test_world3d_buildings: %s"%("PASS" if failed==0 else "FAIL")); quit(0 if failed==0 else 1)
