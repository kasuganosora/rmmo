extends "res://tools/test_world3d_fortification_access.gd"
## Reuse saved HTTP-generated records; isolate doors to test real runtime collision.
func run() -> void:
	create_timer(180).timeout.connect(func():quit(2))
	if OS.get_cmdline_user_args().is_empty(): push_error("Pass the directory containing circle.gltf and ellipse.gltf from the access HTTP test"); quit(2); return
	for shape in ["circle","ellipse"]:
		var path: String=OS.get_cmdline_user_args()[0].path_join(shape+".gltf")
		var meta: Dictionary=Doc.authoritative_extras(path).get("extras",{})
		check(not meta.is_empty(),"read previously saved HTTP map "+shape)
		if meta.is_empty(): continue
		meta.rmmo_records=meta.rmmo_records.filter(func(r):return not r.has("fortification") or r.get("fixture",{}).get("id","")=="tower_entrance_0" or r.get("fortification",{}).get("part","").begins_with("access_tower_0_door_"))
		var plan:=preload("res://scripts/world3d/fortification_plan.gd").new().build({"id":"access","style":"medieval_stone","wall_access":true,"arrow_slits":true,"height":7.5,"thickness":3.5,"shape":"ellipse","radius_x":40,"radius_z":30 if shape=="ellipse" else 40})
		var route: Dictionary=plan.access_routes[0]
		var loader:=preload("res://scripts/world3d/map_loader.gd").new(); root.add_child(loader)
		loader._record_meta=meta; loader._building=true
		loader.call_deferred("_build_records"); var loaded: Array=await loader.finished
		var scene: Node3D=loaded[0]; var host:=Node3D.new(); root.add_child(host); host.add_child(scene)
		Stream.sync(scene,host,Data.vec(route.entry)); await physics()
		var fixtures=preload("res://scripts/world3d/building_fixtures.gd")
		var direction: Vector3=(Data.vec(route.room)-Data.vec(route.entry)).normalized(); var across:=Vector3(-direction.z,0,direction.x)
		var body:=CharacterBody3D.new(); var collision:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.3; capsule.height=2.1; collision.shape=capsule; body.add_child(collision); host.add_child(body)
		for amount in [0,1]:
			check(fixtures.set_runtime(scene,"fortification:access",route.door_id,amount,0).ok,"set runtime tower door "+shape+" "+str(amount)); await physics()
			for side in [-.5,.5]:
				var hit:=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Data.vec(route.entry)+Vector3.UP*2+across*side,Data.vec(route.room)+Vector3.UP*2+across*side))
				check(hit.is_empty()==(amount==1),"actual leaf collision follows door state "+shape)
			body.position=Data.vec(route.entry)+Vector3.UP*1.06; body.velocity=Vector3.ZERO
			for i in 150:
				await physics_frame; body.velocity=direction*3+Vector3.DOWN*2; body.move_and_slide()
			var traveled: float=(body.position-Data.vec(route.entry)).dot(direction)
			check(traveled<1.8 if amount==0 else traveled>5,"2.1m capsule blocked closed / passes open "+shape+" "+str(amount)); print("DOOR_TRAVEL ",shape," open=",amount," meters=",traveled)
		host.free()
	print("TOWER_DOORS_FINISHED failures=",failed); quit(0 if failed==0 else 1)
