extends "res://tools/test_world3d_roads.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
func run() -> void:
	create_timer(300).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("terrain_sculpt_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var ground: String=doc.add_box("grass",Vector3(0,-.25,0),Vector3(24,.5,24)); var obstacle: String=doc.add_box("block",Vector3(-7,1,-7),Vector3(2,2,2))
	check(doc.save(map_path)==OK,"temporary terrain map saved")
	var material_dir:=directory.path_join("materials"); DirAccess.make_dir_recursive_absolute(material_dir)
	var img:=Image.create(16,16,false,Image.FORMAT_RGB8); img.fill(Color(.3,.46,.2)); img.save_png(material_dir.path_join("albedo.png")); img.fill(Color(.5,.5,1)); img.save_png(material_dir.path_join("normal.png"))
	var file:=FileAccess.open(material_dir.path_join("soil.json"),FileAccess.WRITE); file.store_string(JSON.stringify({"material":{"name":"地形测试草土","color":[1,1,1,1],"roughness":.9,"texture_path":"albedo.png","normal_path":"normal.png","tile_size":[2,2]}})); file.close()
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); editor._material_directory=material_dir; root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30230
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"terrain HTTP server starts")
	var definitions: Array=(await rpc("tools/list")).result.tools
	check(definitions.size()==114 and definitions.filter(func(t):return t.name=="sculpt_terrain").size()==1 and definitions.all(func(t):return t.name!="paint_tile"),"discover 114 current 3D tools including terrain")
	var before: Array=editor._doc.records.duplicate(true); var count: int=editor._doc._undo.size()
	await atomic_reject("create_terrain",{"width":256,"depth":256,"cell_size":.25})
	await atomic_reject("create_terrain",{"center":[0,0,0]})
	await atomic_reject("create_terrain",{"source_id":ground,"width":24})
	var fresh:=await call_tool("create_terrain",{"center":[40,3,0],"width":8,"depth":8,"cell_size":.5})
	check(fresh.get("ok",false) and editor._doc._find(fresh.id).terrain_mesh.columns==16,"fresh terrain creates chosen grid away from existing objects")
	await call_tool("set_object_transform",{"id":fresh.id,"position":[40,5,0],"rotation":[0,90,0],"size":[16,2,8]})
	await call_tool("sculpt_terrain",{"id":fresh.id,"mode":"flatten","points":[[40,0]],"radius":2,"strength":3,"target_height":6})
	check(absf(Terrain.sample(editor._doc._find(fresh.id),Vector3.ZERO)-1)<.0001,"translated rotated scaled terrain uses world-space flatten height")
	await call_tool("set_object_transform",{"id":fresh.id,"rotation":[10,90,0]}); await atomic_reject("sculpt_terrain",{"id":fresh.id,"mode":"raise","points":[[40,0]]})
	for i in 4: await call_tool("undo")
	check(equivalent(before,editor._doc.records),"new patch and its transforms undo independently")
	var created:=await call_tool("create_terrain",{"source_id":ground,"cell_size":1,"material_id":"soil"})
	if not created.get("ok",false): quit(1); return
	check(created.id==ground and editor._doc.records.size()==2 and editor._doc._undo.size()==count+1,"conversion preserves identity, one mesh object and one undo")
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"conversion undo restores ground exactly")
	await call_tool("redo"); var baseline: Array=editor._doc.records.duplicate(true)
	await call_tool("list_terrains")
	var args:={"id":ground,"mode":"raise","points":[[4,4]],"radius":3,"strength":2,"hardness":.25}
	count=editor._doc._undo.size(); var preview:=await call_tool("preview_terrain_stroke",args)
	check(preview.changed_cells>0 and equivalent(baseline,editor._doc.records) and count==editor._doc._undo.size(),"stroke preview is read only")
	await call_tool("sculpt_terrain",args); check(Terrain.sample(editor._doc._find(ground),Vector3(4,0,4))==2,"HTTP raise changes actual surface")
	await call_tool("sculpt_terrain",args.merged({"mode":"smooth","strength":1},true)); check(Terrain.sample(editor._doc._find(ground),Vector3(4,0,4))<2,"HTTP smoothing reduces summit")
	await call_tool("undo"); await call_tool("sculpt_terrain",args.merged({"mode":"flatten","target_height":0,"strength":20},true)); check(Terrain.sample(editor._doc._find(ground),Vector3(4,0,4))==0,"HTTP flatten applies target height")
	await call_tool("undo"); await call_tool("sculpt_terrain",args.merged({"mode":"lower","points":[[5,-4]],"radius":2},true))
	check(Terrain.sample(editor._doc._find(ground),Vector3(5,0,-4))==-2,"HTTP lower makes pit")
	var hole_args:=args.merged({"mode":"hole","points":[[-4,4]],"radius":2},true)
	await call_tool("sculpt_terrain",hole_args); var holed: Array=editor._doc.records.duplicate(true)
	check(is_nan(Terrain.sample(editor._doc._find(ground),Vector3(-4,0,4))),"hole removes sampled ground")
	check(editor._terrain_panel.choice.get_item_text(0).contains("12 洞格"),"MCP edits refresh the terrain panel hole count")
	await call_tool("sculpt_terrain",hole_args.merged({"mode":"fill"},true)); check(Terrain.sample(editor._doc._find(ground),Vector3(-4,0,4))==0,"HTTP fill restores surface")
	await call_tool("undo"); check(equivalent(holed,editor._doc.records),"fill undo restores hole mask")
	await atomic_reject("sculpt_terrain",args.merged({"mode":"flatten"},true))
	await atomic_reject("sculpt_terrain",args.merged({"radius":-1},true))
	await atomic_reject("sculpt_terrain",args.merged({"points":[[4,4],[-7,-7]]},true))
	count=editor._doc._undo.size(); var unchanged:=await call_tool("sculpt_terrain",args.merged({"points":[[999,999]]},true))
	check(not unchanged.changed and count==editor._doc._undo.size(),"off-terrain no-op creates no history")
	await atomic_reject("sculpt_terrain",args.merged({"mode":"lower","strength":20},true))
	await call_tool("set_object_properties",{"ids":[obstacle],"locked":true,"hidden":true})
	for mode in ["raise","lower","hole"]: await atomic_reject("sculpt_terrain",args.merged({"mode":mode,"points":[[-7,-7]],"radius":2},true))
	await call_tool("undo")
	await call_tool("set_object_properties",{"ids":[ground],"locked":true}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	await call_tool("set_object_properties",{"ids":[ground],"hidden":true}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	await atomic_reject("set_terrain_material",{"id":ground,"material_id":"missing"})
	await call_tool("set_terrain_material",{"id":ground,"material_id":"builtin:checker"}); await call_tool("undo")
	# Terrain support footprints include flat cells and exclude holes and sloped cells.
	var terrain_record: Dictionary=editor._doc._find(ground); var shapes:=Foot.record_shapes(terrain_record)
	check(shapes.size()==int(terrain_record.terrain_mesh.columns*terrain_record.terrain_mesh.rows)-terrain_record.terrain_mesh.holes.count(true),"planning occupancy omits hole cells")
	check(shapes.any(func(s):return Foot.level_ground(terrain_record,s,0)) and shapes.any(func(s):return not Foot.level_ground(terrain_record,s,0)),"terraces provide level support, slopes do not claim level support")
	await atomic_reject("generate_waterway",{"id":"terrain_river","points":[[-10,0],[10,0]],"ground_ids":[ground]})
	var node: MeshInstance3D=editor._doc._mesh(editor._doc._find(ground))
	check(node.mesh.get_surface_count()==2 and node.mesh.surface_get_material(0).normal_enabled and node.mesh.surface_get_material(0).normal_texture!=null,"two terrain surfaces retain PBR normals after sculpt"); node.free()
	# UI dragging commits once, Escape restores the complete brush transaction.
	await call_tool("set_editor_camera",{"projection":"top","center":[0,0,0],"span":30}); editor._dock_tabs.current_tab=10; await settle(); await physics()
	before=editor._doc.records.duplicate(true); count=editor._doc._undo.size()
	var settings:={"mode":"raise","radius":1.5,"strength":.25,"hardness":.25,"target_height":0}
	check(editor._terrain_brush.begin(ground,settings).ok,"UI terrain brush starts")
	var dock_scroll: ScrollContainer=editor._terrain_panel.get_parent(); dock_scroll.scroll_vertical=int(editor._terrain_panel.brush_fields.position.y)-55
	await settle(); await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png(directory.path_join("terrain_panel.png"))
	await mouse_at(Vector3(2,0,-8),true); await mouse_move(Vector3(5,0,-8)); await mouse_at(Vector3(5,0,-8),false)
	check(editor._doc._undo.size()==count+1 and not equivalent(before,editor._doc.records),"multiple UI dabs are a single undo transaction")
	await atomic_reject("sculpt_terrain",args); editor._terrain_brush.cancel(); await call_tool("undo"); check(equivalent(before,editor._doc.records),"UI stroke undo restores exact data")
	check(editor._terrain_brush.begin(ground,settings).ok,"second UI brush starts")
	await mouse_at(Vector3(2,0,-8),true); await mouse_move(Vector3(5,0,-8))
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; Input.parse_input_event(escape); await settle()
	check(not editor._terrain_brush.active and equivalent(before,editor._doc.records),"Escape rolls back entire in-progress terrain stroke")
	# A support conflict after a successful dab rolls the whole UI gesture back.
	check(editor._terrain_brush.begin(ground,settings).ok,"conflict brush starts")
	await mouse_at(Vector3(-10,0,-7),true); await mouse_move(Vector3(-8.4,0,-7)); await mouse_at(Vector3(-8.4,0,-7),false); editor._terrain_brush.cancel()
	check(equivalent(before,editor._doc.records),"late collision cancels earlier dabs in the same gesture")
	# Verify exact heights/holes/PBR through draft, map reopen and runtime physics.
	await call_tool("save_editor_draft"); await call_tool("save_world"); var saved: Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":map_path}); check(equivalent(saved,editor._doc.records),"terrain and material survive save/reopen"); await call_tool("save_world")
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(map_path))
	for entry in raw.nodes:
		if entry.get("extras",{}).has("rmmo_records"):
			for r in entry.extras.rmmo_records:
				if r.has("terrain_mesh"): r.terrain_mesh.heights.pop_back()
	var bad_path:=directory.path_join("broken.gltf"); file=FileAccess.open(bad_path,FileAccess.WRITE); file.store_string(JSON.stringify(raw)); file.close()
	await atomic_reject("open_world",{"path":bad_path})
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,0,0],"distance":35,"pitch":-52,"yaw":25}); editor._grid.hide(); await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("terrain.png"))
	# Prefab dependencies include the terrain base material, not just face overrides.
	var library=preload("res://scripts/world_editor/asset_library.gd").new(directory.path_join("prefab_pack"))
	var captured:=preload("res://scripts/world_editor/prefab_library.gd").capture([editor._doc._find(ground)],library,"Terrain fixture")
	check(captured.ok,"terrain prefab packs PBR dependencies")
	if captured.ok:
		var loaded_prefab:=preload("res://scripts/world_editor/prefab_library.gd").read(captured.entry); check(loaded_prefab.ok and loaded_prefab.records[0].terrain_material.normal_path.contains("material_textures"),"terrain prefab resolves copied normal map")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"sculpted terrain runtime loads")
	if loaded[0]!=null: await runtime(loaded[0])
	print("TERRAIN_ARTIFACTS "+directory); print("TERRAIN_SCULPT_FINISHED failures=%d"%failed); quit(1 if failed else 0)
func mouse_at(point: Vector3, pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; event.position=editor._camera.unproject_position(point)+editor._canvas.global_position; Input.parse_input_event(event); await settle(); await physics()
func mouse_move(point: Vector3) -> void:
	var event:=InputEventMouseMotion.new(); event.button_mask=MOUSE_BUTTON_MASK_LEFT; event.position=editor._camera.unproject_position(point)+editor._canvas.global_position; Input.parse_input_event(event); await settle(); await physics()
func runtime(scene: Node3D) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3.ZERO); await physics()
	var space:=host.get_world_3d().direct_space_state
	var top:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4,8,4),Vector3(4,-30,4)))
	check(not top.is_empty() and absf(top.position.y-2)<.01,"runtime collision reaches actual raised height")
	var pit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(5,8,-4),Vector3(5,-30,-4)))
	check(not pit.is_empty() and absf(pit.position.y+2)<.01,"runtime pit collision follows lower surface")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4,8,4),Vector3(-4,-30,4))).is_empty(),"through-hole has no invisible top or underside collider")
	var body:=CharacterBody3D.new(); var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.height=2.1; capsule.radius=.3; shape.shape=capsule; body.add_child(shape); host.add_child(body); body.floor_snap_length=.3
	body.position=Vector3(4,3.2,4)
	for i in 45: await physics_frame; body.velocity=Vector3(0,-3,0); body.move_and_slide()
	check(body.is_on_floor() and absf(body.position.y-3.05)<.08,"2.1m character stands on sculpted summit")
	body.position=Vector3(-4,1.1,4)
	for i in 90: await physics_frame; body.velocity=Vector3(0,-8,0); body.move_and_slide()
	check(not body.is_on_floor() and body.position.y< -5,"character falls through real opening")
	host.free()
