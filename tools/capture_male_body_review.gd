extends SceneTree
const Model = preload("res://scripts/char/character_model_3d.gd")
const Starter = preload("res://scripts/char/starter_equipment.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(600, 800)
	var scene := Node3D.new()
	root.add_child(scene)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("899ba6")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b8c2d1")
	world.environment.ambient_light_energy = .42
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, 32, 0)
	light.light_energy = 1.15
	scene.add_child(light)
	var model = Model.create("male", {}, {})
	scene.add_child(model)
	model.set_process(false)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.15
	scene.add_child(camera)
	camera.position = Vector3(0, 1.08, 5)
	camera.look_at(Vector3(0, 1.0, 0))
	var cases := [["front", "idle", {}, 0.0], ["left", "idle", {}, 0.0], ["back", "idle", {}, 0.0], ["front", "walk", {}, .2], ["front_left", "dash", {}, .15], ["front_left", "attack", Starter.PARTS, .2], ["front", "idle", Starter.PARTS, 0.0]]
	cases.append(["front", "idle", {"Boots":1}, 0.0])
	cases.append(["front_left", "dash", {"Clothing1":2,"Boots":2}, .15])
	cases.append(["front", "idle", Starter.PARTS, 0.0])
	cases.append(["front", "walk", Starter.PARTS, .2])
	cases.append(["front_left", "dash", Starter.PARTS, .15])
	cases.append(["left", "sit_chair", Starter.PARTS, .2])
	cases.append(["front_left", "dash", {"Clothing1":2,"Boots":2}, .15])
	cases.append(["left", "idle", Starter.PARTS, 0.0])
	cases.append(["back", "idle", Starter.PARTS, 0.0])
	for i in cases.size():
		var entry: Array = cases[i]
		if i==9:model.configure("female", {}, Starter.PARTS)
		model.set_equipment(entry[2])
		model.play(entry[1], entry[0], true)
		model.pose_at(entry[3])
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var path := preload("res://scripts/asset/art_paths.gd").review_path("character_3d/male_body_%d.png" % i)
		root.get_texture().get_image().save_png(path)
		print("CAPTURE ", path)
	scene.free()
	quit()
