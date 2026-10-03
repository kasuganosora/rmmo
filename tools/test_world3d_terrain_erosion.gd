extends "res://tools/build_river_bank_lab.gd"
func run() -> void:
	create_timer(360).timeout.connect(func():quit(2)); Engine.max_fps=60; root.size=Vector2i(1800,1200); root.content_scale_size=root.size
	directory=Paths.cache_directory("terrain_erosion_%d"%Time.get_ticks_usec()); map_path=directory.path_join("map.gltf")
	var town_hash:=FileAccess.get_sha256(TOWN); var doc=Doc.open_file(MAP)
	var steep: String=doc.records.filter(func(r):return r.get("editor_name","").begins_with("C 陡岸"))[0].uuid
	var hill: String=doc.records.filter(func(r):return r.get("editor_name","").begins_with("G 隆起"))[0].uuid
	var wall: String=doc.records.filter(func(r):return r.get("editor_name","").begins_with("D 水渠 · 垂直"))[0].uuid
	check(doc.save(map_path)==OK,"temporary independent erosion fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle(); editor._safety.enabled=false
	var probe:=TCPServer.new(); port=30710
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"erosion real loopback MCP")
	var defs: Array=(await rpc("tools/list")).result.tools
	var schema: Dictionary=defs.filter(func(d):return d.name=="sculpt_terrain")[0].inputSchema
	check(defs.size()==114 and schema.properties.mode.enum.has("erode") and schema.properties.has("talus_angle"),"HTTP discovers bounded erosion schema")
	check(editor._terrain_panel.brush_fields.fields.has("iterations") and editor._terrain_panel.brush_fields.fields.has("erosion_seed"),"UI exposes same erosion parameters")
	editor._grid.hide(); editor._city.overlay.hide(); editor._authoring.marker.hide()
	var camera_args:={"projection":"perspective","center":[20.8,0.,0],"distance":11,"pitch":-22,"yaw":-64}
	await shot("weathering_before",camera_args)
	var args:={"id":steep,"mode":"erode","points":[[21.,0]],"radius":14.,"strength":6.,"iterations":16,"talus_angle":38.,"erosion_seed":17}
	var before: Array=editor._doc.records.duplicate(true); var count: int=editor._doc._undo.size()
	var preview:=await call_tool("preview_terrain_stroke",args)
	check(preview.ok and preview.changed and equivalent(before,editor._doc.records) and count==editor._doc._undo.size(),"erosion preview changes no state")
	var result:=await call_tool("sculpt_terrain",args); var applied: Array=editor._doc.records.duplicate(true)
	check(result.ok and result.changed and editor._doc._undo.size()==count+1,"erosion across non-solid river water is one transaction")
	await call_tool("undo"); check(equivalent(before,editor._doc.records),"erosion undo restores all heights")
	await call_tool("redo"); check(equivalent(applied,editor._doc.records),"erosion redo restores all heights and materials")
	for invalid in [{"iterations":33},{"talus_angle":0},{"erosion_seed":-1},{"iterations":32,"radius":32.,"points":[[0,-30],[0,30],[0,-30],[0,30]]}]: await atomic_reject("sculpt_terrain",args.merged(invalid,true))
	for property in ["locked","hidden"]:
		await call_tool("set_object_properties",{"ids":[steep],property:true}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	await call_tool("set_floor_view",{"isolation":true,"base_height":30}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	await call_tool("set_object_transform",{"id":wall,"position":[21,-1,0]}); await atomic_reject("sculpt_terrain",args); await call_tool("undo")
	# Use the real interactive transaction and cancel path with the erosion settings.
	var settings:=args.duplicate(true); settings.erase("id"); settings.erase("points")
	check(editor._terrain_brush.begin(steep,settings).ok,"UI erode brush begins")
	editor._terrain_brush.before=editor._doc.records.duplicate(true); editor._terrain_brush.was_dirty=editor._dirty; editor._terrain_brush.pointer_down=true
	check(editor._terrain.sculpt(args,true).ok,"UI erode uses shared sculpt operation")
	editor._terrain_brush.finish(true); editor._terrain_brush.cancel()
	check(equivalent(applied,editor._doc.records),"UI cancellation rolls back erosion")
	editor._selection_tools.ids.clear(); editor._refresh_selection(); editor._gizmo.hide()
	await shot("weathering_after",camera_args)
	await call_tool("sculpt_terrain",{"id":hill,"mode":"erode","points":[[32,48]],"radius":11.,"strength":4.,"iterations":12,"erosion_seed":81})
	await shot("weathering_hill",{"projection":"perspective","center":[32,3,48],"distance":29,"pitch":-28,"yaw":25})
	await call_tool("save_world"); var saved: Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":map_path}); check(equivalent(saved,editor._doc.records),"weathered geometry and PBR survive save and reopen")
	var r: Dictionary=editor._doc._find(steep); var expected:=Terrain.sample(r,Vector3(5.25,0,0))+float(r.position[1])
	var measured:={}; var start:=Time.get_ticks_usec(); var pure:=Terrain.stroke(r,args); measured.erosion_ms=(Time.get_ticks_usec()-start)/1000.
	start=Time.get_ticks_usec(); var mesh:=Terrain.mesh(pure.record,null); measured.mesh_rebuild_ms=(Time.get_ticks_usec()-start)/1000.
	start=Time.get_ticks_usec(); var shape:=mesh.create_trimesh_shape(); measured.collision_build_ms=(Time.get_ticks_usec()-start)/1000.
	check(shape!=null and mesh.get_surface_count()==2,"weathering remains one mesh with two surfaces")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"weathered map runtime loads")
	if loaded[0]!=null:
		var host:=Node3D.new(); root.add_child(host); host.add_child(loaded[0]); Stream.sync(loaded[0],host,Vector3(21,0,0)); await physics()
		var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(21.25,8,0),Vector3(21.25,-8,0)))
		check(not hit.is_empty() and absf(hit.position.y-expected)<.015,"runtime collision matches weathered visible surface through water")
		host.queue_free(); await settle()
	check(FileAccess.get_sha256(TOWN)==town_hash,"existing town unchanged")
	if failed==0:
		var destination=Doc.open_file(MAP)
		check(destination!=null and destination.map_meta.get("river_bank_lab",false),"lab destination is owned test map")
		if failed==0:
			destination.records=saved; check(destination.save(MAP)==OK,"publish weathered independent lab")
	measured.failures=failed; measured.map=MAP
	var f:=FileAccess.open(OUTPUT.path_join("weathering.json"),FileAccess.WRITE); f.store_string(JSON.stringify(measured,"\t")); f.close()
	print("EROSION_EDITOR_TIMINGS ",JSON.stringify(measured)); print("TERRAIN_EROSION_MCP_FINISHED failures=",failed); quit(1 if failed else 0)
