extends "res://tools/test_world3d_roads.gd"
const W=preload("res://scripts/world3d/waterway_data.gd")
const Channel=preload("res://scripts/world3d/channel_surface.gd")
func run() -> void:
	create_timer(300).timeout.connect(func():quit(2))
	root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("waterways_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground_id:=doc.add_box("grass",Vector3(0,-.25,0),Vector3(140,.5,140)); doc._find(ground_id).color=[.32,.40,.22]
	check(doc.save(map_path)==OK,"temporary waterway map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30010
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"waterway HTTP server starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==114 and definitions.any(func(t):return t.name=="preview_waterway" and t.annotations.readOnlyHint) and not definitions.any(func(t):return t.name=="paint_tile"),"114 current 3D tools expose waterway preview, old 2D remains retired")
	check((await call_tool("list_waterways")).regions.is_empty(),"initial river catalog empty")
	var bridge:={"id":"market_bridge","segment":1,"t":.5,"width":5.0,"approach":3.0,"rail_height":1.1}
	var args:={"id":"town_river","ground_ids":[ground_id],"points":[[-10,-60],[0,-35],[0,35],[12,60]],"bridges":[bridge],"bank_material_id":"pack:default:paving/historic_cobble/material","bridge_material_id":"pack:default:paving/historic_cobble/material"}
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var preview:=await call_tool("preview_waterway",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.bridges.size()==1 and equivalent(preview,await call_tool("preview_waterway",args)),"deterministic river and bridge preview")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"preview is readonly")
	await atomic_reject("generate_waterway",args.merged({"plan_token":"stale"}))
	await atomic_reject("generate_waterway",args.merged({"width":100},true))
	await atomic_reject("generate_waterway",args.merged({"points":[[0,-20],[0,20],[0,-20]]},true))
	await atomic_reject("generate_waterway",args.merged({"ground_ids":[ground_id,ground_id]},true))
	await atomic_reject("generate_waterway",args.merged({"bank_material_id":"missing"},true))
	await atomic_reject("generate_waterway",args.merged({"bridges":[bridge.merged({"t":.01},true)]},true))
	await call_tool("set_object_properties",{"ids":[ground_id],"locked":true}); await atomic_reject("generate_waterway",args); await call_tool("undo")
	var obstruction: String=editor._doc.add_box("block",Vector3(0,1,20),Vector3(2,2,2)); editor._doc._find(obstruction).editor_hidden=true; editor._doc._find(obstruction).editor_locked=true; editor._rebuild()
	await atomic_reject("generate_waterway",args); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstruction); editor._rebuild()
	await call_tool("create_road_path",{"points":[[-40,0,0],[40,0,0]],"width":5}); await atomic_reject("generate_waterway",args); await call_tool("undo")
	preview=await call_tool("preview_waterway",args); before=editor._doc.recovery_snapshot(); history=editor._doc._undo.size()
	var generated:=await call_tool("generate_waterway",args.merged({"plan_token":preview.plan_token}))
	if not generated.get("ok",false): quit(1); return
	check(editor._doc._undo.size()==history+1,"excavation + river + bridge commit once")
	var after: Dictionary=editor._doc.recovery_snapshot(); var region: Dictionary=editor._waterways.regions()[0]
	check(editor._doc._find(ground_id).has("channel_mesh") and region.sources[0].uuid==ground_id,"original ground identity and recovery source retained")
	await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"undo restores original terrain without channel")
	await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores exact river and bridge IDs")
	history=editor._doc._undo.size(); var repeated:=await call_tool("generate_waterway",{"id":"town_river"}); check(not repeated.changed and history==editor._doc._undo.size(),"same generation is no-op")
	var bank_id: String=region.parts.filter(func(p):return p.role=="bank")[0].id
	var visual: MeshInstance3D=editor._doc._mesh(editor._doc._find(bank_id)); var textured:=false
	for i in visual.mesh.get_surface_count():
		var mat: Material=visual.mesh.surface_get_material(i)
		if mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null: textured=true
	check(textured,"bank mesh contains actual albedo and normal material"); visual.free()
	await atomic_reject("generate_buildings",{"parameters":{"floors":1},"placements":[{"position":[0,0,20]}]})
	for flag in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[bank_id],flag:true}); await atomic_reject("generate_waterway",{"id":"town_river"}); await atomic_reject("remove_waterway",{"id":"town_river"}); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":10}); await atomic_reject("generate_waterway",{"id":"town_river"}); await call_tool("undo")
	await call_tool("set_event_template",{"id":bank_id,"template":"dialogue","parameters":{"text":"Keep river edits"}})
	await atomic_reject("generate_waterway",{"id":"town_river"}); await atomic_reject("remove_waterway",{"id":"town_river","keep_objects":false})
	check((await call_tool("list_waterways")).regions[0].modified_or_missing.has(bank_id),"catalog identifies hand-edited members")
	await call_tool("remove_waterway",{"id":"town_river"}); check(editor._waterways.regions().is_empty() and editor._doc._find(bank_id).has("event_template"),"detach preserves scene and hand-authored event")
	await call_tool("undo"); await call_tool("undo")
	await call_tool("select_objects",{"ids":[bank_id]}); await call_tool("delete_selection"); await atomic_reject("generate_waterway",{"id":"town_river"}); await call_tool("undo")
	await call_tool("clear_surface_material",{"id":bank_id}); await atomic_reject("generate_waterway",{"id":"town_river"}); await call_tool("undo")
	var edit:=await call_tool("generate_waterway",{"id":"town_river","width":14}); check(edit.changed,"explicit width update replans whole river"); await call_tool("undo")
	var independent: String=editor._doc.add_box("block",Vector3(0,-.5,20),Vector3(1,1,1)); editor._rebuild()
	await atomic_reject("generate_waterway",{"id":"town_river","points":[[30,-60],[30,60]],"bridges":[]})
	await atomic_reject("remove_waterway",{"id":"town_river","keep_objects":false}); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=independent); editor._rebuild()
	await call_tool("remove_waterway",{"id":"town_river","keep_objects":false}); check(editor._doc.records.size()==1 and not editor._doc._find(ground_id).has("channel_mesh"),"delete river restores original ground"); await call_tool("undo")
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"river recipes, sources, PBR and true holes survive reopen")
	await call_tool("generate_waterway",{"id":"town_river"})
	# Real canvas clicks route through the same UI planner; then cancel the uncommitted proposal.
	editor._dock_tabs.current_tab=9; await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":155})
	var panel: VBoxContainer=editor._city.panel.waterway_panel; panel.load_region(); panel.current=region.settings.duplicate(true); panel.form()
	check(editor._city.begin_waterway(0).ok,"canvas waterway drawing starts")
	for p in [Vector3(-10,0,-60),Vector3(0,0,-35),Vector3(0,0,35),Vector3(12,0,60)]:
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=editor._camera.unproject_position(p)+editor._canvas.global_position; Input.parse_input_event(click); await settle(); click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await settle()
	var enter:=InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; Input.parse_input_event(enter); await settle()
	check(not editor._city.busy() and panel.current.points.size()==4,"Enter accepts the four-point centerline")
	panel.show_preview(); check(not panel.preview.is_empty(),"UI previews through shared planner")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(directory.path_join("waterway_preview.png"))
	panel.fields.fields.width.value=13; panel.show_preview(); history=editor._doc._undo.size(); panel.apply(); check(editor._doc._undo.size()==history+1,"UI application uses one shared transaction"); await call_tool("undo")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.5,0],"distance":75,"pitch":-50,"yaw":30}); editor._grid.hide(); await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("waterway_scene.png"))
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,-.1,0],"distance":25,"pitch":-30,"yaw":25}); await settle(); await RenderingServer.frame_post_draw
	editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("bridge_closeup.png"))
	await call_tool("save_world"); editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"saved river runtime loads")
	if loaded[0]!=null: await river_runtime(loaded[0])
	if is_instance_valid(loader): loader.queue_free()
	print("WATERWAY_ARTIFACTS "+directory); print("WORLD3D_WATERWAYS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
func river_runtime(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
	var space:=host.get_world_3d().direct_space_state
	for point in [[0,20,-2.7],[7,20,.025],[30,20,0],[0,0,.025],[10,0,.025]]:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point[0],4,point[1]),Vector3(point[0],-5,point[1])))
		check(not hit.is_empty() and absf(hit.position.y-point[2])<.006,"runtime ground / bank / bed / bridge ray "+str(point))
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.2
	for direction in [1,-1]:
		body.position=Vector3(-18*direction,1.08,0); body.velocity=Vector3.ZERO; var grounded:=true
		for i in 340:
			await physics_frame; body.velocity=Vector3(8*direction,-2,0); body.move_and_slide()
			if i>5: grounded=grounded and body.is_on_floor()
			if body.position.x*direction>18: break
		check(grounded and body.position.x*direction>18,"2.1m player crosses both bridgeheads without snagging, direction %d"%direction)
	host.free()
