extends SceneTree
## Native source geometry/rig inspection. Does not install or replace game hair.
const SOURCE = "D:/code/rmmo_runtime/assets/characters/source_hair/koikatu/"
const OUTPUT = "D:/code/rmmo_runtime/review_artifacts/character_3d/source_hair_01/"
var builder = preload("res://tools/source_hair_builder.gd").new()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(720, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.1, 0.13)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.8
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.8
	world.add_child(camera)
	for n in range(1, 7):
		var group := Node3D.new()
		world.add_child(group)
		for part in ["f", "b"]:
			group.add_child(builder.load_source("p_cf_hair_%s_%02d" % [part, n]))
		for side in [0, 1, 2]:
			var angle := float(side) * PI / 2.0
			camera.position = Vector3(sin(angle), 0.07, cos(angle)) * 1.5
			camera.look_at(Vector3(0, 0.07, 0))
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "source_%02d_%d.png" % [n, side])
		group.queue_free()
		await process_frame
	print("PASS: captured 6 native front/back pairs, 18 views; material is inspection-only")
	quit()
