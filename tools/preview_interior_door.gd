extends SceneTree

const OUT := "D:/code/rmmo_runtime/review_artifacts/interior_timber_door"
const ASSET := "D:/code/rmmo_runtime/assets/interior_timber_door/"

func _initialize() -> void:
	call_deferred("run")

func capture(viewport: SubViewport, filename: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT.path_join(filename))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ASSET + "interior_timber_door.glb", state) != OK:
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 1000)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model := document.generate_scene(state)
	viewport.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for slot in node.mesh.get_surface_count():
			var material: StandardMaterial3D = node.mesh.surface_get_material(slot)
			material.vertex_color_use_as_albedo = true
	var packed := PackedScene.new()
	if packed.pack(model) != OK or ResourceSaver.save(packed, ASSET + "interior_timber_door_preview.tscn") != OK:
		quit(1)
		return
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.115, .13, .15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.82,.86,.92)
	env.environment.ambient_light_energy = .70
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -145, 0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 125, 0)
	fill.light_energy = .40
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.64
	viewport.add_child(camera)
	camera.position = Vector3(0, .06, -5)
	camera.look_at(Vector3(0, .06, 0))
	await capture(viewport, "front_straight.png")
	camera.position = Vector3(-2, .60, -5)
	camera.look_at(Vector3(0, .05, 0))
	await capture(viewport, "front_angle.png")
	camera.position = Vector3(1.8, .5, 5)
	camera.look_at(Vector3(0, .05, 0))
	var back_light := DirectionalLight3D.new()
	back_light.rotation_degrees = Vector3(-25,20,0)
	back_light.light_energy = .9
	viewport.add_child(back_light)
	await capture(viewport, "back.png")
	back_light.visible = false
	camera.size = .65
	camera.position = Vector3(.9, -.05, -2.5)
	camera.look_at(Vector3(.43, -.17, -.05))
	await capture(viewport, "knob_joinery_detail.png")
	# Look from corridor (-Z) into room (+Z). Screen-right hinge is -X,
	# and negative Y rotation moves the free left edge into +Z.
	var hinge := Vector3(-.6, 0, 0)
	var rotation := Basis(Vector3.UP, deg_to_rad(-45))
	var turn := Transform3D(rotation, hinge - rotation * hinge)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("DoorLeaf"):
			node.transform = turn * node.transform
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(3, .02, 3)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(.26,.28,.29)
	floor_mesh.material = floor_material
	floor.mesh = floor_mesh
	floor.position = Vector3(0,-1.115,.65)
	viewport.add_child(floor)
	var label := Label3D.new()
	label.text = "ROOM  +Z"
	label.font_size = 64
	label.pixel_size = .0018
	label.position = Vector3(.95,-1.08,1.20)
	label.rotation_degrees = Vector3(-90, 180, 0)
	label.no_depth_test = false
	viewport.add_child(label)
	camera.size = 3.05
	camera.position = Vector3(.6,3.6,-4.5)
	camera.look_at(Vector3(0,-.10,.35))
	await capture(viewport, "open_into_room.png")
	quit()
