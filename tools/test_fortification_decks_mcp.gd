extends "res://tools/test_world3d_roads.gd"
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));Engine.max_fps=30
	directory=Paths.cache_directory("deck_mcp_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("grass",Vector3(0,-.3,0),Vector3(120,.6,120));check(doc.save(map_path)==OK,"temporary map saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	var probe:=TCPServer.new();port=30710
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real HTTP server starts")
	var defs:Array=(await rpc("tools/list")).result.tools
	check(defs.any(func(d):return d.name=="generate_fortification") and defs.any(func(d):return d.name=="bake_fortification"),"3D generation and baking remain discoverable")
	var args:={"id":"deck_test","tower_layout":"manual","points":[[-20,0],[20,0]]}
	await atomic_reject("generate_fortification",args.merged({"height":2}))
	var preview:=await call_tool("preview_fortification",args)
	await call_tool("generate_fortification",args)
	var baseline:Dictionary=editor._doc.recovery_snapshot()
	var records:Array=editor._doc.records.filter(func(r):return r.has("fortification")).duplicate(true)
	var texture:=""
	for r:Dictionary in records:
		for p:Dictionary in r.get("prefab_materials",[]):
			if p.get("texture_path","").contains("/paving/"):texture=p.texture_path
	var audit:=preload("res://scripts/world3d/fortification_deck_cleanup.gd").apply(records,preview.settings.base_height+preview.settings.height,texture)
	check(audit.ok and audit.overlap_area<.0001,"HTTP-generated tower joins contain no overlapping deck area")
	await call_tool("undo");check(not editor._doc.records.any(func(r):return r.has("fortification")),"one undo removes full structure")
	await call_tool("redo");check(equivalent(baseline,editor._doc.recovery_snapshot()),"redo restores repaired frozen geometry and ownership")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("open_world",{"path":map_path});check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"native save/reopen retains repaired geometry")
	editor._mcp.stop();editor.queue_free();await settle()
	print("DECK_MCP_FINISHED failures=",failed);quit(1 if failed else 0)
