extends SceneTree
const Author=preload("res://tools/place_town_streetlamps.gd")
const B=preload("res://scripts/world3d/building_blueprint.gd")
const Item=preload("res://scripts/world3d/day_night_review_item.gd")
const Lights=preload("res://scripts/world3d/streetlamp_lights.gd")
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label_:String)->void:
	print("PASS " if ok else "FAIL ",label_)
	if not ok:failures+=1
func brightness(picture:Image,pixel:Vector2)->float:
	var sum:=0.0
	for y in range(-3,4):
		for x in range(-3,4):
			var c:=picture.get_pixel(clampi(int(pixel.x)+x,0,picture.get_width()-1),clampi(int(pixel.y)+y,0,picture.get_height()-1))
			sum+=c.r*.2126+c.g*.7152+c.b*.0722
	return sum/49.0
func run()->void:
	create_timer(240).timeout.connect(func():quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var server=root.get_node("MockServer");var session=root.get_node("GameSession")
	Item.grant(server.inventory)
	session.spawn_data={"inventory":server.inventory.snapshot(),"gold":server.inventory.get_gold()}
	session.world3d_map_path=Author.TARGET;session.world3d_spawn=Vector3(-300,.9,-40)
	var world=load("res://scenes/world_3d.tscn").instantiate();root.add_child(world)
	while not world.is_world_ready():await process_frame
	# Keep manual inspection cameras fixed; world._process calls rig.follow directly.
	world.set_process(false);world.set_physics_process(false)
	world._player.set_physics_process(false);world._combat.set_physics_process(false);world._camera.set_process(false);world._camera.set_physics_process(false)
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Author.OUT+"/placement.json"))
	var runtime=world._weather.streetlamps
	check(runtime!=null,"one central streetlamp controller")
	world._hud._toggle_window("inventory");await process_frame
	var grid:Node=world._hud._windows.inventory.find_child("InvGrid",true,false);var slot:Control
	for cell in grid.get_children():
		if cell.item_id==Item.ID:slot=cell;break
	check(slot!=null,"review dial in actual town backpack");if slot==null:quit(1);return
	var input:=InputEventMouseButton.new();input.button_index=MOUSE_BUTTON_LEFT;input.pressed=true;input.double_click=true
	world._request_environment({"time_hours":12.0,"time_speed":0.0})
	slot._gui_input(input)
	check(world._night and world._weather.values.time_hours==0.0,"town double-click sets actual night")
	world._hud._toggle_window("inventory")
	# Regression: the observer stays at spawn. No walk/teleport may be needed to light the town.
	runtime.refresh()
	check(runtime.fixtures.size()==23 and runtime.lights.size()==23,"all 23 fixtures loaded at stationary spawn with their landscape: "+str(runtime.fixtures.size()))
	check(runtime.fixtures.values().all(func(r):return r.lit and r.glow.visible and r.light.visible),"stationary night toggle lights the entire district simultaneously")
	var starting_camera:Vector3=world._camera.camera.global_position
	var light_ids:Array=runtime.lights.map(func(l):return l.get_instance_id())
	world._camera.camera.global_position+=Vector3(200,0,200);runtime.refresh()
	check(runtime.lights.all(func(l):return l.visible) and runtime.lights.map(func(l):return l.get_instance_id())==light_ids,"camera distance neither switches nor reallocates lights")
	world._camera.camera.global_position=starting_camera
	# Inspect the street without changing player position or streaming origin.
	var street_camera:Camera3D=world._camera.camera
	street_camera.global_position=Vector3(-320,3,-51);street_camera.look_at(Vector3(-230,1,-29))
	world._player.hide();world._hud.hide();runtime.refresh()
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	var street_lit:=root.get_texture().get_image();street_lit.save_png(Author.OUT+"/street_all_night.png")
	runtime.set_process(false)
	for light in runtime.lights:light.hide()
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw
	var street_unlit:=root.get_texture().get_image();var distant_pavement:Array=[]
	for id in ["obj_4028","obj_4029","obj_4040"]:
		var lamp:Dictionary=report.lamps.filter(func(l):return l.id==id)[0]
		var post:=B.vec(lamp.position);var point:=post+(B.vec(lamp.road_edge)-post).normalized()*2+Vector3.UP*.02
		var pixel:=street_camera.unproject_position(point)
		var lit:=brightness(street_lit,pixel);var unlit:=brightness(street_unlit,pixel)
		check(not street_camera.is_position_behind(point) and Rect2(Vector2.ZERO,root.size).has_point(pixel),"distant road sample visible "+id)
		check(lit>unlit+.025,"unvisited distant road illuminated "+id+" "+str(lit)+" vs "+str(unlit))
		distant_pavement.append({"id":id,"camera_distance":street_camera.global_position.distance_to(point),"lit":lit,"unlit":unlit})
	runtime.set_process(true);runtime.refresh();world._hud.show()
	var seen:Dictionary={};var center:Vector3
	for lamp:Dictionary in report.lamps:
		var at:=B.vec(lamp.position);var edge:=B.vec(lamp.road_edge);var forward:Vector3=(edge-at).normalized()
		check(Basis(Vector3.UP,deg_to_rad(lamp.yaw)).z.dot(forward)>.95,"emblem faces road "+lamp.id)
		world._player.global_position=at+forward*2+Vector3.UP*.9
		var camera:Camera3D=world._camera.camera;camera.global_position=at+forward*5+Vector3.UP*2.8;camera.look_at(at+Vector3.UP*2.5)
		Stream.sync(world._map_root,world,at);await physics_frame;await process_frame;runtime.refresh()
		var found:=false
		for row:Dictionary in runtime.fixtures.values():
			var node=row.node.get_ref()
			if is_instance_valid(node) and str(node.name).begins_with(lamp.id+"__"):
				found=true
				if row.lit and row.glow.visible:seen[lamp.id]=true
				check(row.lit and row.glow.visible and node.get_active_material(0).emission_enabled,"night crystal + halo "+lamp.id)
				center=node.global_transform*node.get_aabb().get_center()
				check(runtime.lights.any(func(l):return l.visible and l.global_position.distance_to(center)<.01),"nearby blue illumination "+lamp.id)
		check(found,"streamed lamp discovered "+lamp.id)
		check(runtime.lights.size()==runtime.fixtures.size() and runtime.lights.all(func(l):return l.visible and not l.shadow_enabled),"one persistent non-shadow light per loaded lamp")
	check(seen.size()==23,"all 23 deployed lamps emit at night")
	# Review the street from its road-facing side, never a detached lamp-only scene.
	var first:Dictionary=report.lamps[1];var at:=B.vec(first.position);var forward:Vector3=(B.vec(first.road_edge)-at).normalized()
	world._player.global_position=at+forward*2+Vector3.UP*.9
	var camera:Camera3D=world._camera.camera;camera.global_position=at+forward*8+Vector3.UP*3.6;camera.look_at(at+Vector3.UP*1.5)
	world._player.hide();world._hud.hide()
	Stream.sync(world._map_root,world,at);runtime.refresh()
	var material_count:=Lights.night_materials.size()
	for i in 6:runtime.refresh()
	check(Lights.night_materials.size()==material_count,"steady night reuses emission materials")
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	var lit_image:=root.get_texture().get_image();lit_image.save_png(Author.OUT+"/town_night_fixed.png")
	runtime.set_process(false)
	for light in runtime.lights:light.hide()
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw
	var unlit_image:=root.get_texture().get_image();var pavement:Array=[]
	for meters in [2.0,3.0]:
		var pixel:=camera.unproject_position(at+forward*meters+Vector3.UP*.02)
		var lit:=brightness(lit_image,pixel);var unlit:=brightness(unlit_image,pixel)
		pavement.append({"distance_from_post":meters,"lit":lit,"unlit":unlit})
		check(lit>unlit+.025 and lit>.12,"actual road surface illuminated at "+str(meters)+"m: "+str(lit)+" vs "+str(unlit))
	runtime.set_process(true);runtime.refresh();world._hud.show()
	world._hud._toggle_window("inventory");await process_frame
	grid=world._hud._windows.inventory.find_child("InvGrid",true,false)
	for cell in grid.get_children():
		if cell.item_id==Item.ID:slot=cell;break
	slot._gui_input(input);runtime.refresh();world._hud._toggle_window("inventory")
	check(not world._night and runtime.lights.all(func(l):return not l.visible) and runtime.fixtures.values().all(func(r):return not r.lit and not r.glow.visible),"dial switches every loaded lamp and halo off in daytime")
	world._hud.hide()
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(Author.OUT+"/town_day_facing_fixed.png")
	world._request_environment({"time_hours":0.0});runtime.refresh()
	for row:Dictionary in runtime.fixtures.values():
		var node=row.node.get_ref()
		if not is_instance_valid(node):continue
		node.hide();runtime.refresh();check(not row.lit and not row.glow.visible,"hidden source turns off emission and halo");node.show();break
	Stream.sync(world._map_root,world,Vector3(5000,1,5000));await process_frame;runtime.refresh()
	check(runtime.lights.is_empty() and runtime.fixtures.is_empty(),"unloaded district releases all lights")
	Stream.sync(world._map_root,world,at);await process_frame;runtime.refresh()
	check(runtime.lights.size()==23 and runtime.lights.all(func(l):return l.visible),"stream reentry restores all night lighting")
	check(server.inventory.get_qty(Item.ID)==1,"review dial preserved")
	var f:=FileAccess.open(Author.OUT+"/night.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"lamps":seen.size(),"candidate":FileAccess.get_sha256(Author.TARGET),"actual_world_and_inventory":true,"pavement":pavement,"distant_pavement":distant_pavement,"stationary_all_lamps":true},"\t"));f.close()
	print("TOWN_NIGHT failures=",failures);world.free();quit(1 if failures else 0)
