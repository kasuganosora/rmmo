extends "res://tools/test_world3d_mcp.gd"
const Bank=preload("res://scripts/world3d/rock_bank_mesh.gd")
func run()->void:
	var path:=Paths.external_root()+"/cache/world3d/rock_bank_test_%d/map.gltf"%Time.get_ticks_usec()
	var doc:=Doc.new();check(doc.save(path)==OK,"isolated map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"loopback server")
	var discovery:=await rpc("tools/list");var names:Array=discovery.result.tools.map(func(t):return t.name)
	for name_ in ["list_rock_banks","preview_rock_bank","set_rock_bank","remove_rock_bank"]:check(name_ in names,"discover "+name_)
	var args:={"id":"test_bank","points":[[0,1,0],[0,1,5],[1,1,10]],"inner_heights":[0,0,0],"height":3.,"cap_width":3.,"roughness":.25,"seed":17}
	await call_tool("preview_rock_bank",args);check(doc.records.is_empty() and doc._undo.is_empty(),"preview has no mutation/history")
	await call_tool("set_rock_bank",args)
	var first:Array=doc.records.duplicate(true)
	if first.is_empty():editor.queue_free();await settle();quit(1);return
	await call_tool("set_rock_bank",args.merged({"id":"second_bank","points":[[0,1,20],[0,1,25],[1,1,30]]},true))
	editor._selection_tools.ids.clear();editor._refresh_selection();editor._ground_batches.flush()
	var batch_state:=await call_tool("editor_state",{})
	check(batch_state.ground_batching.source_objects==2 and batch_state.ground_batching.render_surfaces==2,"HTTP created banks automatically merge four surfaces into two")
	await call_tool("remove_rock_bank",{"id":"second_bank"})
	var mesh:=Bank.mesh(first[0]);var arrays:=mesh.surface_get_arrays(0);var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	check(normals[0].y>.8,"grass cap faces up")
	check(mesh.get_faces().size()>100,"real mesh faces for collision")
	check(Bank.arrays(first[0])==Bank.arrays(first[0]),"deterministic geometry")
	var history:int=doc._undo.size()
	for invalid in [{"height":0},{"points":[[0,0,0],[0,0,0]]},{"rock_material_id":"missing"},{"id":"test_bank","points":[[0,0,0],[10,0,10],[0,0,10],[10,0,0]]}]:
		await call_tool("set_rock_bank",args.merged(invalid,true),false)
		check(equivalent(first,doc.records) and doc._undo.size()==history,"invalid update has no side effects")
	await call_tool("set_object_properties",{"ids":["test_bank"],"locked":true})
	await call_tool("set_rock_bank",{"id":"test_bank","height":4},false)
	await call_tool("remove_rock_bank",{"id":"test_bank"},false)
	await call_tool("set_object_properties",{"ids":["test_bank"],"locked":false})
	await call_tool("set_object_properties",{"ids":["test_bank"],"hidden":true})
	await call_tool("set_rock_bank",{"id":"test_bank","height":4},false)
	await call_tool("set_object_properties",{"ids":["test_bank"],"hidden":false})
	await call_tool("create_terrain",{"source_id":"test_bank"},false)
	await call_tool("set_floor_view",{"isolation":true,"base_height":5.,"floor_height":3.})
	await call_tool("set_rock_bank",{"id":"test_bank","height":4},false)
	await call_tool("set_floor_view",{"base_height":0.})
	await call_tool("preview_rock_bank",{"id":"test_bank","height":4})
	await call_tool("set_floor_view",{"isolation":false})
	first=doc.records.duplicate(true)
	await call_tool("set_rock_bank",{"id":"test_bank","height":4.,"seed":19})
	check(doc.records.size()==1 and doc.records[0].rock_bank.height==4,"stable update identity")
	await call_tool("undo");check(equivalent(first,doc.records),"undo restores recipe")
	await call_tool("redo");check(doc.records[0].rock_bank.height==4,"redo restores update")
	var panel=editor._terrain_panel.rock_banks;panel.load_record("test_bank")
	check(panel.points.size()==3 and panel.fields.values().height==4,"UI loads same editable recipe")
	await call_tool("save_world");var reopened=Doc.open_file(path)
	check(reopened!=null and equivalent(doc.records,reopened.records),"save reopen preserves native geometry and dependencies")
	await call_tool("remove_rock_bank",{"id":"test_bank"});check(doc.records.is_empty(),"delete bank")
	await call_tool("undo");check(doc.records.size()==1,"undo delete")
	await call_tool("set_rock_bank",{"id":"test_bank","inner_widths":[2.,3.,2.5],"direction_mode":"fixed","cap_angle":180.})
	panel.load_record("test_bank");check(panel.inner_widths.size()==3 and panel.fields.values().direction_mode=="fixed","UI restores varying width and directional cap")
	var before_args:=args.duplicate(true);preload("res://scripts/world_editor/rock_bank_tools.gd").plan(Doc.new(),args,editor._material_tool.library,func(_r):return true)
	check(equivalent(args,before_args),"preview does not mutate caller path arrays")
	var source_path:=Paths.external_root()+"/maps/medieval_river_town/map.gltf"
	if FileAccess.file_exists(source_path):
		var records:Array=Doc.authoritative_extras(source_path).extras.rmmo_records
		var bridge:Dictionary=records.filter(func(r):return r.uuid=="stone_e_0be972769041dbc9")[0]
		var pose:=Transform3D(Basis.from_euler(Bank.vec(bridge.rotation)*PI/180),Bank.vec(bridge.position));var foot=preload("res://scripts/world_editor/building_footprint.gd");var bank_tools=preload("res://scripts/world_editor/rock_bank_tools.gd")
		for spec in [[Vector3(0,-2,0),false,"open arch"],[Vector3(-bridge.bridge_mesh.length*.5+.5,-1,0),true,"solid abutment"]]:
			var points:Array[Vector3]=[];var box:=AABB(spec[0]-Vector3.ONE*.15,Vector3.ONE*.3)
			for i in 8:points.append(pose*box.get_endpoint(i))
			var shape:Dictionary=foot.from_points(points)
			check(bank_tools.bridge_overlap([shape],bridge,shape.bounds)==spec[1],"narrow bridge collision: "+spec[2])
	if "--capture-ui" in OS.get_cmdline_user_args():
		root.size=Vector2i(1600,1000);editor._dock_tabs.current_tab=10;editor._terrain_panel.tasks.current_tab=2
		await call_tool("set_editor_camera",{"center":[-1,0,5],"distance":20.,"pitch":-35.,"yaw":-25.,"projection":"perspective"})
		for i in 20:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Paths.external_root()+"/review_artifacts/bridge_terrain_20261006/editor_rock_bank.png")
	editor.queue_free();await settle();print("ROCK_BANK_TEST failures=",failed);quit(1 if failed else 0)
