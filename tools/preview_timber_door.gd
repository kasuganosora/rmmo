extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var out:="D:/code/rmmo_runtime/review_artifacts/timber_door"
	DirAccess.make_dir_recursive_absolute(out)
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file("D:/code/rmmo_runtime/assets/timber_door/timber_door.glb",state)!=OK:quit(1);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(900,1000);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var model:=document.generate_scene(state);viewport.add_child(model)
	for node in model.find_children("*","MeshInstance3D",true,false):
		for slot in node.mesh.get_surface_count():
			var material:StandardMaterial3D=node.mesh.surface_get_material(slot)
			print("DOOR_MATERIAL ",material.resource_name," vertex_color=",material.vertex_color_use_as_albedo)
			material.vertex_color_use_as_albedo=true
	var packed:=PackedScene.new()
	if packed.pack(model)!=OK:quit(1);return
	if ResourceSaver.save(packed,"D:/code/rmmo_runtime/assets/timber_door/timber_door_preview.tscn")!=OK:quit(1);return
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.18,.20,.22);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.65;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-140,0);viewport.add_child(sun)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.65;viewport.add_child(camera)
	for side in [-1,1,0]:
		camera.position=Vector3(1.8,.6,side*5);camera.look_at(Vector3.ZERO)
		if side==0:camera.position=Vector3(0,0,-5);camera.look_at(Vector3.ZERO)
		for i in 10:await process_frame
		await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out.path_join("front.png" if side==-1 else ("back.png" if side==1 else "front_straight.png")))
	camera.size=.75;camera.position=Vector3(-.43,.70,-3);camera.look_at(Vector3(-.43,.64,-.06))
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out.path_join("spear_detail.png"))
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,140,0);fill.light_energy=.5;viewport.add_child(fill)
	camera.size=.40;camera.position=Vector3(-.30,.82,-1.4);camera.look_at(Vector3(-.53,.64,-.06))
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png(out.path_join("spear_relief.png"))
	quit()
