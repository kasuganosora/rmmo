extends "res://tools/test_world3d_buildings.gd"
const Fixtures=preload("res://scripts/world3d/building_fixtures.gd")

func run() -> void:
	create_timer(600).timeout.connect(func():push_error("Fixture integration timeout");quit(2))
	var directory:=Paths.cache_directory("fixture_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]); var path:=directory.path_join("map.gltf")
	var doc:=Doc.new(); doc.add_box("ground",Vector3(0,-.3,0),Vector3(45,.6,45))
	check(doc.save(path)==OK,"create temporary door fixture map")
	Net.session().world3d_editor_path=path; Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); await physics(); editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"start real HTTP MCP")
	var discovery:=await rpc("tools/list"); var names: Array=discovery.result.tools.map(func(t):return t.name)
	check(names.size()==118 and names.has("set_building_component_state") and names.has("list_building_components") and not names.has("paint_tile"),"discover 118 current 3D tools including articulated components")
	var recipes:=await call_tool("list_building_templates")
	check(recipes.presets.size()==7 and recipes.parameters_schema.properties.has("foundation_depth") and recipes.parameters_schema.properties.has("dormers"),"discover foundations and varied architectural recipes")
	for preset in Blueprint.medieval_presets()+Blueprint.urban_presets():
		var plan:=Blueprint.generate(preset.parameters)
		check(plan.ok and plan.records.size()<=Blueprint.MAX_PARTS,"recipe valid and within schema part limit: "+preset.id)
		if not plan.ok: continue
		for slab in plan.records.filter(func(r):return r.building.floor==0 and r.building.role=="floor"):
			var foot: Array=plan.records.filter(func(r):return r.building.part==slab.building.part+"/foundation")
			if slab.position[1]-slab.size[1]/2>slab.building.floor_y+.05:
				check(foot.is_empty(),"elevated landing has no floating foundation");continue
			check(foot.size()==1 and is_equal_approx(foot[0].position[1]+foot[0].size[1]/2,slab.position[1]-slab.size[1]/2) and foot[0].position[1]-foot[0].size[1]/2<=-float(plan.parameters.get("foundation_depth",1.0)),"foundation joins raised slab and reaches required depth below terrain")
		for record in plan.records:
			if not record.has("fixture"):continue
			check(Fixtures.valid(record),"generated hinge metadata valid")
			var closed:=Transform3D(Basis.from_euler(Blueprint.vec(record.rotation)*PI/180),Blueprint.vec(record.position))
			var pivot:=Blueprint.vec(record.fixture.pivot)
			check((Fixtures.pose(closed,record.fixture,.5)*pivot).distance_to(closed*pivot)<.00001,"hinge remains fixed at half-open")
	var p: Dictionary=Blueprint.medieval_presets()[0].parameters.merged({"roof_axis":"width","dormers":2},true)
	var plan:=Blueprint.generate(p)
	var made:=await call_tool("generate_buildings",{"parameters":p,"placements":[{"position":[0,0,0]}]})
	if not made.get("ok",false): quit(1); return
	var id: String=made.building_ids[0]
	# Supporting terrain is the only overlap exception: buried props stay protected.
	var obstacle: String=doc.add_box("block",Vector3(18,-.65,0),Vector3(1,.4,1))
	var blocked_before:=doc.recovery_snapshot()
	await call_tool("generate_buildings",{"parameters":p,"placements":[{"position":[18,0,0]}]},false)
	check(doc.recovery_snapshot()==blocked_before,"foundation cannot overlap a buried existing prop")
	doc.remove(obstacle)
	var listing:=await call_tool("list_building_components",{"id":id})
	var door: Dictionary=listing.components.filter(func(c):return c.id=="f0/north/entrance/door")[0]
	var window: Dictionary=listing.components.filter(func(c):return c.kind=="window" and c.id.begins_with("f0/"))[0]
	var shutter: Dictionary=listing.components.filter(func(c):return c.kind=="shutter")[0]
	var before:=doc.recovery_snapshot(); var history: int=doc._undo.size()
	for args in [{"id":id,"component_id":door.id,"open":1.1},{"id":id,"component_id":"missing","open":0},{"id":"missing","component_id":door.id,"open":0}]: await call_tool("set_building_component_state",args,false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid state and missing IDs fail without side effects")
	doc._find(door.members[0]).editor_locked=true; before=doc.recovery_snapshot()
	await call_tool("set_building_component_state",{"id":id,"component_id":door.id,"open":0},false)
	check(doc.recovery_snapshot()==before,"locked member blocks complete door operation atomically")
	doc._find(door.members[0]).erase("editor_locked")
	await call_tool("set_building_component_state",{"id":id,"component_id":door.id,"open":0})
	check(door.members.all(func(uuid):return doc._find(uuid).fixture.open==0),"HTTP closes all leaf, rail and handle members together")
	await call_tool("undo"); check(doc._find(door.members[0]).fixture.open==1,"undo restores open door")
	await call_tool("redo"); check(doc._find(door.members[0]).fixture.open==0,"redo restores closed door")
	await call_tool("set_building_component_state",{"id":id,"component_id":window.id,"open":.4})
	await call_tool("set_building_component_state",{"id":id,"component_id":shutter.id,"open":0})
	check(editor._buildings.conflicts(id).is_empty(),"opening a window is not a manual geometry conflict")
	editor._building_panel.refresh_list(id)
	check(editor._building_panel.fixtures.rows.size()==listing.components.size(),"UI discovers same program-controlled components")
	# A rigid transform transports closed frames and local hinges as one house.
	await call_tool("update_building",{"id":id,"yaw":35})
	check(is_equal_approx(doc._find(window.members[0]).fixture.open,.4) and editor._buildings.conflicts(id).is_empty(),"whole-house rotation preserves open state and ownership")
	await call_tool("undo")
	await call_tool("save_world"); await call_tool("open_world",{"path":path}); doc=editor._doc
	check(doc._find(door.members[0]).fixture.open==0 and is_equal_approx(doc._find(window.members[0]).fixture.open,.4),"door/window state survives save and reopen")
	var baked: Dictionary=doc._find(window.members[0]).duplicate(true)
	var open_pose:=Fixtures.transform(baked); Fixtures.bake_snapshot(baked)
	check(not baked.has("fixture") and Fixtures.transform(baked).is_equal_approx(open_pose),"ordinary snapshot preserves current open pose without a dangling controller")
	var frame: Transform3D=Fixtures.transform(doc._find(window.members[0]))
	editor._sync_record_transform(doc._find(window.members[0]))
	check(editor._view.get_node(NodePath(window.members[0])).transform.is_equal_approx(frame),"unpainted editor transform refresh preserves window articulation")
	editor.free(); Net.session().world3d_editor_doc=null; Net.session().world3d_editor_path=""; await physics()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(path)
	var loaded: Array=await loader.finished
	check(loaded[0]!=null,"runtime loads authoritative articulated records")
	if loaded[0]!=null:
		var scene: Node3D=loaded[0]; var host:=Node3D.new(); root.add_child(host); host.add_child(scene)
		Stream.sync(scene,host,Vector3.ZERO); await physics()
		var opening: Dictionary=plan.openings.filter(func(o):return o.id=="entrance" and o.wall=="f0/north")[0]
		var center:=Vector3(opening.u,1.1,opening.fixed); var space:=host.get_world_3d().direct_space_state
		var ray:=PhysicsRayQueryParameters3D.create(center+Vector3(0,0,-.45),center+Vector3(0,0,.45))
		check(not space.intersect_ray(ray).is_empty(),"closed door has real blocking collision")
		var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); host.add_child(nav); nav.build(scene.get_meta("stream_library"))
		var deadline:=Time.get_ticks_msec()+40000
		while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
		check(nav.fully_ready,"fixture navigation builds")
		if nav.fully_ready: check(not nav.find_path(Blueprint.vec(plan.entrance),Blueprint.vec(plan.rooms[0].center)).ok,"navigation refuses path through closed door")
		check(Fixtures.set_runtime(scene,id,door.id,1,.25).ok,"runtime API starts hinged animation")
		await create_timer(.1).timeout
		var spec: Dictionary=scene.get_meta("stream_by_id")[door.members[0]]
		check(spec.extras.fixture.open>0 and spec.extras.fixture.open<1,"door actually animates through intermediate angles")
		await create_timer(.3).timeout; await physics()
		check(space.intersect_ray(ray).is_empty(),"open door collision rotates clear of opening")
		check(scene.get_meta("stream_bodies")[door.members[0]].global_transform.is_equal_approx(scene.get_meta("stream_meshes")[door.members[0]].global_transform),"visible leaf and physical body agree")
		if nav.fully_ready: check(nav.find_path(Blueprint.vec(plan.entrance),Blueprint.vec(plan.rooms[0].center)).ok,"opening door restores navigation without town rebake")
		for component in Fixtures.list_runtime(scene,id):
			if component.kind!="door": Fixtures.set_runtime(scene,id,component.id,1,0)
		await physics()
		for o in plan.openings:
			if not o.wall.contains("dormer"):continue
			var c:=Vector3(o.u+.25,o.floor_y+o.bottom+o.height/2,o.fixed)
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(c+Vector3(0,0,-.5),c+Vector3(0,0,1.3)))
			check(hit.is_empty(),"open dormer looks into a real cut roof cavity")
		Stream.sync(scene,host,Vector3(500,0,500)); await physics(); Stream.sync(scene,host,Vector3.ZERO); await physics()
		check(space.intersect_ray(ray).is_empty() and spec.extras.fixture.open==1,"animated state and collision survive chunk unload/reload")
		var pose: Transform3D=spec.transform
		check(not Fixtures.set_runtime(scene,id,door.id,NAN,0).ok and spec.transform==pose,"invalid runtime state is atomic")
		host.free()
	print("test_world3d_building_fixtures: ","PASS" if failed==0 else "FAIL", " fixture=",directory)
	quit(0 if failed==0 else 1)
