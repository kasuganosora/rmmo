extends "res://tools/test_world3d_roads.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
func run() -> void:
	create_timer(540).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("round_walls_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("grass",Vector3(0,-.25,0),Vector3(200,.5,200)); doc.add_box("block",Vector3(15,2,15),Vector3(3,4,3)); check(doc.save(map_path)==OK,"temporary circular wall map saved")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30130
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"round wall HTTP starts")
	var definitions: Array=(await rpc("tools/list")).result.tools; var schema: Dictionary=definitions.filter(func(t):return t.name=="generate_fortification")[0].inputSchema
	check(definitions.size()==118 and schema.properties.shape.enum.has("ellipse") and schema.properties.gates.items.properties.has("angle") and schema.properties.style.enum.has("medieval_stone") and schema.properties.has("trim_material_id"),"discovery exposes circle / ellipse dimensions and gate angles")
	await call_tool("create_road_path",{"points":[[0,0,-60],[0,0,0]],"width":4}); await call_tool("generate_road_surface",{"material_id":"pack:default:paving/historic_cobble/material"})
	var args:={"id":"ring","tower_layout":"manual","shape":"ellipse","radius_x":40,"radius_z":40,"gates":[{"id":"north","angle":270,"width":6,"height":5.0,"open":1}],"stone_material_id":"pack:default:walls/castle_rubble/material","door_material_id":"pack:default:wood/worn_planks/material"}
	var before: Dictionary=editor._doc.recovery_snapshot(); var history: int=editor._doc._undo.size(); var preview:=await call_tool("preview_fortification",args)
	if not preview.get("ok",false): quit(1); return
	check(preview.outline.size()==256 and equivalent(before,editor._doc.recovery_snapshot()) and history==editor._doc._undo.size(),"ring preview readonly with sampled curved outline")
	await atomic_reject("generate_fortification",args.merged({"gates":[{"id":"low","angle":270,"width":6,"height":4.99,"open":1}]},true)); await atomic_reject("generate_fortification",args.merged({"style":"unknown"})); await atomic_reject("generate_fortification",args.merged({"trim_material_id":"missing"})); await atomic_reject("generate_fortification",args.merged({"plan_token":"stale"})); await atomic_reject("generate_fortification",args.merged({"radius_x":200,"radius_z":15},true))
	await atomic_reject("generate_fortification",args.merged({"gates":[{"id":"bad","angle":22.5,"width":6,"height":5.0,"open":1}]},true))
	await atomic_reject("generate_fortification",args.merged({"gates":[]},true))
	var obstacle: String=editor._doc.add_box("block",Vector3(40,2,0),Vector3(3,4,3)); editor._doc._find(obstacle).editor_hidden=true; editor._doc._find(obstacle).editor_locked=true; editor._rebuild()
	await atomic_reject("generate_fortification",args); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle); editor._rebuild()
	preview=await call_tool("preview_fortification",args); var generated:=await call_tool("generate_fortification",args.merged({"plan_token":preview.plan_token}))
	if not generated.get("ok",false): quit(1); return
	var after: Dictionary=editor._doc.recovery_snapshot(); await call_tool("undo"); check(equivalent(before.records,editor._doc.records) and equivalent(before.map_meta,editor._doc.map_meta),"ring undo preserves inner objects and road"); await call_tool("redo"); check(equivalent(after,editor._doc.recovery_snapshot()),"ring redo exact")
	var curved: Dictionary=editor._doc.records.filter(func(r):return r.has("fortification") and r.has("channel_mesh"))[0]; var node: MeshInstance3D=editor._doc._mesh(curved)
	check(node.mesh.surface_get_material(0).normal_enabled and node.mesh.surface_get_material(0).normal_texture!=null,"curved wall has actual PBR normals"); check(node.mesh.get_surface_count()==2,"curved masonry and coping share only two render surfaces"); node.free()
	await call_tool("set_object_properties",{"ids":[curved.uuid],"locked":true}); await atomic_reject("generate_fortification",{"id":"ring","radius_x":50}); await call_tool("undo")
	await call_tool("set_fortification_gate",{"id":"ring","gate_id":"north","open":0}); await call_tool("undo")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,2,0],"distance":122,"pitch":-48,"yaw":20}); editor._grid.hide(); await shot("circle.png")
	await call_tool("generate_fortification",{"id":"ring","radius_x":55,"radius_z":35}); check(editor._fortifications.regions()[0].settings.radius_x==55,"existing circle updates into ellipse")
	await shot("ellipse.png")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,-35],"distance":20,"pitch":-12,"yaw":15}); await shot("gate_close.png")
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"ellipse mesh, doors, recipes and PBR survive reopen"); await call_tool("save_world")
	# UI two-corner shortcut uses the same request / schema, without overwriting the map.
	var panel: VBoxContainer=editor._city.panel.fortification_panel; panel.new_region(); panel.fields.fields.shape.select(1); panel.fields.fields.shape.item_selected.emit(1)
	editor._dock_tabs.current_tab=9; await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":210}); check(editor._city.begin_fortification(0).ok,"UI begins circular bounds drawing")
	for p in [Vector3(-30,0,-20),Vector3(30,0,20)]:
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=editor._camera.unproject_position(p)+editor._canvas.global_position; Input.parse_input_event(click); await settle(); click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await settle()
	var enter:=InputEventKey.new(); enter.pressed=true; enter.keycode=KEY_ENTER; Input.parse_input_event(enter); await settle()
	var request: Dictionary=panel.request(); check(not editor._city.busy() and request.shape=="ellipse" and is_equal_approx(request.radius_x,30) and is_equal_approx(request.radius_z,20),"two corners define ellipse center and radii in UI")
	check(equivalent(saved.records,editor._doc.records),"unapplied UI ellipse draft leaves map intact")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished; check(loaded[0]!=null,"saved ellipse runtime loads")
	if loaded[0]!=null: await runtime_ring(loaded[0])
	if is_instance_valid(loader): loader.queue_free()
	print("ROUND_WALL_ARTIFACTS "+directory); print("ROUND_WALLS_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)
func shot(name_: String) -> void:
	await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(name_))
func runtime_ring(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3(0,0,-35)); await physics()
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.2
	for amount in [0,1]:
		check(Fixtures.set_runtime(scene,"fortification:ring","north",amount,.15).ok,"curved gate animation starts")
		for i in 20: await physics_frame
		body.position=Vector3(0,1.08,-45); var grounded:=true
		for i in 180:
			await physics_frame; body.velocity=Vector3(0,-2,8); body.move_and_slide()
			if i>5: grounded=grounded and body.is_on_floor()
			if body.position.z> -28: break
		check(grounded and (body.position.z< -35 if amount==0 else body.position.z> -28),"2.1m capsule obeys curved gate collision: %d"%amount)
	var space:=host.get_world_3d().direct_space_state
	for x in [-2.8,0.0,2.8]:
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,4.99,-40),Vector3(x,4.99,-30))).is_empty(),"gate full-width 5m clearance remains open at x=%s"%x)
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,3.5,-40),Vector3(0,3.5,-30))).is_empty(),"3.5m third-person camera corridor clear")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(65,2,0),Vector3(45,2,0))).is_empty(),"ellipse wall collision follows curved perimeter")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-10,2,0),Vector3(10,2,0))).is_empty(),"ellipse interior has no phantom solid fill")
	host.free()
