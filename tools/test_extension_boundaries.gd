extends "res://tools/test_world3d_mcp.gd"
const T=preload("res://scripts/world3d/terrain_surface.gd")
var directory:String
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));rpc_timeout_ms=120000
	directory=Paths.cache_directory("extension_boundaries_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("map.gltf");var doc:=Doc.new();check(doc.save(path)==OK,"boundary fixture saved")
	var session=preload("res://scripts/net/net.gd").session();session.world3d_editor_path=path;session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await settle()
	while editor._load_job!=null and editor._load_job.active:await process_frame
	var probe:=TCPServer.new();port=30930
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"boundary real HTTP starts")
	var definitions:Array=(await rpc("tools/list")).result.tools
	check(definitions.any(func(t):return t.name=="list_terrain_rivers") and definitions.any(func(t):return t.name=="remove_terrain_river"),"river edit tools discovered")
	var a:=await call_tool("create_terrain",{"center":[0,0,0],"width":8.,"depth":8.,"cell_size":2.})
	var b:=await call_tool("create_terrain",{"center":[8,0,0],"width":8.,"depth":8.,"cell_size":1.})
	var before:Dictionary=editor._doc.recovery_snapshot()
	var brush:={"id":a.id,"mode":"raise","points":[[4,1]],"radius":3.,"strength":.3}
	await call_tool("sculpt_terrain",brush)
	for z in range(-4,5):
		check(absf(T.sample(editor._doc._find(a.id),Vector3(4,0,z))-T.sample(editor._doc._find(b.id),Vector3(-4,0,z)))<.0001,"mixed grid boundary continuous z="+str(z))
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"mixed grid exact undo")
	await call_tool("set_object_properties",{"ids":[b.id],"locked":true});var locked:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("sculpt_terrain",brush,false);check(equivalent(locked,editor._doc.recovery_snapshot()),"mixed locked neighbor atomic")
	await call_tool("undo")
	var ground:=await call_tool("create_terrain",{"center":[0,0,50],"width":32.,"depth":32.,"cell_size":1.})
	var river:={"id":"reroute","terrain_ids":[ground.id],"points":[[-12,45],[12,45]],"width":4.,"bank_width":2.,"water_level":-.5,"depth":1.5,"natural_materials":false}
	await call_tool("generate_terrain_river",river)
	await call_tool("sculpt_terrain",{"id":ground.id,"mode":"raise","points":[[12,62]],"radius":1.,"strength":.2})
	var untouched:float=T.sample(editor._doc._find(ground.id),Vector3(12,0,12))
	var old:Dictionary=editor._doc.recovery_snapshot();river.points=[[-12,55],[12,55]]
	await call_tool("preview_terrain_river",river);check(equivalent(old,editor._doc.recovery_snapshot()),"river reroute preview readonly")
	await call_tool("generate_terrain_river",river)
	check(absf(T.sample(editor._doc._find(ground.id),Vector3(0,0,-5)))<.001 and T.sample(editor._doc._find(ground.id),Vector3(0,0,5))< -1.,"old bed restored and new bed cut")
	check(T.sample(editor._doc._find(ground.id),Vector3(12,0,12))==untouched,"unrelated sculpt preserved")
	await call_tool("undo");check(equivalent(old,editor._doc.recovery_snapshot()),"reroute one exact undo");await call_tool("redo")
	await call_tool("save_world");await call_tool("open_world",{"path":path})
	check(equivalent((await call_tool("list_terrain_rivers")).rivers[0].points,river.points),"river layer survives reopen")
	await call_tool("remove_terrain_river",{"id":river.id})
	check(absf(T.sample(editor._doc._find(ground.id),Vector3(0,0,5)))<.001,"river removal restores terrain")
	await call_tool("undo")
	await call_tool("sculpt_terrain",{"id":ground.id,"mode":"raise","points":[[0,55]],"radius":1.,"strength":.1})
	old=editor._doc.recovery_snapshot();await call_tool("remove_terrain_river",{"id":river.id},false);check(equivalent(old,editor._doc.recovery_snapshot()),"owned river sample conflicts protected");await call_tool("undo")
	for i in 2:
		var x:float=100+i*150
		await call_tool("create_terrain",{"center":[x,0,0],"width":120.,"depth":100.,"cell_size":2.})
		var args:={"id":"ring_water_%d"%i,"shape":"ellipse","center_x":x,"radius_x":40. if i==0 else 50.,"radius_z":40. if i==0 else 30.,"style":"medieval_stone","height":8.,"thickness":3.5,"corner_towers":false,"wall_access":false,"arrow_slits":false,"gates":[{"id":"water","angle":0.,"kind":"water","width":16.,"height":5.,"open":1.,"grille":true}]}
		var p:=await call_tool("preview_fortification",args)
		if not p.get("ok",false):continue
		var plan:Dictionary=editor._fortifications.prepare(args)
		check(plan.records.filter(func(r):return r.has("water_gate")).size()==2,"ring water uses two actual arches")
		before=editor._doc.recovery_snapshot();await call_tool("generate_fortification",args)
		await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"ring water undo exact");await call_tool("redo")
		await call_tool("set_fortification_gate",{"id":args.id,"gate_id":"water","open":0.})
		check(editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")==args.id and r.has("fixture")).size()==4,"ring preserves four independent leaves")
	var hill:=await call_tool("create_terrain",{"center":[0,0,150],"width":64.,"depth":40.,"cell_size":1.})
	var fort:={"id":"following_towers","shape":"path","points":[[-20,150],[20,150]],"follow_terrain":true,"style":"medieval_stone","height":7.5,"thickness":3.5,"corner_towers":true,"tower_layout":"manual","wall_access":true,"arrow_slits":true,"gates":[]}
	await call_tool("generate_fortification",fort)
	await call_tool("set_fortification_terrain_follow",{"id":fort.id,"enabled":false})
	var disabled:Dictionary=editor._doc.recovery_snapshot()
	await call_tool("set_fortification_terrain_follow",{"id":fort.id,"enabled":true})
	await call_tool("undo");check(equivalent(disabled,editor._doc.recovery_snapshot()),"existing frozen follow toggle undo exact");await call_tool("redo")
	before=editor._doc.recovery_snapshot()
	var sculpt:={"id":hill.id,"mode":"raise","points":[[0,150]],"radius":32.,"hardness":1.,"strength":.2}
	var changed:=await call_tool("sculpt_terrain",sculpt)
	check(changed.get("changed_ids",[]).size()>1,"terrain sculpt updates frozen tower and wall components")
	var regions:Array=editor._fortifications.catalog().regions
	check(regions.all(func(r):return r.modified_or_missing.is_empty()),"follower manifest remains coherent")
	await call_tool("undo");check(equivalent(before,editor._doc.recovery_snapshot()),"frozen follow exact undo including recipe");await call_tool("redo")
	var part:Dictionary=editor._doc.records.filter(func(r):return r.get("fortification",{}).get("id")==fort.id)[0]
	await call_tool("set_object_properties",{"ids":[part.uuid],"locked":true});locked=editor._doc.recovery_snapshot()
	await call_tool("sculpt_terrain",sculpt,false);check(equivalent(locked,editor._doc.recovery_snapshot()),"locked tower cancels full terrain transaction");await call_tool("undo")
	await call_tool("save_world");var saved:Dictionary=editor._doc.recovery_snapshot();await call_tool("open_world",{"path":path})
	check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"all boundaries save reopen exact")
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1600,1000);root.content_scale_size=root.size;editor._grid.hide()
		for shot:Array in [["circle_water",[138,4,0],25,-12,90],["ellipse_water",[298,4,0],25,-12,90],["following_towers",[0,5,150],65,-24,25],["rerouted_river",[0,-.5,50],30,-40,20]]:
			await call_tool("set_editor_camera",{"projection":"perspective","center":shot[1],"distance":shot[2],"pitch":shot[3],"yaw":shot[4]});await settle();await RenderingServer.frame_post_draw
			editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(shot[0]+".png"))
	print("BOUNDARIES_ARTIFACTS ",directory);editor._mcp.stop();editor.queue_free();await settle()
	print("BOUNDARIES_FINISHED failures=",failed);quit(0 if failed==0 else 1)
