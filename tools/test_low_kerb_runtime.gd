extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/bridge_road_edges_20261007/plan.json"))
	var doc:=Doc.new()
	doc.records=p.records.filter(func(r):return r.uuid=="town_road_10_5_0")
	doc.add_box("ground",Vector3(328,-.25,168),Vector3(40,.5,40))
	var ramp:=doc.add_box("block",Vector3(340,2,180),Vector3(4,.2,4));doc._find(ramp).rotation=[50,0,0]
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene);Stream.sync(scene,host,Vector3(322,0,168));await physics()
	var nav:=WalkNavigation.new();host.add_child(nav)
	var body:=WalkBody.new();body.floor_snap_length=.2
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;shape.shape=capsule;body.add_child(shape);host.add_child(body)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	var start:=Vector3(322.376342773438,.925,168.216384887695);var end:=Vector3(324.549835,.925,165.958771)
	for speed in [1.6,4.]:
		for reverse in [false,true]:
			body.position=end if reverse else start;body.velocity=Vector3.ZERO;authority.mount(body,nav,"low_kerb")
			for tick in 10:await physics_frame;authority.move_intent(tick,Vector3.ZERO,0)
			var target:Vector3=start if reverse else end
			for tick in range(10,190):
				await physics_frame
				var delta:=target-body.position;delta.y=0
				if delta.length()<.15:break
				authority.move_intent(tick,delta.normalized(),speed)
			var distance:=Vector2(body.position.x-target.x,body.position.z-target.z).length()
			check(distance<.2,"actual curved kerb speed=%s reverse=%s distance=%s"%[speed,reverse,distance])
			if distance>=.2:
				var foot:=body.position-Vector3.UP*.9;var direction:Vector3=(target-body.position).normalized();direction.y=0;direction=direction.normalized()
				for length in [.24,.32,.32+speed/60.,.4]:
					var at:Vector3=foot+direction*length;var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*.4,at-Vector3.UP);query.exclude=[body.get_rid()]
					var hit:=body.get_world_3d().direct_space_state.intersect_ray(query)
					print("LOW_KERB_HIT ",length," ",hit.get("position")," ",hit.get("normal"))
			authority.release()
	body.position=Vector3(340,2.9,180)
	check(authority._landing_below(body,Vector3(340,2.4,180),Vector3.FORWARD).is_empty(),"continuous steep slope is still rejected")
	check(authority._landing_below(body,Vector3(1000,0,1000),Vector3.RIGHT).is_empty(),"empty space has no false landing support")
	host.free();print("LOW_KERB_RUNTIME failures=",failed);quit(failed)
