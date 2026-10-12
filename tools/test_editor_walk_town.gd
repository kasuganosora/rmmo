extends "res://tools/test_editor_walk_mode.gd"
## Read the user's town, but keep this editor session and all outputs in test cache.
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"

func run() -> void:
	Engine.max_fps=60; root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	directory=Paths.cache_directory("editor_walk_town_%d"%Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(directory)
	var source_hash:=FileAccess.get_sha256(SOURCE)
	print("WALK_TOWN reading source")
	var doc=Doc.open_file(SOURCE)
	if doc==null:check(false,"town source opens");quit(1);return
	print("WALK_TOWN building editor records=",doc.records.size())
	var session=preload("res://scripts/net/net.gd").session(); session.world3d_editor_doc=doc; session.world3d_editor_path=directory.path_join("temporary.gltf")
	editor=preload("res://scripts/world_editor/world_editor.gd").new(); editor._mcp_autostart=false
	editor._draft_directory=directory.path_join("drafts"); root.add_child(editor); editor._safety.enabled=false
	await settle(); editor._ground_batches.flush(); await frames(15)
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK: port+=1
	probe.stop(); check(editor.start_mcp(port).ok,"town walking HTTP starts")
	var snapshot: Dictionary=doc.recovery_snapshot(); var history: int=doc._undo.size()
	var view: Node=editor._view; var collision_rebuilds: int=editor._fortification_collisions.rebuild_count
	var walk=editor._walk_mode
	for point in [Vector3(-35,0,-2.5),Vector3(261.7,0,125.9)]:
		var feet: Vector3=walk._ground(point,50.,60.)
		check(feet.is_finite(),"actual town has capsule clearance at "+str(point))
		if not feet.is_finite():continue
		await enter([feet.x,feet.y,feet.z])
		check(walk.body.is_on_floor(),"capsule stands on actual town surface")
		var start: Vector3=walk.body.position
		await call_tool("set_editor_walk_view",{"yaw":-90,"pitch":-15,"distance":5})
		await motion([0,1],1.)
		check(walk.active and walk.body.is_on_floor() and walk.body.position.distance_to(start)>1.,"capsule physically walks on town ground / bridge")
		print("WALK_TOWN route ",start," -> ",walk.body.position)
		await RenderingServer.frame_post_draw
		var image_path:=directory.path_join("bridge.png" if point.x>0 else "spawn_road.png")
		check(root.get_texture().get_image().save_png(image_path)==OK,"town third-person screenshot saved")
		print("WALK_TOWN preview ",image_path)
		await call_tool("set_editor_walk_mode",{"enabled":false})
	check(editor._view==view and editor._fortification_collisions.rebuild_count==collision_rebuilds,"walking never rebuilds the town or its collision batches")
	check(equivalent(snapshot,doc.recovery_snapshot()) and doc._undo.size()==history and not editor._dirty,"town authoring data and history remain unchanged")
	check(FileAccess.get_sha256(SOURCE)==source_hash,"formal town source remains unchanged")
	editor.queue_free(); await settle(); print("EDITOR_WALK_TOWN failures=",failed); quit(0 if failed==0 else 1)
