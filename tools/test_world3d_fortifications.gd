extends "res://tools/test_world3d_roads.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
func run() -> void:
	create_timer(450).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("fortifications_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground:=doc.add_box("grass",Vector3(0,-.25,0),Vector3(150,.5,150)); doc._find(ground).color=[.32,.41,.25]; check(doc.save(map_path)==OK,"temporary fortification map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30120
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"fortification HTTP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools; check(definitions.size()==109 and definitions.any(func(t):return t.name=="preview_fortification" and t.annotations.readOnlyHint),"109 tools expose fortification generation and gate control")
	await call_tool("create_road_path",{"points":[[0,0,-55],[0,0,0]],"width":4}); await call_tool("generate_road_surface",{})
	var args:={"id":"city_wall","points":[[-30,-30],[30,-30],[30,30],[-30,30]],"closed":true,"gates":[{"id":"north","segment":0,"t":.5,"width":6,"height":4.5,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size()
	var preview:=await call_tool("preview_fortification",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.gates.size()==1 and equivalent(preview,await call_tool("preview_fortification",args)),"wall preview reproducible")
	check(equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"wall preview readonly")
	await atomic_reject("generate_fortification",args.merged({"plan_token":"stale"}))
	await atomic_reject("generate_fortification",args.merged({"gates":[]},true))
	await atomic_reject("generate_fortification",args.merged({"height":2},true))
	await atomic_reject("generate_fortification",args.merged({"base_height":2},true))
	await atomic_reject("generate_fortification",args.merged({"stone_material_id":"missing"},true))
	await atomic_reject("generate_fortification",args.merged({"points":[[-20,-20],[20,20],[-20,20],[20,-20]]},true))
	var obstacle: String=editor._doc.add_box("block",Vector3(20,2,-30),Vector3(3,4,3)); editor._doc._find(obstacle).editor_hidden=true; editor._doc._find(obstacle).editor_locked=true; editor._rebuild()
	await atomic_reject("generate_fortification",args); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle); editor._rebuild()
	preview=await call_tool("preview_fortification",args); before=editor._doc.recovery_snapshot(); history=editor._doc._undo.size()
	var generated:=await call_tool("generate_fortification",args.merged({"plan_token":preview.plan_token}))
	if not generated.get("ok",false): quit(1); return
	check(editor._doc._undo.size()==history+1,"wall and gates form one transaction")
	var after: Dictionary=editor._doc.recovery_snapshot(); await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"wall undo preserves road and terrain"); await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"wall redo exact")
	history=editor._doc._undo.size(); var repeat_:=await call_tool("generate_fortification",{"id":"city_wall"}); check(not repeat_.changed and history==editor._doc._undo.size(),"wall regeneration is no-op")
	var id: String=generated.ids[0]; var record: Dictionary=editor._doc._find(id); var node: MeshInstance3D=editor._doc._mesh(record); var textured:=false
	for i in node.mesh.get_surface_count():
		var mat: Material=node.mesh.surface_get_material(i)
		if mat is StandardMaterial3D and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null: textured=true
	check(textured,"castle wall uses actual PBR stone and normals"); node.free()
	for flag in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[id],flag:true}); await atomic_reject("generate_fortification",{"id":"city_wall"}); await atomic_reject("set_fortification_gate",{"id":"city_wall","gate_id":"north","open":0}); await atomic_reject("remove_fortification",{"id":"city_wall"}); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":10}); await atomic_reject("generate_fortification",{"id":"city_wall"}); await call_tool("undo")
	await call_tool("set_event_template",{"id":id,"template":"dialogue","parameters":{"text":"Do not overwrite wall"}}); await atomic_reject("generate_fortification",{"id":"city_wall"}); check((await call_tool("list_fortifications")).regions[0].modified_or_missing.has(id),"hand edits reported"); await call_tool("undo")
	await atomic_reject("set_fortification_gate",{"id":"city_wall","gate_id":"north","open":2})
	await call_tool("set_fortification_gate",{"id":"city_wall","gate_id":"north","open":0}); check(editor._doc.records.filter(func(r):return r.has("fortification") and r.has("fixture")).all(func(r):return r.fixture.open==0),"HTTP gate close updates both leaves")
	await call_tool("generate_road_surface",{}); await call_tool("undo"); check(editor._doc.records.filter(func(r):return r.has("fortification") and r.has("fixture")).all(func(r):return r.fixture.open==1),"gate state undo restores open pose")
	await call_tool("remove_fortification",{"id":"city_wall"}); check(editor._doc.records.all(func(r):return not r.has("fortification")),"detach clears ownership and bakes current gate pose"); await call_tool("undo")
	await call_tool("remove_fortification",{"id":"city_wall","keep_objects":false}); check(editor._fortifications.regions().is_empty() and editor._doc.records.all(func(r):return not r.has("fortification")),"remove preserves preexisting roads and ground"); await call_tool("undo")
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"walls, gates, grouping and materials survive reopen"); await call_tool("save_world")
	var original_gate: Dictionary=editor._doc.records.filter(func(r):return r.has("fortification") and r.has("fixture"))[0]
	var gate_pose:=Fixtures.transform(original_gate); await call_tool("select_objects",{"ids":[original_gate.uuid]}); var copy_result:=await call_tool("duplicate_selection",{})
	var copied_gate: Dictionary=editor._doc._find(copy_result.selection[0]); check(not copied_gate.has("fortification") and not copied_gate.has("fixture") and Fixtures.transform(copied_gate).basis.is_equal_approx(gate_pose.basis),"ordinary gate copy bakes pose and has independent ownership"); await call_tool("undo")
	# Shared UI drawing and generation on an independent second wall.
	editor._dock_tabs.current_tab=9; await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":160})
	var panel: VBoxContainer=editor._city.panel.fortification_panel; panel.new_region(); check(editor._city.begin_fortification(0).ok and (await call_tool("editor_state")).fortification_drawing,"UI begins wall path and MCP exposes drawing state")
	for p in [Vector3(55,0,-25),Vector3(55,0,25)]:
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=editor._camera.unproject_position(p)+editor._canvas.global_position; Input.parse_input_event(click); await settle(); click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await settle()
	var enter:=InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; Input.parse_input_event(enter); await settle(); check(not editor._city.busy() and panel.current.points.size()==2,"Enter commits wall draft")
	panel.show_preview(); check(not panel.preview.is_empty(),"UI wall preview uses shared planner"); history=editor._doc._undo.size(); panel.apply(); check(editor._doc._undo.size()==history+1,"UI wall application one transaction"); await call_tool("undo")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,2,0],"distance":100,"pitch":-40,"yaw":30}); editor._grid.hide(); await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("walls.png"))
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,-30],"distance":24,"pitch":-18,"yaw":175}); await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("gate.png"))
	await call_tool("save_world"); editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished; check(loaded[0]!=null,"fortification runtime loads")
	if loaded[0]!=null: await gate_runtime(loaded[0])
	if is_instance_valid(loader): loader.queue_free()
	print("FORTIFICATION_ARTIFACTS "+directory); print("FORTIFICATIONS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
func gate_runtime(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3(0,0,-30)); await physics()
	check(Fixtures.list_runtime(scene,"fortification:city_wall").size()==1,"runtime discovers fortification gate without masquerading as house")
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.2
	for amount in [0,1]:
		check(Fixtures.set_runtime(scene,"fortification:city_wall","north",amount,.15).ok,"programmatic gate animation starts")
		for i in 20: await physics_frame
		body.position=Vector3(0,1.08,-40); body.velocity=Vector3.ZERO; var grounded:=true
		for i in 210:
			await physics_frame; body.velocity=Vector3(0,-2,8); body.move_and_slide()
			if i>5: grounded=grounded and body.is_on_floor()
			if body.position.z> -20: break
		check(grounded and (body.position.z< -30 if amount==0 else body.position.z> -20),"closed gate blocks / open gate lets 2.1m player through: %d"%amount)
	host.free()
