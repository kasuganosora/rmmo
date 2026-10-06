extends "res://tools/test_world3d_buildings.gd"
var MAP="D:/code/rmmo_runtime/maps/medieval_house_showcase/map.gltf"
var OUT="D:/code/rmmo_runtime/review_artifacts/house_playground/runtime.json"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):MAP=arg.trim_prefix("--map=")
		if arg.begins_with("--report="):OUT=arg.trim_prefix("--report=")
	create_timer(900).timeout.connect(func():quit(2)); Engine.max_fps=60
	var original_hash:=FileAccess.get_sha256(MAP)
	var raw:=Doc.authoritative_extras(MAP); check(raw.has("extras"),"saved showcase records readable")
	if not raw.has("extras"): quit(1); return
	var fixtures: Array=[]
	for id in raw.extras.building_instances:
		var value: Dictionary=raw.extras.building_instances[id]
		var plan:=Blueprint.generate(value.parameters)
		check(plan.ok and value.parameters.floor_height==4,"current 4 m recipe valid: "+id)
		fixtures.append({"id":id,"plan":plan,"origin":Blueprint.vec(value.position)})
	check(fixtures.size()==7,"all seven basic houses in playable map")
	var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader); loader.start(MAP); var loaded: Array=await loader.finished
	check(loaded[0]!=null,"native runtime loader opens showcase")
	if loaded[0]==null: quit(1); return
	var host:=Node3D.new(); root.add_child(host); var scene: Node3D=loaded[0]; host.add_child(scene)
	Stream.sync(scene,host,Vector3(0,0,-53)); await physics()
	var space:=host.get_world_3d().direct_space_state
	var ground:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,2,-53),Vector3(0,-2,-53)))
	check(not ground.is_empty() and absf(ground.position.y)<.02,"spawn has level support")
	var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1
	var query:=PhysicsShapeQueryParameters3D.new(); query.shape=capsule; query.transform=Transform3D(Basis.IDENTITY,Vector3(0,1.06,-53))
	check(space.intersect_shape(query).is_empty(),"spawn has full character clearance")
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new(); host.add_child(nav); nav.build(scene.get_meta("stream_library"))
	var deadline:=Time.get_ticks_msec()+120000
	while not nav.fully_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(nav.fully_ready,"showcase navigation bake completes")
	var checked_rooms:=0; var stairs_checked:=0
	var body:=WalkBody.new(); body.floor_snap_length=.2
	var shape:=CollisionShape3D.new(); shape.shape=capsule; shape.position.y=.15; body.add_child(shape); host.add_child(body)
	var walk_nav:=WalkNavigation.new(); host.add_child(walk_nav)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	for fixture in fixtures:
		Stream.sync(scene,host,fixture.origin); await physics()
		if nav.fully_ready:
			for room in fixture.plan.rooms:
				var route: Dictionary=nav.find_path(fixture.origin+Blueprint.vec(fixture.plan.entrance),fixture.origin+Blueprint.vec(room.center))
				check(route.ok,"entry reaches "+fixture.id+" / "+str(room.id)); checked_rooms+=1
		for stair in fixture.plan.stairs:
			for reverse in [false,true]:
				var route:Array=stair.get("waypoints",[stair.bottom,stair.top]).duplicate(true)
				if reverse:route.reverse()
				body.position=fixture.origin+Blueprint.vec(route[0])+Vector3(0,.905,0); body.velocity=Vector3.ZERO; authority.mount(body,walk_nav,"gallery-check")
				for point in route.slice(1):
					var target:Vector3=fixture.origin+Blueprint.vec(point)
					for tick in 450:
						var flat:=Vector3(target.x-body.position.x,0,target.z-body.position.z)
						if flat.length()<.17 and absf(body.position.y-.9-target.y)<.15: break
						await physics_frame; authority.move_intent(tick,flat.normalized(),2.5)
					check(Vector2(body.position.x-target.x,body.position.z-target.z).length()<.3 and absf(body.position.y-.9-target.y)<.2,"2.1 m capsule "+("descends " if reverse else "climbs ")+fixture.id+" stair "+str(stair.floor)+" target="+str(point)+" actual="+str(body.position-fixture.origin))
					authority.release();authority.mount(body,walk_nav,"gallery-check")
				authority.release(); stairs_checked+=1

	host.free()
	check(FileAccess.get_sha256(MAP)==original_hash,"verification preserves showcase map")
	var file:=FileAccess.open(OUT,FileAccess.WRITE); file.store_string(JSON.stringify({"failures":failed,"map_sha256":original_hash,"houses":fixtures.size(),"rooms_checked":checked_rooms,"stair_directions_checked":stairs_checked},"\t")); file.close()
	print("HOUSE_PLAYGROUND_RUNTIME_FINISHED failures=",failed); quit(1 if failed else 0)
