extends SceneTree
const Item=preload("res://scripts/world3d/day_night_review_item.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")
const OUT="D:/code/rmmo_runtime/review_artifacts/day_night_review_item"
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func run()->void:
	create_timer(150).timeout.connect(func():quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	var server=root.get_node("MockServer");var session=root.get_node("GameSession")
	check(server.item_catalog.has_item(Item.ID) and not server.item_catalog.get_item(Item.ID).consumable,"registered reusable review item")
	check(server.inventory.get_qty(Item.ID)==1,"starter bag includes one review dial")
	Item.grant(server.inventory);Item.grant(server.inventory)
	check(server.inventory.get_qty(Item.ID)==1,"grant is idempotent")
	var full=preload("res://scripts/net/combat/inventory.gd").new();full.max_slots=0
	check(not Item.grant(full) and full.slot_count()==0,"full bag does not overwrite other items or exceed capacity")
	check(not server._inventory_module_logic.try_use_item(Item.ID).ok,"unsupported 2D path cannot consume review item")
	server.login("day_night_review_test","test","local");await server.login_finished
	server.create_character("昼夜验收","warrior","1","male",{})
	var created:Array=await server.character_created;check(created[0],"temporary test character created")
	var character:Dictionary=created[2]
	server.enter_world3d(character.id);var entered:Array=await server.enter_world_ready;check(entered[0],"real character enter flow")
	server.inventory.consume(Item.ID,1);var gold:int=server.inventory.get_gold()
	server.enter_world3d(character.id);await server.enter_world_ready
	check(server.inventory.get_qty(Item.ID)==1 and server.inventory.get_gold()==gold,"restored character receives missing dial without resetting bag")
	server.enter_world3d(character.id);await server.enter_world_ready
	check(server.inventory.get_qty(Item.ID)==1,"reenter does not duplicate dial")
	session.selected_character=character
	session.spawn_data={"inventory":server.inventory.snapshot(),"gold":server.inventory.get_gold()}
	var directory:=preload("res://scripts/world3d/map_paths.gd").cache_directory("review_dial_%d"%Time.get_ticks_usec())
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.1,0),Vector3(40,.2,40))
	doc.add_box("stone_wall",Vector3(0,1.5,-3),Vector3(10,3,.3))
	doc.map_meta.environment=Settings.updated({}, {"time_hours":12.0,"time_speed":0.0,"weather_transition":0.0})
	doc.map_meta.lamps=[0,2.5,0]
	var path:=directory.path_join("map.gltf")
	check(doc.save(path)==OK,"temporary map saved")
	if failures:quit(1);return
	var initial_hash:=FileAccess.get_sha256(path)
	session.world3d_map_path=path;session.world3d_spawn=Vector3(0,.9,5)
	var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	world._player.set_physics_process(false);world._combat.set_physics_process(false)
	var map_id:String=world._map_ref()
	server.sky_authority.ensure_map("review/other",Settings.defaults())
	var other:Dictionary=server.sky_authority.maps["review/other"].duplicate(true)
	var env_before:Dictionary=server.sky_authority.maps[map_id].environment.duplicate(true)
	world._hud._toggle_window("inventory");await process_frame
	var grid:Node=world._hud._windows.inventory.find_child("InvGrid",true,false)
	check(grid!=null,"real backpack grid displayed")
	var slot:Control=null
	if grid!=null:
		for cell in grid.get_children():
			if cell.item_id==Item.ID:slot=cell;break
	check(slot!=null,"review item is visible in the actual backpack")
	if slot==null:quit(1);return
	var input:=InputEventMouseButton.new();input.button_index=MOUSE_BUTTON_LEFT;input.pressed=true
	slot._gui_input(input)
	check(server.sky_authority.maps[map_id].environment.time_hours==12.0,"single click only selects")
	input.double_click=true;slot._gui_input(input)
	check(server.sky_authority.maps[map_id].environment.time_hours==0.0 and world._night and world._weather.values.preset=="night","double click reaches real HUD/world/server clock and night presentation")
	check(world._lamps.size()==1 and world._lamps[0].light_energy>0,"existing runtime night lamps respond")
	for frame in 10:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT+"/night.png")
	slot._gui_input(input)
	check(server.sky_authority.maps[map_id].environment.time_hours==12.0 and not world._night and world._lamps[0].light_energy==0,"second double click restores day and turns night lamps off")
	for frame in 10:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT+"/day.png")
	check(server.inventory.get_qty(Item.ID)==1,"uses never consume item")
	check(server.sky_authority.maps["review/other"]==other,"other map clock untouched")
	for key in ["weather","weather_intensity","wind_speed","wind_direction","weather_transition"]:
		check(server.sky_authority.maps[map_id].environment[key]==env_before[key],"preserve "+key)
	world._request_environment({"time_hours":22.0,"time_speed":120.0})
	world._night=false
	check(server.try_use_item(Item.ID).ok and server.sky_authority.maps[map_id].environment.time_hours==12.0 and server.sky_authority.maps[map_id].environment.time_speed==0,"server use reads actual running clock and freezes review hour")
	world._transfer_pending=true
	check(not server.try_use_item(Item.ID).ok and server.sky_authority.maps[map_id].environment.time_hours==12.0,"map transfer rejects without toggling")
	world._transfer_pending=false
	check(not Item.use(server,"review/missing",Callable(world,"_request_environment")).ok,"missing map rejects without changing active map")
	check(not Item.use(server,map_id,func(_changes):return {"ok":false,"error":"test rejection"}).ok and server.inventory.get_qty(Item.ID)==1,"failed environment request does not consume item")
	server.inventory.consume(Item.ID,1)
	check(not server.try_use_item(Item.ID).ok and server.sky_authority.maps[map_id].environment.time_hours==12.0,"cannot toggle without owning the item")
	check(FileAccess.get_sha256(path)==initial_hash and Doc.open_file(path).map_meta.environment.time_hours==12.0,"review never writes authored map environment")
	var file:=FileAccess.open(OUT+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"item":Item.ID,"real_hud_double_click":true,"runtime_clock":true,"map_unchanged":FileAccess.get_sha256(path)==initial_hash},"\t"));file.close()
	print("DAY_NIGHT_ITEM failures=",failures);world.free();quit(1 if failures else 0)
