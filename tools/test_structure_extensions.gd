extends "res://tools/test_world3d_mcp.gd"
const T=preload("res://scripts/world3d/terrain_surface.gd")
const B=preload("res://scripts/world3d/bridge_mesh.gd")
var directory:String
func run()->void:
	create_timer(300).timeout.connect(func():quit(2))
	rpc_timeout_ms=60000
	directory=Paths.cache_directory("structure_extensions_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new()
	doc.add_box("stone",Vector3(0,-5.25,0),Vector3(120,.5,55))
	for z in [-16.,16.]:
		doc.add_box("grass",Vector3(-15,-.25,z),Vector3(10,.5,16))
		doc.add_box("grass",Vector3(15,.75,z),Vector3(10,.5,16))
	doc.add_box("grass",Vector3(-38,-.25,90),Vector3(54,.5,40))
	doc.add_box("grass",Vector3(38,-.25,90),Vector3(54,.5,40))
	doc.add_box("stone",Vector3(0,-4.25,90),Vector3(22,.5,40))
	check(doc.save(path)==OK,"structure fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=30740
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"structure real HTTP")
	var tools:Array=(await rpc("tools/list")).result.tools
	check(tools.any(func(t):return t.name=="generate_bridge" and t.inputSchema.properties.has("wing_length")),"bridge schema discoverable")
	var catalog:=await call_tool("list_bridge_prefabs")
	check(catalog.prefabs.any(func(p):return p.id=="timber_trestle"),"timber prefab discoverable")
	for i in 2:
		var z:float=[-16.,16.][i]
		var args:={"id":"extension_bridge_%d"%i,"prefab_id":["timber_trestle","stone_segmental"][i],"start":[-10,0,z],"end":[10,1,z],"width":6.,"depth":5.,"camber":.2,"wing_length":2.,"wear":.25,"moss":.2,"variation_seed":19}
		var before:Dictionary=editor._doc.recovery_snapshot()
		var preview:=await call_tool("preview_bridge",args)
		check(equivalent(before,editor._doc.recovery_snapshot()),"bridge preview read only")
		if not preview.get("ok",false):continue
		var prepared:Dictionary=editor._bridges.prepare(args);var mesh:=B.new().build(prepared.record)
		check(mesh!=null and mesh.get_surface_count()==3,"bridge actual module geometry")
		check(absf(B.height_at(-10,prepared.record.bridge_mesh)+.5)<.001 and absf(B.height_at(10,prepared.record.bridge_mesh)-.5)<.001,"both bridgehead elevations exact")
		var history:int=editor._doc._undo.size()
		await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token}))
		check(editor._doc._undo.size()==history+1 and editor._doc._find(args.id).has("house_prefab"),"bridge freezes shared geometry in one transaction")
		var created:Dictionary=editor._doc.recovery_snapshot()
		await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"bridge undo exact")
		await call_tool("redo");check(equivalent(created,editor._doc.recovery_snapshot()),"bridge redo exact")
	var terrain:=await call_tool("create_terrain",{"center":[0,0,48],"width":80.,"depth":24.,"cell_size":2.})
	if terrain.get("ok",false):
		var record:Dictionary=editor._doc._find(terrain.id)
		for z in int(record.terrain_mesh.rows)+1:
			for x in int(record.terrain_mesh.columns)+1:record.terrain_mesh.heights[z*(int(record.terrain_mesh.columns)+1)+x]=T.point(record,x,z).x*.04/record.size[1]
		editor._rebuild()
		await fortification({"id":"slope_spline","shape":"spline","points":[[-30,44],[0,48],[30,44]],"follow_terrain":true,"style":"medieval_stone","corner_towers":false,"wall_access":false,"arrow_slits":false,"battlements":true,"height":7.5,"thickness":2.5})
	await fortification({"id":"water_arches","shape":"path","points":[[-50,90],[50,90]],"style":"medieval_stone","corner_towers":false,"wall_access":false,"arrow_slits":false,"battlements":true,"height":8.,"thickness":3.5,"gates":[{"id":"river","segment":0,"t":.5,"kind":"water","width":24.,"height":5.,"open":1.,"water_depth":4.,"grille":true}]})
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("generate_fortification",{"id":"bad_spline","shape":"spline","points":[[0,0],[0,0]]},false)
	check(equivalent(before,editor._doc.recovery_snapshot()),"invalid spline has no side effects")
	await call_tool("save_world");var saved:Array=editor._doc.records.duplicate(true)
	await call_tool("open_world",{"path":path});check(equivalent(saved,editor._doc.records),"structure native save reopen")
	await preload("res://tools/extension_physics_fixture.gd").bridges(self,editor._doc,check)
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,1000);root.content_scale_size=root.size
		editor._grid.hide()
		for shot:Array in [["timber",[0,0,-16],27,-18,30],["timber_detail",[-8,1,-16],10,-14,30],["stone",[0,0,16],27,-18,30],["slope_wall",[0,5,46],50,-25,30],["water_gate",[0,4,90],45,-12,0],["water_gate_detail",[0,6,90],17,-8,0],["far",[0,1,0],90,-28,40]]:
			await call_tool("set_editor_camera",{"projection":"perspective","center":shot[1],"distance":shot[2],"pitch":shot[3],"yaw":shot[4]})
			await settle();await RenderingServer.frame_post_draw
			editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0]+".png"))
	print("STRUCTURE_EXTENSIONS_ARTIFACTS ",directory)
	editor._mcp.stop();editor.queue_free();await settle()
	print("STRUCTURE_EXTENSIONS_FINISHED failures=",failed);quit(0 if failed==0 else 1)
func fortification(args:Dictionary)->void:
	var before:Dictionary=editor._doc.recovery_snapshot()
	if args.id=="water_arches":
		var shallow:=args.duplicate(true);shallow.gates[0].water_depth=2.
		await call_tool("preview_fortification",shallow,false)
		check(equivalent(before,editor._doc.recovery_snapshot()),"short water piers reject without mutation")
	var p:=await call_tool("preview_fortification",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"fortification preview read only")
	if not p.get("ok",false):return
	var prepared:Dictionary=editor._fortifications.prepare(args)
	if args.id=="slope_spline":check(prepared.records.any(func(r):return r.get("terrain_grade",[0,0])!=[0,0]),"spline wall follows physical slope")
	if args.id=="water_arches":check(prepared.records.filter(func(r):return r.has("water_gate")).size()==3,"water gate has three real arch bays")
	var h:int=editor._doc._undo.size()
	await call_tool("generate_fortification",args.merged({"plan_token":p.plan_token}))
	check(editor._doc._undo.size()==h+1,"fortification one transaction")
	var created:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"fortification undo exact")
	await call_tool("redo");check(equivalent(created,editor._doc.recovery_snapshot()),"fortification redo exact")
	if args.id=="water_arches":
		var leaves:Array=editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")==args.id and r.has("fixture"))
		check(leaves.size()>=6,"each water-gate leaf keeps its own physical hinge after freezing")
		await call_tool("set_fortification_gate",{"id":args.id,"gate_id":"river","open":0.})
		check(leaves.all(func(r):return editor._doc._find(r.uuid).fixture.open==0.),"MCP closes all grille leaves")
		await preload("res://tools/extension_physics_fixture.gd").closed_grilles(self,editor._doc,check)
		if DisplayServer.get_name()!="headless":
			await call_tool("set_editor_camera",{"center":[0,4,90],"distance":40.,"pitch":-8.,"yaw":0.})
			await settle();await RenderingServer.frame_post_draw
			editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join("water_grilles_closed.png"))
		await call_tool("undo");check(equivalent(created,editor._doc.recovery_snapshot()),"water grille undo restores all leaf states")
