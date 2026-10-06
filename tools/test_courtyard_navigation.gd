extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var p:Dictionary=Blueprint.medieval_presets().filter(func(v):return v.id=="courtyard")[0].parameters
	var plan:=Blueprint.generate(p);var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(70,.5,70))
	for r:Dictionary in plan.records:r.building.id="yard_test";doc.records.append(r)
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene)
	Stream.sync(scene,host,Vector3.ZERO);await physics()
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();nav.agent_height=2.1;host.add_child(nav)
	nav.build(scene.get_meta("stream_library"),Vector3(0,0,15))
	while not nav.fully_ready:await process_frame
	var edge:float=p.depth/2+p.annex_depth
	var a:=Vector3(0,0,edge+2);var b:=Vector3(0,p.base_height,edge-1)
	var body:=WalkBody.new();body.floor_snap_length=.2
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.1;shape.shape=capsule;shape.position.y=.15;body.add_child(shape);host.add_child(body)
	var authority:=preload("res://scripts/world3d/world_authority.gd").new()
	for backwards in [false,true]:
		var start:=b if backwards else a;var finish:=a if backwards else b
		var path:=NavigationServer3D.map_get_path(nav.map,start,finish,true)
		check(path.size()>1 and path[-1].distance_to(finish)<.25,"real navigation connects courtyard to street "+str(backwards))
		body.position=start+Vector3.UP*.905;body.velocity=Vector3.ZERO;authority.mount(body,nav,"yard_test")
		for tick in 300:
			await physics_frame
			var wish:=Vector3(finish.x-body.position.x,0,finish.z-body.position.z)
			if wish.length()<.15:break
			authority.move_intent(tick,wish.normalized(),2.5)
		check((body.position-Vector3.UP*.9-finish).length()<.25,"authoritative movement with real nav crosses steps "+str(backwards))
		authority.release()
	host.free();print("COURTYARD_NAV_FINISHED failures=",failed);quit(1 if failed else 0)
