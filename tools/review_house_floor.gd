extends "res://tools/test_ground_batching.gd"
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,800)
	var checkpoint=JSON.parse_string(FileAccess.get_file_as_string("D:/code/rmmo_runtime/review_artifacts/house_revision/painted_checkpoint.json"))
	var house=checkpoint.houses[0];var origin:=Vector3(house.position[0],0,house.position[2])
	var doc:=Doc.new();doc.records=checkpoint.records.filter(func(r):return not r.has("building") or r.building.id==house.building_id)
	viewport=SubViewport.new();viewport.size=root.size;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.4,.5,.6);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.8;viewport.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-43,145,0);viewport.add_child(sun)
	camera=Camera3D.new();viewport.add_child(camera);camera.fov=65
	var scene:=doc.build();viewport.add_child(scene);var nodes:=scene.get_children()
	var batcher:=Batch.new();viewport.add_child(batcher)
	var before:Array=[]
	for state in ["source","batch"]:
		if state=="batch":batcher.sync(nodes);batcher.flush()
		for i in 5:
			camera.position=origin+Vector3(-1+i*.3,6.1,-4.5);camera.look_at(origin+Vector3(-5.3,4.46,-4.5))
			await frames(3);await RenderingServer.frame_post_draw
			var img:=viewport.get_texture().get_image();img.save_png("D:/code/rmmo_runtime/review_artifacts/floor_%s_%d.png"%[state,i])
			if state=="source":before.append(img)
			else:print("FLOOR_DIFF ",i," ",difference(before[i],img))
	quit()
