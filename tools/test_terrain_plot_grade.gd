extends "res://tools/test_world3d_roads.gd"
const Terrain=preload("res://scripts/world3d/terrain_surface.gd")
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	directory=Paths.cache_directory("terrain_plot_grade_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory);map_path=directory.path_join("map.gltf")
	var doc:=Doc.new();check(doc.save(map_path)==OK,"temporary map")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=map_path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=31960
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"3D HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.filter(func(t):return t.name=="sculpt_terrain")[0].inputSchema.properties.has("plot_grade"),"real HTTP discovers slope plane")
	var a:=await call_tool("create_terrain",{"center":[-8,0,0],"width":16,"depth":24,"cell_size":1})
	var b:=await call_tool("create_terrain",{"center":[8,0,0],"width":16,"depth":24,"cell_size":1})
	var args:={"id":a.id,"mode":"flatten","shape":"rectangle","points":[[0,0]],"plot_width":12,"plot_depth":8,"plot_yaw":90,"plot_grade":[.1,.05],"blend_margin":3,"target_height":2,"strength":1,"cross_tiles":true}
	var before:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("preview_terrain_stroke",args)
	check(equivalent(before,editor._doc.recovery_snapshot()),"slope preview has no document/history effect")
	await call_tool("sculpt_terrain",args)
	var left:Dictionary=editor._doc._find(a.id);var right:Dictionary=editor._doc._find(b.id)
	check(absf(Terrain.sample(left,Vector3(8,0,3))-1.7)<.00001 and absf(Terrain.sample(right,Vector3(-8,0,3))-1.7)<.00001,"rotated downhill plane has identical shared edge")
	check(absf(Terrain.sample(right,Vector3(-5,0,0))-2.15)<.00001,"local Z gradient rotates into world X")
	check(absf(Terrain.sample(right,Vector3(0,0,0)))<.00001,"outside blend margin stays untouched")
	var after:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"one undo restores both slopes")
	await call_tool("redo");check(equivalent(after,editor._doc.recovery_snapshot()),"one redo restores both slopes")
	await atomic_reject("sculpt_terrain",args.merged({"plot_grade":[.15,.15]},true))
	await atomic_reject("sculpt_terrain",args.merged({"plot_grade":[.2,0]},true))
	await atomic_reject("sculpt_terrain",args.merged({"plot_grade":[0]},true))
	await atomic_reject("sculpt_terrain",args.merged({"shape":"circle"},true))
	await atomic_reject("sculpt_terrain",args.merged({"mode":"raise"},true))
	await call_tool("set_object_properties",{"ids":[b.id],"locked":true})
	await atomic_reject("sculpt_terrain",args.merged({"target_height":3},true));await call_tool("undo")
	var fields=editor._terrain_panel.brush_fields
	check(fields.fields.has("plot_grade") and fields.fields.plot_grade.get_child_count()==2 and fields.fields.plot_grade.get_child(1).prefix=="Z","UI exposes local X/Z slope values")
	var source:Dictionary=right.duplicate(true);source.position=[8,5,0];source.rotation=[0,90,0];source.size=[16,2,24]
	var rotated:=Terrain.stroke(source,args.merged({"points":[[8,0]],"plot_yaw":0,"target_height":7},true))
	check(rotated.ok,"tilted target works on rotated vertically scaled terrain")
	if rotated.ok:
		var local:=Terrain.transform(rotated.record).affine_inverse()*Vector3(10,0,0)
		check(absf(Terrain.sample(rotated.record,local)+5-7.2)<.00001,"world plane height independent of terrain transform and Y scale")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":map_path})
	check(equivalent(saved,editor._doc.recovery_snapshot()),"native save reopen preserves actual slope heights")
	editor._mcp.stop();editor.queue_free();await settle();print("TERRAIN_PLOT_GRADE failures=",failed);quit(1 if failed else 0)
