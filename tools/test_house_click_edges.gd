extends "res://tools/test_world3d_buildings.gd"
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var plan:=Blueprint.generate(Blueprint.medieval_presets()[0].parameters)
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.25,0),Vector3(60,.5,60))
	for r:Dictionary in plan.records:r.building.id="click_test";doc.records.append(r)
	var host:=Node3D.new();root.add_child(host);var scene:=doc.build();host.add_child(scene);Stream.sync(scene,host,Vector3.ZERO);await physics()
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();nav.agent_height=2.1;host.add_child(nav);nav.build(scene.get_meta("stream_library"))
	while not nav.fully_ready:await process_frame
	var player:=preload("res://scripts/world3d/world_player.gd").new();var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model);host.add_child(player);player.set_physics_process(false);player.navigation=nav
	for floor_ in 2:
		var room:Dictionary=plan.rooms.filter(func(r):return r.floor==floor_)[0]
		var middle:=Blueprint.vec(room.center)+Vector3.UP*.018
		player.position=middle+Vector3.UP*.9
		var edge:=Vector3(room.bounds[0]+.15,middle.y,middle.z)
		check(not nav.find_path(middle,edge).ok,"strict nav reproduces visible floor edge rejection")
		player.set_click_target(edge,"ground")
		check(player.click_target is Vector3,"floor edge click starts route on storey "+str(floor_))
		var last:Vector3=player._route[-1] if not player._route.is_empty() else player.click_target
		check(absf(last.y-middle.y)<.4 and Vector2(last.x-edge.x,last.z-edge.z).length()<.65,"edge target stays on same storey")
		player.set_click_target(middle+Vector3(1,0,0),"block")
		check(player.click_target is Vector3,"solid component metadata does not reject walkable top")
		player.set_click_target(middle+Vector3(0,2,0),"block")
		check(player.click_target==null,"wall/ceiling height without nav remains unreachable")
	host.free();print("HOUSE_CLICK_EDGES_FINISHED failures=",failed);quit(1 if failed else 0)
