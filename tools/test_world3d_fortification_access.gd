extends "res://tools/test_world3d_roads.gd"
const Data=preload("res://scripts/world3d/city_layout.gd")
class WalkBody extends CharacterBody3D:
	var surface_id:="ground"
	func _sense_surface() -> void: pass
func run() -> void:
	create_timer(1100).timeout.connect(func():quit(2)); root.size=Vector2i(1440,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("wall_access_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	for shape in (OS.get_cmdline_user_args() if not OS.get_cmdline_user_args().is_empty() else ["path","circle","ellipse"]): await sample(shape)
	print("ACCESS_ARTIFACTS "+directory); print("ACCESS_FINISHED failures=",failed); quit(0 if failed==0 else 1)
func sample(shape: String) -> void:
	map_path=directory.path_join(shape+".gltf"); var doc:=Doc.new(); var ground:=doc.add_box("grass",Vector3(0,-.25,0),Vector3(120,.5,120)); doc._find(ground).color=[.32,.4,.25]; check(doc.save(map_path)==OK,"temporary access map "+shape)
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_path=map_path; session.world3d_editor_doc=null
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false; editor._draft_directory=directory.path_join("drafts_"+shape); root.add_child(editor); await settle()
	var probe:=TCPServer.new(); port=30380
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"access HTTP starts")
	var defs: Array=(await rpc("tools/list")).result.tools; var schema: Dictionary=defs.filter(func(d):return d.name=="generate_fortification")[0].inputSchema
	check(schema.properties.has("wall_access") and schema.properties.has("arrow_slits") and schema.properties.has("interior_side") and schema.properties.has("tower_door_open"),"HTTP discovers internal stairs, arrow ports and tower doors")
	var args:={"id":"access","tower_layout":"manual","points":[[-20,0],[20,0]],"shape":"path" if shape=="path" else "ellipse","radius_x":40,"radius_z":30 if shape=="ellipse" else 40}
	if shape=="closed": args.merge({"shape":"path","closed":true,"points":[[-25,-25],[25,-25],[25,25],[-25,25]]},true)
	var preview:=await call_tool("preview_fortification",args)
	if not preview.get("ok",false): editor._mcp.stop(); editor.queue_free(); await settle(); return
	check(preview.settings.wall_access and preview.settings.arrow_slits and preview.access_routes[0].stair_width>=2.6,"new walls include stairs, tower entry and real arrow ports")
	await atomic_reject("generate_fortification",args.merged({"thickness":2.5}))
	await atomic_reject("generate_fortification",args.merged({"height":5.0}))
	await atomic_reject("generate_fortification",args.merged({"tower_door_open":1.1}))
	var route: Dictionary=preview.access_routes[0]; var obstacle: String=editor._doc.add_box("block",Data.vec(route.stairs_bottom)+Vector3(0,1,0),Vector3(2,2,2)); editor._rebuild()
	await atomic_reject("generate_fortification",args); editor._doc.records=editor._doc.records.filter(func(r):return r.uuid!=obstacle); editor._rebuild()
	await call_tool("generate_fortification",args); var generated: Dictionary=editor._doc.recovery_snapshot(); await call_tool("undo"); await call_tool("redo"); check(equivalent(generated,editor._doc.recovery_snapshot()),"access is one undoable operation")
	await call_tool("generate_fortification",{"id":"access","tower_door_open":0}); await call_tool("generate_fortification",{"id":"access","tower_door_open":1})
	var records: Array=editor._doc.records.duplicate(true)
	var tower:=Data.vec(route.deck); var inside: Vector3=Data.vec(route.entry)-Data.vec(route.room); inside.y=0; inside=inside.normalized(); var view_yaw:=wrapf(rad_to_deg(atan2(inside.x,inside.z))+30,-180,180)
	await call_tool("set_editor_camera",{"projection":"perspective","center":[tower.x+inside.x*5,4,tower.z+inside.z*5],"distance":32,"pitch":-30,"yaw":view_yaw}); editor._grid.hide(); await shot(shape+"_stairs.png")
	var hidden: Array=[]
	for r in records:
		if r.get("fortification",{}).get("part","").begins_with("access_tower_0_") and r.fortification.role not in ["tower_stair","door","hinge","hinge_mount"]:
			var node: Node3D=editor._view.get_node_or_null(NodePath(r.uuid))
			if node!=null: node.hide(); hidden.append(node)
	await call_tool("set_editor_camera",{"projection":"perspective","center":[tower.x,3.6,tower.z],"distance":22,"pitch":-28,"yaw":view_yaw}); await shot(shape+"_internal_cutaway.png")
	for node in hidden: node.show()
	await call_tool("set_editor_camera",{"projection":"perspective","center":[0,3,0],"distance":120 if shape!="path" else 65,"pitch":-45,"yaw":25}); await shot(shape+"_overview.png")
	await call_tool("save_world"); var saved: Dictionary=editor._doc.recovery_snapshot(); await call_tool("open_world",{"path":map_path}); check(equivalent(saved.records,editor._doc.records),"access geometry and configuration survive save/reopen")
	editor._mcp.stop(); editor.queue_free(); await settle()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(map_path); var loaded: Array=await loader.finished; check(loaded[0]!=null,"access runtime loads "+shape)
	if loaded[0]!=null: await runtime_access(loaded[0],preview.access_routes,records,shape)
	if is_instance_valid(loader): loader.queue_free()
func shot(name_: String) -> void:
	await settle(); await RenderingServer.frame_post_draw; editor._camera.get_viewport().get_texture().get_image().save_png(directory.path_join(name_))
func runtime_access(scene: Node3D,routes: Array,records: Array,label_: String) -> void:
	var host:=Node3D.new(); root.add_child(host); host.add_child(scene); var route: Dictionary=routes[0]; Stream.sync(scene,host,Data.vec(route.deck)); await physics()
	var space:=host.get_world_3d().direct_space_state
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Data.vec(route.entry)+Vector3.UP*3.5,Data.vec(route.room)+Vector3.UP*3.5)).is_empty(),"city-side 5m tower entrance is truly hollow "+label_)
	var fixtures=preload("res://scripts/world3d/building_fixtures.gd")
	check(fixtures.set_runtime(scene,"fortification:access",route.door_id,0,0).ok,"runtime closes tower door with its hinges "+label_); await physics()
	var toward: Vector3=(Data.vec(route.room)-Data.vec(route.entry)).normalized(); var across:=Vector3(-toward.z,0,toward.x)
	for side in [-.5,.5]:
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Data.vec(route.entry)+Vector3.UP*2+across*side,Data.vec(route.room)+Vector3.UP*2+across*side)).is_empty(),"closed tower leaf blocks entry ray "+label_)
	check(fixtures.set_runtime(scene,"fortification:access",route.door_id,1,0).ok,"runtime reopens tower door "+label_); await physics()
	for raw in route.arrow_ports:
		var c:=Data.vec(raw); var n: Vector3=c-Data.vec(route.room); n.y=0; n=n.normalized(); var tangent:=Vector3(-n.z,0,n.x)
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(c-n*.8,c+n*.8)).is_empty(),"projectile ray traverses tower outward arrow port "+label_)
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(c+tangent*.5-n*.8,c+tangent*.5+n*.8)).is_empty(),"stone beside tower port blocks projectiles "+label_)
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); nav.agent_height=2.1; host.add_child(nav); nav.build(scene.get_meta("stream_library")); var deadline:=Time.get_ticks_msec()+45000
	while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(nav.fully_ready,"2.1m agent navmesh completes "+label_)
	if nav.fully_ready:
		check(nav.find_path(Data.vec(route.entry),Data.vec(route.room)).ok,"navigation enters tower room "+label_)
		check(nav.find_path(Data.vec(route.stairs_bottom)+Vector3(0,0,.1),Data.vec(route.deck)).ok,"navigation reaches tower deck by stairs "+label_)
		check(nav.find_path(Data.vec(route.deck),Data.vec(routes[1].deck)).ok,"wall walk connects neighboring tower decks "+label_)
	var body:=WalkBody.new(); var collision:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1; collision.shape=capsule; collision.position.y=.15; body.add_child(collision); body.floor_snap_length=.25; host.add_child(body)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	body.position=Data.vec(route.entry)+Vector3.UP*.905; authority.mount(body,nav,"fortification-access")
	await follow_path(body,authority,nav,Data.vec(route.deck),label_+" enter and climb internal stair")
	check(body.position.distance_to(Data.vec(route.deck)+Vector3.UP*.9)<.4,"capsule reaches walkable tower roof "+label_)
	await follow_path(body,authority,nav,Data.vec(routes[1].deck),label_+" traverse curtain and second roof")
	await follow_path(body,authority,nav,Data.vec(route.deck),label_+" return across both roof connections")
	await follow_path(body,authority,nav,Data.vec(route.entry),label_+" descend and exit city-side door")
	check(absf(body.position.y-.9)<.3,"capsule descends back to city ground "+label_)
	authority.release(); host.free()
func walk_to(body: CharacterBody3D,authority: RefCounted,target: Vector3,limit: int) -> void:
	for i in limit:
		var delta:=Vector3(target.x-body.position.x,0,target.z-body.position.z)
		if delta.length()<.15: break
		await physics_frame; authority.move_intent(Engine.get_physics_frames(),delta.normalized(),3.0)

func follow_path(body: CharacterBody3D,authority: RefCounted,nav: Node,target: Vector3,label_: String) -> void:
	var path: Dictionary=nav.find_path(body.position-Vector3.UP*.9,target)
	check(path.ok,"route "+label_)
	if not path.ok: return
	for waypoint in path.path:
		await walk_to(body,authority,waypoint,600)
		if Vector2(body.position.x-waypoint.x,body.position.z-waypoint.z).length()>.4:
			check(false,"physical traversal "+label_); print("STUCK ",body.position," waypoint ",waypoint); return
	check(body.position.distance_to(target+Vector3.UP*.9)<.4,"physical traversal "+label_)
