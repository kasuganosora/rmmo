extends "res://tools/test_world3d_fortification_access.gd"
func run() -> void:
	create_timer(600).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("wall_spacing_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory); map_path=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("grass",Vector3(0,-.25,0),Vector3(180,.5,180)); check(doc.save(map_path)==OK,"temporary layout map")
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30480
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"layout HTTP starts")
	var defs: Array=(await rpc("tools/list")).result.tools; var schema: Dictionary=defs.filter(func(d):return d.name=="generate_fortification")[0].inputSchema
	check(defs.size()==118 and ["tower_layout","tower_spacing","floor_material_id"].all(func(k):return schema.properties.has(k)) and not schema.properties.has("layout_version"),"118 tools expose public layout modes and floor material")
	var ring:={"id":"ring","shape":"ellipse","radius_x":40,"radius_z":40,"wall_access":false,"arrow_slits":false}
	var auto:=await call_tool("preview_fortification",ring)
	check(auto.get("tower_count",0)==4 and auto.settings.tower_layout=="automatic" and auto.layout_zones.size()==4,"automatic 40m ring uses four spaced towers")
	await atomic_reject("generate_fortification",ring.merged({"tower_count":8},true))
	var dense:=await call_tool("preview_fortification",ring.merged({"tower_count":8,"tower_layout":"manual"},true))
	check(dense.get("tower_count",0)==8 and dense.layout_zones.is_empty(),"manual ring allows eight towers without automatic zones")
	await atomic_reject("generate_fortification",{"id":"bad","points":[[-20,0],[20,0]]})
	await atomic_reject("generate_fortification",{"id":"bad","points":[[-30,0],[30,0]],"gates":[{"id":"near","segment":0,"t":.22,"width":5,"height":5,"open":1}]})
	await atomic_reject("generate_fortification",{"id":"bad","points":[[-30,0],[30,0]],"tower_layout":"unknown"})
	var args:={"id":"manual","points":[[-20,0],[20,0]],"tower_layout":"manual"}
	var preview:=await call_tool("preview_fortification",args)
	await call_tool("generate_fortification",args)
	var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("undo"); await call_tool("redo"); check(equivalent(saved,editor._doc.recovery_snapshot()),"manual layout and paved foundations share undo transaction")
	var floors: Array=editor._doc.records.filter(func(r):return r.get("fortification",{}).get("part","").contains("_ground_floor"))
	check(not floors.is_empty() and floors.all(func(r):return r.has("surface_paint") and r.surface_paint[0].material.has("normal_path")),"tower floor uses actual default PBR stone with normal")
	await atomic_reject("generate_fortification",{"id":"nearby","points":[[-20,30],[40,30]]})
	check((await call_tool("preview_fortification",{"id":"nearby","points":[[-20,30],[40,30]],"tower_layout":"manual"})).ok,"manual placement bypasses neighboring tower exclusion only")
	await atomic_reject("generate_fortification",{"id":"manual","floor_material_id":"missing"})
	var panel=editor._city.panel.fortification_panel; panel.current=editor._fortifications.regions()[0].settings.duplicate(true); panel.form()
	check(panel.request().tower_layout=="manual" and panel.request().floor_material_id.contains("sandstone_floor") and not panel.request().has("layout_version"),"UI restores mode and paving material from shared recipe")
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-20,1,0],"distance":19,"pitch":-22,"yaw":180}); editor._grid.hide(); await shot("city_side_stone_floor.png")
	var hidden: Array=[]
	for r in editor._doc.records:
		if r.get("fortification",{}).get("part","").begins_with("access_tower_0_") and not r.fortification.part.contains("_ground_floor") and r.fortification.role not in ["tower_stair","door","hinge","hinge_mount"]:
			var n=editor._view.get_node_or_null(NodePath(r.uuid))
			if n!=null: n.hide(); hidden.append(n)
	await call_tool("set_editor_camera",{"projection":"perspective","center":[-20,1,0],"distance":22,"pitch":-35,"yaw":25}); await shot("stone_floor_cutaway.png")
	for n in hidden: n.show()
	await call_tool("save_world"); saved=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records) and equivalent(saved.map_meta,editor._doc.map_meta),"mode, floor, foundation and material survive save/reopen")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished; check(loaded[0]!=null,"paved tower runtime loads")
	if loaded[0]!=null: await paved_runtime(loaded[0],preview.access_routes[0])
	print("SPACING_ARTIFACTS "+directory); print("SPACING_HTTP_FINISHED failures=",failed); quit(0 if failed==0 else 1)
func paved_runtime(scene: Node3D,route: Dictionary) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); Stream.sync(scene,host,Data.vec(route.room)); await physics()
	var space:=host.get_world_3d().direct_space_state
	for offset in [Vector3.ZERO,Vector3(1,0,0),Vector3(-1,0,0)]:
		var p: Vector3=Data.vec(route.room)+offset; var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP))
		check(not hit.is_empty() and absf(hit.position.y-.03)<.001,"interior has solid stone collision above grass")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Data.vec(route.entry)+Vector3.UP*5.02,Data.vec(route.room)+Vector3.UP*5.02)).is_empty(),"5m headroom retained above raised paving")
	var body:=CharacterBody3D.new(); var collision:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1; collision.shape=capsule; body.add_child(collision); host.add_child(body); body.floor_snap_length=.25
	body.position=Data.vec(route.entry)+Vector3.UP*1.06
	for target in [Data.vec(route.room),Data.vec(route.entry)]:
		for i in 300:
			var delta:=Vector3(target.x-body.position.x,0,target.z-body.position.z)
			if delta.length()<.15: break
			await physics_frame; body.velocity=delta.normalized()*3+Vector3.DOWN*2; body.move_and_slide()
		check(Vector2(body.position.x-target.x,body.position.z-target.z).length()<.3,"capsule crosses paved doorway threshold both ways")
	host.free()
