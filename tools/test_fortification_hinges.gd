extends "res://tools/test_world3d_roads.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")
func run() -> void:
	create_timer(240).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("wall_hinges_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); var floor_id:=doc.add_box("grass",Vector3(0,-.25,0),Vector3(120,.5,120)); doc._find(floor_id).color=[.32,.4,.25]; check(doc.save(map_path)==OK,"temporary hinge map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30320
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"hinge HTTP starts")
	await call_tool("generate_fortification",{"id":"hinge","tower_layout":"manual","points":[[-15,0],[15,0]],"gates":[{"id":"entry","segment":0,"t":.5,"width":6,"height":5,"open":0}]})
	var records: Array=editor._doc.records.filter(func(r):return r.has("fortification")); var sleeves: Array=records.filter(func(r):return r.fortification.role=="hinge"); var mounts: Array=records.filter(func(r):return r.fortification.role=="hinge_mount")
	check(sleeves.size()==2 and mounts.size()==2,"three modeled hinges per leaf merged into sleeve and mount meshes")
	for sleeve in sleeves:
		var door: Dictionary=records.filter(func(r):return r.fortification.role=="door" and sleeve.fortification.part==r.fortification.part+"_hinge")[0]
		var pivot: Vector3=Fixtures.transform(door)*Fixtures.vec(door.fixture.pivot)
		for amount in [0,.35,1]:
			var a: Dictionary=door.duplicate(true); var b: Dictionary=sleeve.duplicate(true); a.fixture.open=amount; b.fixture.open=amount
			check((Fixtures.transform(a)*Fixtures.vec(a.fixture.pivot)).distance_to(pivot)<.00001 and Fixtures.transform(b).origin.distance_to(pivot)<.00001,"visible hinge and door share fixed rotation axis at %s"%amount)
	await call_tool("set_fortification_gate",{"id":"hinge","gate_id":"entry","open":.6}); await call_tool("undo"); await call_tool("redo")
	check(mounts.all(func(r):return not r.has("fixture") and equivalent(r,editor._doc._find(r.uuid))),"wall-mounted pintles stay fixed during open / undo / redo")
	var ring:=await call_tool("preview_fortification",{"id":"ring_hinges","shape":"ellipse","radius_x":40,"radius_z":40,"gates":[{"id":"entry","angle":270,"width":6,"height":5,"open":1}]})
	check(ring.get("ok",false),"curved gate uses the same modeled hinge planner through HTTP")
	await call_tool("set_environment",{"preset":"day","ambient_energy":.65})
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-3,2.7,-1.37],"distance":3.2,"pitch":-5,"yaw":-25}); editor._grid.hide(); await shot("hinge_close.png")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,0],"distance":20,"pitch":-12,"yaw":15}); await shot("gate.png")
	await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records),"hinge axes and stationary mounts survive save / reopen")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished; check(loaded[0]!=null,"hinge runtime loads")
	if loaded[0]!=null:
		var scene: Node3D=loaded[0]; var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Vector3(0,0,0)); await physics()
		check(Fixtures.list_runtime(scene,"fortification:hinge")[0].members.size()==4,"runtime gate includes both leaves and both sleeve groups")
		for amount in [0,1]:
			check(Fixtures.set_runtime(scene,"fortification:hinge","entry",amount,0).ok,"runtime drives modeled hinges")
			await physics()
			if amount==1:
				for x in [-2.8,0.,2.8]: check(host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,4.99,-4),Vector3(x,4.99,4))).is_empty(),"hardware preserves 5m opening at x=%s"%x)
		host.free()
	if is_instance_valid(loader): loader.queue_free()
	print("HINGE_ARTIFACTS "+directory); print("HINGES_FINISHED failures=",failed); quit(0 if failed==0 else 1)
func shot(name_: String) -> void:
	await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(name_))
