extends "res://tools/test_world3d_mcp.gd"
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	var path:=Paths.cache_directory("bridge_surface_%d"%Time.get_ticks_usec())+"/map.gltf"
	var doc:=Doc.new();doc.add_box("stone",Vector3(0,-5.25,0),Vector3(40,.5,20))
	for side in [-1,1]:doc.add_box("grass",Vector3(side*12,-.25,0),Vector3(10,.5,16))
	check(doc.save(path)==OK,"temporary native bridge map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;root.add_child(editor);await settle()
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"HTTP bridge server")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="generate_bridge"),"native 3D bridge discovered")
	var args:={"id":"surface_bridge","prefab_id":"stone_rustic","start":[-7,0,0],"end":[7,0,0],"width":5.,"depth":5.,"camber":0.}
	var preview:=await call_tool("preview_bridge",args)
	if not preview.get("ok",false):editor.queue_free();await settle();quit(1);return
	await call_tool("generate_bridge",args.merged({"plan_token":preview.plan_token},true))
	var record:Dictionary=doc._find("surface_bridge")
	check(record.has("house_prefab"),"UI/MCP shared generator freezes corrected mesh")
	if not record.has("house_prefab"):editor.queue_free();await settle();quit(1);return
	var mesh:Mesh=preload("res://scripts/world3d/house_prefab.gd").geometry(record).mesh
	var upward:=true
	for normal:Vector3 in mesh.surfaces[0][Mesh.ARRAY_NORMAL]:upward=upward and normal.y>.7
	for point:Vector3 in mesh.surfaces[0][Mesh.ARRAY_VERTEX]:upward=upward and absf(point.z)<=2.0001
	check(upward and mesh.get_surface_count()==3,"paving only on walking top; three material surfaces")
	var after:Array=doc.records.duplicate(true)
	await call_tool("undo",{});check(doc._find("surface_bridge").is_empty(),"undo corrected bridge")
	await call_tool("redo",{});check(equivalent(doc.records,after),"redo preserves frozen appearance")
	await call_tool("save_world",{});var reopened=Doc.open_file(path)
	check(reopened!=null and equivalent(reopened.records,doc.records),"corrected bridge survives save reopen")
	editor.queue_free();await settle();print("BRIDGE_SURFACE_MCP failures=",failed);quit(1 if failed else 0)
