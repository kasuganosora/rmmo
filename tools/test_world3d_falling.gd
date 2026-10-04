extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	for height in [.45,4.0,12.0]:
		var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(20,.5,20))
		doc.add_box("block",Vector3(0,height/2,0),Vector3(4,height,4))
		var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene);Stream.sync(scene,host,Vector3.ZERO);await physics()
		var nav:=preload("res://scripts/world3d/world_navigation.gd").new();host.add_child(nav);nav.build(scene.get_meta("stream_library"),Vector3.ZERO)
		while not nav.fully_ready:await process_frame
		var body:=WalkBody.new();body.floor_snap_length=.2
		var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.8;shape.shape=capsule;body.add_child(shape);host.add_child(body)
		var authority:=preload("res://scripts/world3d/world_authority.gd").new()
		for jumping in [false,true]:
			body.position=Vector3(1,height+.905,0);body.velocity=Vector3.ZERO;authority.mount(body,nav,"fall_test")
			for tick in 10:await physics_frame;authority.move_intent(tick,Vector3.ZERO,0)
			var lowest_velocity:=0.0;var peak:=body.position.y
			for tick in range(10,190):
				await physics_frame
				authority.move_intent(tick,Vector3.RIGHT if body.position.x<6 else Vector3.ZERO,2.5,jumping and tick==10)
				lowest_velocity=minf(lowest_velocity,body.velocity.y);peak=maxf(peak,body.position.y)
			check(body.position.x>5.8 and absf(body.position.y-.9)<.04,"internal ledge descent height="+str(height)+" jump="+str(jumping)+" final="+str(body.position))
			check(lowest_velocity<-.5,"descent uses gravity, not teleportation")
			if jumping:check(peak>height+.9+.8,"ground jump has upward arc")
			authority.release()
		body.position=Vector3(8,.905,0);body.velocity=Vector3.ZERO;authority.mount(body,nav,"fall_test")
		for tick in 120:await physics_frame;authority.move_intent(tick,Vector3.RIGHT,4,tick==10)
		check(body.position.x<10 and body.position.y>.85,"map edge remains protected while walking/jumping")
		authority.release();host.free();await physics()
	print("WORLD_FALLING_FINISHED failures=",failed);quit(1 if failed else 0)
