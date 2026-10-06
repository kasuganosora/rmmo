extends "res://tools/test_medieval_town_houses.gd"
const Author=preload("res://tools/arrange_bridge_terrain.gd")
const Bank=preload("res://scripts/world3d/rock_bank_mesh.gd")
func run()->void:
	create_timer(900).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900);output_directory=Author.OUT_BANK
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/result.json"))
	var baseline:bool="--baseline" in OS.get_cmdline_user_args()
	var formal:bool="--formal" in OS.get_cmdline_user_args()
	var map_path:String=Author.FORMAL if baseline or formal else Author.MAP_BANK
	if formal:
		output_directory=Author.OUT_BANK+"/formal"
		DirAccess.make_dir_recursive_absolute(output_directory)
	if baseline:report.bank_ids=report.bank_ids.filter(func(id):return not str(id).contains("west"))
	check(report.failures==0,"candidate authoring passed")
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession");session.world3d_map_path=map_path;session.world3d_spawn=Vector3(310,.9,164)
	var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(map_path)
	var loaded:Array=await loader.finished;check(loaded[0]!=null,"full native async map load")
	if loaded[0]==null:quit(1);return
	session.prepared_world3d=loaded[0];session.world3d_loading=true;world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	check(world._navigation.ready_for_queries,"navigation ready")
	if baseline or "--nav-only" in OS.get_cmdline_user_args():
		await teleport(Vector3(260,0,120))
		for i in 900:await physics_frame
		ResourceSaver.save(world._navigation.mesh,output_directory+"/navigation_probe.tres")
		print("NAV_PROBE ",world._navigation.fully_ready," ",NavigationServer3D.map_get_merge_rasterizer_cell_scale(world._navigation.map))
		print("BASELINE_NAVIGATION_READY ",world._navigation.ready_for_queries)
		world.free();quit(0);return
	for child in world.get_children():
		if child is CanvasLayer:child.hide()
	var extras:Dictionary=Author.Doc.authoritative_extras(map_path).extras;var bridge:Dictionary=extras.rmmo_records.filter(func(r):return r.uuid==report.bridge_id)[0]
	var pose:=Transform3D(Basis(Vector3.UP,deg_to_rad(bridge.rotation[1])),B.vec(bridge.position));var center:=pose.origin;var basis:=pose.basis
	await teleport(center+basis*Vector3(30,0,0));world._player.hide();world._request_environment({"time_hours":12.,"time_speed":0.})
	var batcher=world._map_root.get_node_or_null("GroundRenderBatches")
	for frame in 240:
		if batcher!=null and batcher.stats().pending_groups==0:break
		await process_frame
	for id in report.bank_ids:
		if not str(id).contains("west"):check(batcher!=null and batcher._member_groups.has(id),"full native runtime automatically batches "+id)
	await capture("runtime_bridge",center+basis*Vector3(0,6,19),center+basis*Vector3(34,0,0))
	if formal:await capture("runtime_bridge_close",center+basis*Vector3(16,3,13),center+basis*Vector3(18,.1,0))
	await capture("runtime_left_bank",center+basis*Vector3(8,2,-27),center+basis*Vector3(27,0,-20))
	await capture("runtime_right_bank",center+basis*Vector3(7,2,27),center+basis*Vector3(24,0,23))
	await teleport(center+basis*Vector3(-30,0,0))
	for frame in 240:
		if batcher!=null and batcher.stats().pending_groups==0:break
		await process_frame
	for id in report.bank_ids:
		if str(id).contains("west"):
			var node=world._map_root.get_meta("stream_meshes",{}).get(id)
			var eligible:bool=node!=null and batcher._residency_descriptors.has(node.get_instance_id())
			check(eligible and (batcher._member_groups.has(id) or node.mesh.get_surface_count()==2),"west bank has compatible batch or spatial singleton "+id)
	await capture("runtime_west_bank",center+basis*Vector3(-7,4,-24),center+basis*Vector3(-28,0,-19))
	await capture("runtime_overview",center+basis*Vector3(0,75,8),center)
	var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.height=2.1;capsule.radius=.3;shape.shape=capsule;body.add_child(shape);world.add_child(body);body.floor_snap_length=.3
	# The real player is hidden only for screenshots; exclude that stationary
	# test actor so the sweep checks terrain/bridge rather than another capsule.
	body.add_collision_exception_with(world._player)
	for lane in [-2.,0.,2.]:
		for direction in [-1,1]:
			var start:=pose*Vector3(-31*direction,1.08,lane);body.position=start;body.velocity=Vector3.ZERO;Stream.sync(world._map_root,world,start)
			for i in 4:await physics_frame
			for frame in 520:
				await physics_frame;body.velocity=basis.x*10*direction+Vector3.DOWN*2;body.move_and_slide()
				if (pose.affine_inverse()*body.position).x*direction>31:break
			var passed:bool=(pose.affine_inverse()*body.position).x*direction>31
			if not passed:
				print("BRIDGE_BLOCKED ",body.position)
				for i in body.get_slide_collision_count():print("COLLIDER ",body.get_slide_collision(i).get_collider())
			check(passed,"bridge lane "+str(lane)+" direction "+str(direction))
	body.free()
	for frame in 1200:
		if world._navigation.fully_ready:break
		await process_frame
	var bridge_route:Dictionary=world._navigation.find_path(pose*Vector3(-32,0,0),pose*Vector3(32,0,0),.5)
	check(bridge_route.ok,"bridge approach navigation route")
	for id in report.bank_ids:
		var record:Dictionary=extras.rmmo_records.filter(func(r):return r.uuid==id)[0];var rows:=Bank.sections(record);var origin:=B.vec(record.position)
		for fraction in [.25,.5,.75]:
			var row:Dictionary=rows[int((rows.size()-1)*fraction)];var at:Vector3=origin+row.outer.lerp(row.inner,.35)
			Stream.sync(world._map_root,world,at)
			for i in 4:await physics_frame
			var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*3,at+Vector3.DOWN*3))
			check(not hit.is_empty() and absf(hit.position.y-at.y)<.12,"native grass cap collision "+id)
			var face:Vector3=origin+row.outer+Vector3.DOWN*.55
			hit=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(face-row.normal*1.5,face+row.normal*2.))
			check(not hit.is_empty(),"native cliff face collision "+id)
			var water_face:Vector3=origin+row.outer;water_face.y=-1.4
			hit=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(water_face-row.normal*1.5,water_face+row.normal*2.))
			check(not hit.is_empty(),"continuous rock at waterline "+id)
	var file:=FileAccess.open(output_directory+("/formal_runtime_result.json" if formal else "/runtime_result.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"candidate_sha256":FileAccess.get_sha256(map_path),"map_path":map_path,"houses_changed":false,"scope":"full map async load, navigation, six bridge crossings, cap and cliff collision"},"  "));file.close()
	world.free();print("BRIDGE_TERRAIN_RUNTIME failures=",failures);quit(1 if failures else 0)
