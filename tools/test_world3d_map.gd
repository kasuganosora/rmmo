extends SceneTree
var failed:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failed+=1
func run()->void:
	root.size=Vector2i(1280,900)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	doc.map_meta["map_name"]="地图与雷达验收"
	doc.add_box("ground",Vector3(0,-.1,0),Vector3(40,.2,40))
	doc.add_box("block",Vector3(-7,1,-6),Vector3(4,2,5),Vector3(0,30,0))
	doc.add_box("ground",Vector3(110,-.1,0),Vector3(10,.2,10))
	doc.add_npc(Vector3(6,.8,-4),"guide","")
	var dir=preload("res://scripts/world3d/map_paths.gd").cache_directory("map_ui_review")
	check(doc.save(dir.path_join("map.gltf"))==OK,"fixture saved")
	var session=root.get_node("GameSession")
	session.world3d_map_path=dir.path_join("map.gltf");session.world3d_spawn=Vector3(0,.9,4)
	var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	world._player.set_physics_process(false)
	check(world._hud.get_node("MinimapPanel").visible,"radar is visible in real world HUD")
	check(world._map_data.shapes.size()==3 and world._map_data.bounds.end.x>=115,"unloaded distant geometry remains in overview")
	check(world._map_data.markers.size()==1,"NPC POI projected from document")
	check(world._hud._radar.center==Vector2(0,4),"radar centers on the player immediately")
	world._hud._toggle_window("map")
	await process_frame;await process_frame
	var map=world._hud._map_overview
	check(map.has_method("bind_world") and map.world==world,"normal map window uses three-dimensional provider")
	map.center=Vector2.ZERO;map.span=46
	var point:=Vector2(-8.25,6.75)
	check(map.to_world(map.to_screen(point)).distance_to(point)<.001,"negative and fractional metre coordinates round-trip")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=map.size*.5
	var before:float=map.span;map._input_map(wheel)
	check(map.span<before,"scroll wheel zooms overview")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true;click.position=map.to_screen(point)
	map._input_map(click)
	check(world._map_data.pins.size()==1 and world._map_data.pins[0].distance_to(point)<.01,"right-click places a shared precise pin")
	for p in [Vector2(1,1),Vector2(4,4),Vector2(8,8)]:world.toggle_world_map_pin(p)
	check(world._map_data.pins.size()==3,"personal markers capped at three")
	world._hud._on_clear_map_pins()
	check(world._map_data.pins.is_empty(),"existing clear button clears 3D pins")
	world.toggle_world_map_pin(Vector2(-8,6))
	check(world.request_world_map_move(Vector2(4,4)),"map click routes through real navigation")
	check(not world.request_world_map_move(Vector2(5000,5000)),"out-of-map navigation rejected")
	var saved=world._map_path;world._map_path="other";world._refresh_world_map()
	check(world._map_data.pins.is_empty(),"map transition isolates pins")
	world._map_path=saved;world._refresh_world_map()
	check(world._map_data.pins.size()==1,"returning map restores session pins")
	map.center=Vector2.ZERO;map.span=46
	await create_timer(.25).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("world3d_map_ui.png"))
	world.free();await process_frame
	print("test_world3d_map: "+("PASS" if failed==0 else "FAIL"));quit(failed)
