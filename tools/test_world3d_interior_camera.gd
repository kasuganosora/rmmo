extends "res://tools/test_world3d_buildings.gd"
const CameraRig=preload("res://scripts/world3d/third_person_camera.gd")
const Settings=preload("res://scripts/world3d/environment_settings.gd")

func run()->void:
	# Wall-clock timeout is supplied by run_godot_background.py. Fixed-FPS test
	# simulation can advance many seconds while an asynchronous loader is busy.
	root.size=Vector2i(1280,800)
	var directory:=Paths.cache_directory("interior_test_%d"%Time.get_ticks_usec())
	var path:=directory.path_join("map.gltf")
	var doc:=Doc.new();doc.add_box("ground",Vector3(0,-.15,0),Vector3(120,.2,120))
	check(doc.save(path)==OK,"create isolated fixture")
	Net.session().world3d_editor_path=path;Net.session().world3d_editor_doc=doc
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false;editor._draft_directory=directory.path_join("drafts");root.add_child(editor);await physics();editor._safety.enabled=false
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"start real HTTP MCP")
	var discovery:=await rpc("tools/list")
	var env_schema:Dictionary=discovery.result.tools.filter(func(t):return t.name=="set_environment")[0].inputSchema
	check(discovery.result.tools.size()==118 and env_schema.properties.has("interior_cutaway") and env_schema.properties.has("indoor_camera_distance"),"discover current 3D camera settings")
	var catalog:=await call_tool("list_building_templates")
	check(catalog.parameters_schema.properties.has("door_height") and catalog.parameters_schema.properties.has("door_width") and catalog.parameters_schema.properties.has("stair_width") and catalog.parameters_schema.properties.has("stair_landing") and catalog.parameters_schema.properties.has("corridor_width"),"discover shared clearance controls")
	check(catalog.templates.all(func(t):return t.parameters.floor_height==4) and catalog.urban_presets[0].parameters.floor_height==4,"normal and urban defaults are four metres")
	check(not Settings.resolve(doc.map_meta).interior_cutaway,"default cutaway is disabled")
	await call_tool("set_environment",{"interior_cutaway":true})
	var before:=doc.recovery_snapshot();var history:int=doc._undo.size()
	await call_tool("set_environment",{"interior_cutaway":"yes"},false)
	await call_tool("set_environment",{"indoor_camera_distance":20},false)
	await call_tool("generate_buildings",{"parameters":{"stair_width":.5},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":{"door_width":.5},"placements":[{"position":[0,0,0]}]},false)
	await call_tool("generate_buildings",{"parameters":{"stair_landing":.5},"placements":[{"position":[0,0,0]}]},false)
	check(doc.recovery_snapshot()==before and doc._undo.size()==history,"invalid settings/geometry fail without side effects")
	await call_tool("set_environment",{"interior_cutaway":false,"indoor_camera_distance":2.8})
	check(not editor._environment_panel.form.fields.interior_cutaway.button_pressed,"MCP refreshes the shared UI")
	await call_tool("undo");check(Settings.resolve(doc.map_meta).interior_cutaway,"undo camera settings")
	await call_tool("redo");check(not Settings.resolve(doc.map_meta).interior_cutaway,"redo camera settings")
	editor._environment_panel.form.fields.interior_cutaway.button_pressed=true;editor._environment_panel.apply()
	check((await call_tool("get_environment")).environment.interior_cutaway,"UI updates the same MCP state")
	var parameters:=Blueprint.defaults().merged({"floors":3,"roof":"flat"},true)
	var made:=await call_tool("generate_buildings",{"parameters":parameters,"placements":[{"position":[0,0,0]}]})
	var id:String=made.building_ids[0]
	check(doc.map_meta.building_instances[id].version==Blueprint.VERSION,"new recipes use the current building version")
	var plan:=Blueprint.generate(parameters)
	check(plan.openings.filter(func(o):return o.type=="door").all(func(o):return o.height==2.5),"inner/outer openings share 2.5 metre doors")
	await call_tool("update_building",{"id":id,"parameters":{"door_height":2.6,"stair_width":1.8,"stair_landing":2.3,"corridor_width":2.3}})
	await call_tool("undo");await call_tool("redo");await call_tool("undo")
	# A v5 recipe has explicit old storey height but no new dimension fields.
	var old_p:=Blueprint.defaults().merged({"floor_height":3.0,"door_height":2.2,"stair_width":1.4,"corridor_width":1.8,"floors":2},true)
	var old:=await call_tool("generate_buildings",{"parameters":old_p,"placements":[{"position":[32,0,0]}]})
	var old_id:String=old.building_ids[0];var old_instance:Dictionary=doc.map_meta.building_instances[old_id]
	old_instance.version=5
	for key:String in ["door_height","door_width","stair_width","stair_landing","corridor_width"]:old_instance.parameters.erase(key)
	check(Blueprint.valid_meta(doc.map_meta),"v5 map remains readable")
	await call_tool("update_building",{"id":old_id,"parameters":{"seed":8}})
	var updated:Dictionary=doc.map_meta.building_instances[old_id].parameters
	check(updated.floor_height==3 and updated.door_height==2.2 and updated.stair_width==1.4,"updating old recipe preserves its scale")
	await call_tool("generate_buildings",{"parameters":Blueprint.layout_defaults("urban_village").merged({"floors":2},true),"placements":[{"position":[-32,0,0],"yaw":37}]})
	await call_tool("save_world");await call_tool("open_world",{"path":path,"discard_changes":true});doc=editor._doc
	check(Settings.resolve(doc.map_meta).interior_cutaway and is_equal_approx(Settings.resolve(doc.map_meta).indoor_camera_distance,2.8),"save/reopen camera configuration")
	check(doc.map_meta.building_instances[id].parameters.door_height==2.5,"save/reopen new dimensions")
	before=doc.recovery_snapshot()
	editor.free();Net.session().world3d_editor_doc=null;Net.session().world3d_editor_path="";await physics()
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();root.add_child(loader);loader.start(path)
	var loaded:Array=await loader.finished
	check(loaded[0]!=null,"saved runtime map loads")
	if loaded[0]!=null:
		await camera_checks(loaded[0],doc,id)
		check(doc.recovery_snapshot()==before,"runtime hiding never modifies document / authored visibility")
	print("fixture=",directory)
	print("test_world3d_interior_camera: ","PASS" if failed==0 else "FAIL");quit(0 if failed==0 else 1)

func camera_checks(scene:Node3D,doc:RefCounted,id:String)->void:
	var host:=Node3D.new();root.add_child(host);host.add_child(scene);Stream.sync(scene,host,Vector3.ZERO);await physics()
	var rig:=CameraRig.new();var camera:=Camera3D.new();camera.name="Camera3D";camera.current=true;rig.add_child(camera);host.add_child(rig)
	rig.bind_map(scene,Settings.resolve(doc.map_meta))
	var cut=rig.cutaway;var room:Dictionary=cut.locate(Vector3.ZERO);var space:=host.get_world_3d().direct_space_state
	check(room.get("id")==id and room.floor==0,"identify occupied storey")
	var focus:=Vector3(0,1.6,-3);var wanted:=Vector3(0,4.8,-3)
	var ignore:Array[RID]=[]
	cut.update(room,focus,Vector3(0,2,-3),space,ignore,.3)
	check(cut.hidden.is_empty(),"camera -> person: no cutaway")
	cut.update(room,focus,Vector3(0,3.9,-3),space,ignore,.3)
	check(not cut.hidden.is_empty(),"desired camera inside slab still detects ceiling occlusion")
	cut.update(room,focus,wanted,space,ignore,.3)
	check(not cut.hidden.is_empty(),"camera -> upper floor -> person triggers")
	var ground_id:String=doc.map_meta.building_instances[id].parts["f0/floor"]
	check(scene.get_meta("stream_meshes")[ground_id].visible,"occupied floor remains visible")
	var raw_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(wanted,focus))
	check(not raw_hit.is_empty(),"hidden floor retains physical collision")
	for tick in 5:cut.update(room,focus,wanted,space,ignore,.016)
	check(not cut.hidden.is_empty(),"hidden slab remains the occlusion source; no flicker")
	# Put a separate object nearer the camera than the floor. A reversed ray or
	# a scan that skips props to find a later slab would incorrectly activate.
	var blocker:=StaticBody3D.new();var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.6,.3,.6);shape.shape=box;blocker.add_child(shape);host.add_child(blocker);blocker.position=Vector3(0,4.5,-3);blocker.set_meta("uuid","ordinary_prop");await physics()
	cut.update(room,focus,wanted,space,ignore,.3)
	check(cut.hidden.is_empty(),"camera -> prop -> floor -> person must not trigger")
	blocker.free();await physics()
	cut.update(room,focus,Vector3(7,1.6,-3),space,ignore,.3)
	check(cut.hidden.is_empty(),"camera -> wall -> person must not trigger")
	var prehidden:Node3D=scene.get_meta("stream_meshes")[doc.map_meta.building_instances[id].parts["f2/floor/left"]]
	prehidden.visible=false
	cut.update(room,focus,wanted,space,ignore,.3);cut.restore()
	check(not prehidden.visible,"restoring cutaway preserves a previously invisible mesh")
	prehidden.visible=true
	for mode:String in ["first_person","vr"]:
		cut.update(room,focus,wanted,space,ignore,.3)
		check(rig.set_view_mode(mode) and cut.hidden.is_empty(),"switch to "+mode+" restores immediately")
		var old_transform:=rig.transform
		var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
		var old_distance:float=rig._want_distance;rig._unhandled_input(wheel)
		check(rig._want_distance==old_distance,mode+" does not consume orbit controls")
		rig.follow(Vector3(0,.9,0),.1)
		check(cut.hidden.is_empty() and rig.transform==old_transform,mode+" neither hides nor changes head pose")
		rig.set_view_mode("third_person")
	cut.update(room,focus,wanted,space,ignore,.3)
	Stream.sync(scene,host,Vector3(500,0,500));Stream.sync(scene,host,Vector3.ZERO);await physics()
	cut.update(room,focus,wanted,space,ignore,.016)
	check(not cut.hidden.is_empty() and cut.hidden.keys().all(func(key):return not scene.get_meta("stream_meshes")[key].visible),"streamed replacement meshes keep the active cutaway")
	var upper_room:Dictionary=cut.locate(Vector3(0,4,-3))
	cut.update(upper_room,focus+Vector3.UP*4,wanted+Vector3.UP*4,space,ignore,.3)
	var upper_floor:String=doc.map_meta.building_instances[id].parts["f1/floor/left"]
	check(not cut.hidden.is_empty() and scene.get_meta("stream_meshes")[upper_floor].visible,"changing floor restores the occupied floor and hides only levels above it")
	cut.enabled=false;cut.update(room,focus,wanted,space,ignore,.3)
	check(cut.hidden.is_empty(),"disabled map setting never activates")
	cut.enabled=true
	cut.update(cut.locate(Vector3(0,12,0)),focus,wanted,space,ignore,.016)
	check(cut.hidden.is_empty(),"roof terrace / leaving the building restores upper levels")
	for other_id:String in doc.map_meta.building_instances:
		var instance:Dictionary=doc.map_meta.building_instances[other_id]
		if instance.parameters.layout!="urban_village":continue
		var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(instance.yaw)),Blueprint.vec(instance.position))
		var urban:=Blueprint.generate(instance.parameters)
		var feet:Vector3=frame*Blueprint.vec(urban.stairs.back().top)
		Stream.sync(scene,host,feet);await physics()
		var roof_room:Dictionary=cut.locate(feet)
		check(roof_room.get("key","").ends_with(":headhouse"),"rotated rooftop stair enclosure is indoors")
		cut.update(roof_room,feet+Vector3.UP*1.6,feet+Vector3.UP*5,space,ignore,.3)
		check(not cut.hidden.is_empty() and cut.hidden.has(instance.parts["roof/headhouse/ceiling"]),"headhouse ceiling triggers without hiding its occupied walls")
		check(cut.locate(frame*Blueprint.vec(urban.terraces.back().center)).is_empty(),"adjacent open roof terrace remains outdoors")
		cut.restore()
	Stream.sync(scene,host,Vector3.ZERO);await physics()
	# Small changes of capsule height must not shift the network foot anchor.
	var body:=WalkBody.new();var collider:=CollisionShape3D.new();collider.name="CollisionShape3D";body.add_child(collider);host.add_child(body)
	var model:=Node3D.new();model.set_script(preload("res://scripts/char/character_model_3d.gd"));model.auto_configure=false;body.add_child(model)
	var height:=preload("res://scripts/world3d/player_clearance.gd").apply(body,model)
	check(is_equal_approx(collider.position.y-height/2,-.9),"capsule resize preserves foot origin")
	body.free()
	# Gameplay uses a conservative clearance for the tallest current identity.
	var nav:=preload("res://scripts/world3d/world_navigation.gd").new();nav.agent_height=2.1;host.add_child(nav);nav.build(scene.get_meta("stream_library"))
	while not nav.fully_ready:await process_frame
	var plan:=Blueprint.generate(doc.map_meta.building_instances[id].parameters)
	for destination:Dictionary in plan.rooms:
		var route:Dictionary=nav.find_path(Blueprint.vec(plan.entrance),Blueprint.vec(destination.center))
		check(route.ok,"2.1m clearance reaches "+destination.id)
		if not route.ok:
			print("NAV_FAILURE ",route)
	# Runtime navigation uses the current character's height, not the maximum
	# test capsule, so old 2.2m doors remain usable by the normal 1.9m actor.
	var previous_map:RID=nav.map;var previous_nav_version:int=nav.version
	await nav.resize_agent(1.9,scene.get_meta("stream_library"),Vector3.ZERO)
	check(nav.map!=previous_map and nav.version>previous_nav_version and nav.agent_height==1.9,"height change swaps a complete bake while retaining navigation node identity")
	for old_id:String in doc.map_meta.building_instances:
		if old_id==id:continue
		var old_instance:Dictionary=doc.map_meta.building_instances[old_id]
		if old_instance.parameters.floor_height!=3:continue
		var old_plan:=Blueprint.generate(old_instance.parameters)
		var origin:=Blueprint.vec(old_instance.position)
		for destination:Dictionary in old_plan.rooms:
			var route:Dictionary=nav.find_path(origin+Blueprint.vec(old_plan.entrance),origin+Blueprint.vec(destination.center))
			check(route.ok,"old dimensions remain navigable for normal-height actor: "+destination.id)
			if not route.ok:print("LEGACY_NAV ",route)
	# Third-person orbit through a slab can use the unoccluded desired position.
	rig.pitch=deg_to_rad(55);rig.distance=4;rig._want_distance=4;rig.indoor_distance=4
	for tick in 25:rig.follow(Vector3(0,.9,-3),1.0/60)
	check(not cut.hidden.is_empty() and rig.global_position.y>3.78,"camera avoids visible geometry but ignores hidden upper-floor collisions")
	var previous_y:float=rig.last_focus.y;rig.follow(Vector3(0,1.07,-3),1.0/60)
	check(rig.last_focus.y-previous_y<.1,"desktop stair focus smooths a 17cm physical step")
	if DisplayServer.get_name()!="headless":
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-25,0);host.add_child(sun)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new();host.add_child(environment);Settings.apply(Settings.defaults(),sun,environment.environment)
		var reference:=MeshInstance3D.new();var capsule:=CapsuleMesh.new();capsule.height=2.1;capsule.radius=.3;reference.mesh=capsule;reference.position=Vector3(0,1.05,-3);host.add_child(reference)
		var material:=StandardMaterial3D.new();material.albedo_color=Color("467ed6");reference.material_override=material
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("building_metrics/interior_cutaway.png"))
		rig.set_view_mode("first_person")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("building_metrics/restored_at_same_camera.png"))
	cut.restore();host.free()
