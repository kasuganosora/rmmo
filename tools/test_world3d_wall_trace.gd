extends "res://tools/test_world3d_fortification_spacing.gd"
func run() -> void:
	create_timer(600).timeout.connect(func():quit(2)); root.size=Vector2i(1280,960); root.content_scale_size=root.size
	directory=Paths.cache_directory("wall_trace_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var id:=doc.add_box("grass",Vector3.ZERO,Vector3(200,1,160)); var r: Dictionary=doc._find(id)
	r.terrain_mesh={"version":1,"columns":8,"rows":8,"floor":-2.0,"heights":[],"holes":[]}
	for i in 81: r.terrain_mesh.heights.append(-.05)
	for i in 64: r.terrain_mesh.holes.append(false)
	check(doc.save(map_path)==OK,"temporary uneven foundation fixture")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=31820
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"trace HTTP starts")
	var args:={"id":"trace","points":[[-60,0],[-30,-4],[0,-5],[30,-4],[60,0]],"tower_indices":[0,4],"terrain_foundation":true}
	await atomic_reject("generate_fortification",args.merged({"tower_indices":[0,0]},true))
	await atomic_reject("generate_fortification",args.merged({"terrain_foundation":false},true))
	await atomic_reject("generate_fortification",args.merged({"base_height":2.0},true))
	var plan:=await call_tool("preview_fortification",args); check(plan.get("tower_count")==2,"five bends produce only two explicitly selected towers")
	if not plan.get("ok",false): quit(1); return
	await call_tool("generate_fortification",args); var expected: Array=editor._doc.records.duplicate(true)
	await call_tool("undo"); check(editor._doc.records.size()==1,"selected tower wall undoes as one transaction")
	await call_tool("redo"); check(equivalent(expected,editor._doc.records),"selected tower wall redo exact")
	var panel=editor._city.panel.fortification_panel; panel.current=editor._fortifications.regions()[0].settings.duplicate(true); panel.form()
	check(equivalent(panel.request().tower_indices,[0,4]) and panel.request().terrain_foundation,"UI shows independent tower selection")
	panel.tower_nodes.text=""; check(equivalent(panel.request().tower_indices,[0,1,2,3,4]),"clearing UI selection explicitly restores every path node")
	panel.form()
	await call_tool("save_world"); await call_tool("open_world",{"path":map_path}); check(equivalent(expected,editor._doc.records),"trace parameters and geometry survive native reopen")
	editor._mcp.stop(); editor.queue_free(); await settle(); print("WALL_TRACE_HTTP_FINISHED failures=",failed); quit(1 if failed else 0)
