extends "res://tools/test_world3d_roads.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
func run()->void:
	create_timer(300).timeout.connect(func():quit(2))
	directory=Paths.cache_directory("house_plot_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	await settle()
	var probe:=TCPServer.new();port=31760
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	var schema:Dictionary=definitions.filter(func(t):return t.name=="sculpt_terrain")[0].inputSchema
	check(schema.properties.has("plot_width") and schema.properties.has("shape"),"real HTTP discovers rectangular plot parameters")
	var a:=await call_tool("create_terrain",{"center":[-8,0,0],"width":16,"depth":24,"cell_size":1})
	var b:=await call_tool("create_terrain",{"center":[8,0,0],"width":16,"depth":24,"cell_size":1})
	var args:={"id":a.id,"mode":"flatten","shape":"rectangle","points":[[0,0]],"plot_width":10,"plot_depth":6,"plot_yaw":0,"blend_margin":4,"target_height":2,"strength":1,"cross_tiles":true}
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("preview_terrain_stroke",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"plot preview leaves document and history untouched")
	await call_tool("sculpt_terrain",args)
	var left:Dictionary=editor._doc._find(a.id);var right:Dictionary=editor._doc._find(b.id)
	check(absf(Terrain.sample(left,Vector3(8,0,0))-2)<.00001 and absf(Terrain.sample(right,Vector3(-8,0,0))-2)<.00001,"rectangular plateau crosses shared seam")
	check(absf(Terrain.sample(right,Vector3(-1,0,0))-1)<.00001,"soft edge halfway equals smoothstep half")
	check(absf(Terrain.sample(right,Vector3(1,0,0)))<.00001,"ground outside margin unchanged")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"single undo restores both tiles")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"redo restores full plot")
	await atomic_reject("sculpt_terrain",args.merged({"mode":"raise"},true))
	await atomic_reject("sculpt_terrain",args.merged({"strength":2},true))
	await atomic_reject("sculpt_terrain",args.merged({"points":[[0,0],[1,1]]},true))
	await atomic_reject("sculpt_terrain",args.merged({"plot_depth":0},true))
	await call_tool("set_object_properties",{"ids":[b.id],"locked":true});await atomic_reject("sculpt_terrain",args.merged({"target_height":1},true));await call_tool("undo")
	var rotated:Dictionary=args.merged({"plot_yaw":90},true)
	check(Terrain.plot_weight(Vector2(0,4),Vector2.ZERO,rotated)==1. and Terrain.plot_weight(Vector2(4,0),Vector2.ZERO,rotated)<1.,"plot yaw matches native building basis")
	var fields=editor._terrain_panel.brush_fields
	check(fields.fields.has("shape") and fields.fields.has("blend_margin"),"terrain UI uses the same schema")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":map_path})
	check(equivalent(saved,editor._doc.recovery_snapshot()),"native save reopen retains plot heights")
	var f:=FileAccess.open("D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014/plot_tool_test.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failed,"map_path":map_path,"http_port":port}));f.close()
	editor._mcp.stop();editor.queue_free();await settle();print("HOUSE_PLOT_TEST failures=",failed);quit(1 if failed else 0)
