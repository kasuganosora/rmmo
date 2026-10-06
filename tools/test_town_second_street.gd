extends "res://tools/test_medieval_town_houses.gd"
const Author=preload("res://tools/extend_town_reference_street.gd")
func run()->void:
	create_timer(600).timeout.connect(func():quit(2));Engine.max_fps=60;root.size=Vector2i(1440,900)
	output_directory=Author.NEW_OUT
	var authored:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output_directory+"/result.json"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output_directory=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output_directory)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.world3d_map_path=Author.NEW_MAP;session.world3d_spawn=Vector3(-329,.9,0)
	var began:=Time.get_ticks_msec()
	if "--native" in OS.get_cmdline_user_args():
		var loader=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(Author.NEW_MAP)
		var loaded:Array=await loader.finished
		check(loaded[0]!=null,"native asynchronous map prepared")
		if loaded[0]==null:quit(1);return
		session.prepared_world3d=loaded[0];session.world3d_loading=true
	world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	check(world._navigation.ready_for_queries and not world._player.input_locked,"new street ready for normal movement")
	var entry_ms:=Time.get_ticks_msec()-began
	world._camera.yaw=0
	var keyboard_start:Vector3=world._player.position
	var key:=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true;Input.parse_input_event(key)
	for i in 90:await physics_frame
	key=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=false;Input.parse_input_event(key)
	var keyboard_distance:=absf(world._player.position.z-keyboard_start.z)
	# Walking is 1.6 m/s: 90 physics ticks cover 2.4 m, not the run speed.
	check(keyboard_distance>2.0 and world._player.position.y>.5,"keyboard movement remains grounded on residential road distance="+str(keyboard_distance))
	if "--keyboard-only" in OS.get_cmdline_user_args():
		FileAccess.open(output_directory+"/keyboard_result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"distance":keyboard_distance},"\t"))
		world.free();quit(1 if failures else 0);return
	var extras:Dictionary=Recipe.Doc.authoritative_extras(Author.NEW_MAP).extras
	var rows:Array=authored.houses;var sorted:Array=rows.duplicate();sorted.sort_custom(func(a,b):return a.station<b.station)
	var south:=B.vec(sorted.back().road_point);var north:=B.vec(sorted.front().road_point)
	var junction:=Vector3(-329,0,-54.6)
	await teleport(junction)
	for step in range(1,5):await walk(junction.lerp(south,step/4.0),"old avenue connects to new street "+str(step))
	for step in range(1,9):await walk(south.lerp(north,step/8.0),"walk new street section "+str(step))
	for step in range(1,9):await walk(north.lerp(south,step/8.0),"return new street section "+str(step))
	for row:Dictionary in rows:
		var instance:Dictionary=extras.building_instances[row.id];var plan:Dictionary=B.generate(instance.parameters)
		var basis:=Basis(Vector3.UP,deg_to_rad(row.yaw));var origin:=B.vec(row.position)
		var outside:Vector3=origin+basis*B.vec(plan.entrance);var inside:Vector3=outside+basis*Vector3(0,0,2.2)
		inside.y=origin.y+float(instance.parameters.base_height)
		await teleport(outside)
		check(Fixtures.set_runtime(world._map_root,row.id,"f0/north/entrance/door",1,0).ok,"open inherited inward entry "+row.id)
		for i in 3:await physics_frame
		await walk(inside,"enter new home "+row.id)
		var street:=B.vec(row.road_point);street.y=.025
		await walk(street,"exit new home to road "+row.id)
		Fixtures.set_runtime(world._map_root,row.id,"f0/north/entrance/door",0,0)
		var windows:Array=Fixtures.list_runtime(world._map_root,row.id).filter(func(f):return f.kind=="window")
		check(not windows.is_empty(),"independent windows retained "+row.window_style)
		var hidden:Dictionary={}
		for spec:Dictionary in world._map_root.get_meta("stream_library"):
			var b:Dictionary=spec.extras.get("building",{})
			if b.get("id")==row.id and (int(b.get("floor",0))>0 or b.get("role")=="roof"):hidden[spec.uuid]=true
		var cutaway:=preload("res://scripts/world3d/building_cutaway.gd").new();cutaway.map_root=world._map_root;cutaway.apply_hidden(hidden)
		var meshes:Dictionary=world._map_root.get_meta("stream_meshes")
		check(not hidden.is_empty() and hidden.keys().all(func(id):return meshes.has(id) and not meshes[id].visible),"upper floors and roof still hide separately "+row.id)
		cutaway.restore()
	var body:=CharacterBody3D.new();var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;shape.shape=capsule;body.add_child(shape);world.add_child(body)
	for lamp:Dictionary in authored.lamps:
		var at:=B.vec(lamp.position);var roadward:Vector3=(B.vec(lamp.road_edge)-at).normalized();var tangent:=Vector3(-roadward.z,0,roadward.x)
		var basis:=Basis(Vector3.UP,deg_to_rad(lamp.yaw))
		check(basis.z.dot(roadward)>.95,"flag emblem faces road "+lamp.id)
		Stream.sync(world._map_root,world,at);await physics_frame;await physics_frame
		var walk_pose:=Transform3D(Basis.IDENTITY,at+roadward+tangent*-3+Vector3.UP*1.03);body.global_transform=walk_pose
		check(not body.test_move(walk_pose,tangent*6),"pedestrian passage clear beside lamp "+lamp.id)
		var hit_pose:=Transform3D(Basis.IDENTITY,at+roadward+Vector3.UP*1.03)
		check(body.test_move(hit_pose,-roadward*1.3),"solid lamp post "+lamp.id);body.position=Vector3(0,-100,0)
		var envelope:=BoxShape3D.new();envelope.size=Vector3(1.40,4.05,.52)
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=envelope;query.transform=Transform3D(basis,at+basis*Vector3(-.4407,2.075,0))
		var excluded:Array[RID]=[body.get_rid(),world._player.get_rid()]
		for node in world.get_children():
			if node is StaticBody3D and str(node.get_meta("uuid","")).begins_with(lamp.id+"__"):excluded.append(node.get_rid())
		query.exclude=excluded
		check(world.get_world_3d().direct_space_state.intersect_shape(query,16).is_empty(),"lamp and banner avoid house projections "+lamp.id)
		for delta in [Vector3.ZERO,Vector3(.2,0,0),Vector3(-.2,0,0),Vector3(0,0,.2),Vector3(0,0,-.2)]:
			var ray:=PhysicsRayQueryParameters3D.create(at+delta+Vector3.UP*.15,at+delta-Vector3.UP*.1,1)
			check(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"lamp foot has physical ground "+lamp.id)
	body.free()
	await teleport(Vector3(-329,0,0));world._player.hide()
	world._request_environment({"time_hours":12.0,"time_speed":0.0});world._weather.streetlamps.refresh()
	check(world._weather.streetlamps.lights.all(func(l):return not l.visible),"all street lamps off in daylight")
	await capture("street_day",Vector3(-329,3,-43),Vector3(-329,3,50))
	await capture("district",Vector3(-382,110,-84),Vector3(-323,0,-1))
	world._request_environment({"time_hours":0.0,"time_speed":0.0});world._weather.streetlamps.refresh()
	var lit:Dictionary={}
	for row:Dictionary in world._weather.streetlamps.fixtures.values():
		var node=row.node.get_ref()
		if is_instance_valid(node) and row.lit and row.light.visible:lit[str(node.name).get_slice("__",0)]=true
	check(authored.lamps.all(func(l):return lit.has(l.id)),"all new street lamps illuminate simultaneously without visiting")
	check(lit.size()==33,"all 33 town street lamps illuminate together")
	await capture("street_night",Vector3(-329,3,-43),Vector3(-329,3,50))
	var f:=FileAccess.open(output_directory+"/runtime_result.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures":failures,"houses":rows.size(),"lamps":authored.lamps.size(),"entry_ms":entry_ms,"candidate_sha256":FileAccess.get_sha256(Author.NEW_MAP)},"\t"));f.close()
	print("SECOND_STREET_RUNTIME failures=",failures);world.free();quit(1 if failures else 0)
