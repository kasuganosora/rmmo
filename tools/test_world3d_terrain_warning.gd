extends SceneTree
const Warning = preload("res://scripts/world3d/terrain_warning.gd")
var failed := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func surface(host: Node, pos: Vector3, size_: Vector3, slope: float = 0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.position = pos
	body.rotation.z = deg_to_rad(slope)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_
	visual.mesh = mesh
	body.add_child(visual)
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	surface(host, Vector3(0, -0.1, 0), Vector3(8, 0.2, 8))
	surface(host, Vector3(0, 2.9, 0), Vector3(3, 0.2, 8))
	surface(host, Vector3(12, 0, 0), Vector3(6, 0.2, 6), 20)
	surface(host, Vector3(22, -0.1, 0), Vector3(2, 0.2, 4))
	surface(host, Vector3(25, 0.5, 0), Vector3(2, 0.2, 4))
	await physics_frame
	await process_frame
	var space := host.get_world_3d().direct_space_state
	var start := Time.get_ticks_usec()
	var lower := Warning.build(space, Vector3.ZERO, 3)
	check(lower.get_surface_count() == 1, "warning under bridge has surface")
	var valid := true
	for vertex in lower.get_faces(): valid = valid and absf(vertex.y - Warning.LIFT) < 0.002
	check(valid, "lower floor warning does not climb onto bridge")
	var upper := Warning.build(space, Vector3(0, 3, 0), 3)
	valid = not upper.get_faces().is_empty()
	for vertex in upper.get_faces(): valid = valid and absf(vertex.y - Warning.LIFT) < 0.002 and absf(vertex.x) <= 1.501
	check(valid, "bridge warning stops at deck edge without projecting to lower floor")
	var ramp := Warning.build(space, Vector3(12, 0.1 / cos(deg_to_rad(20)), 0), 2)
	valid = not ramp.get_faces().is_empty()
	for vertex in ramp.get_faces(): valid = valid and absf(vertex.y - Warning.LIFT - vertex.x * tan(deg_to_rad(20))) < 0.002
	check(valid, "whitebox slope warning follows exact collision surface")
	var steps := Warning.build(space, Vector3(23.5, 0, 0), 3)
	valid = not steps.get_faces().is_empty()
	var faces := steps.get_faces()
	for i in range(0, faces.size(), 3):
		var min_x := minf(faces[i].x, minf(faces[i+1].x, faces[i+2].x)) + 23.5
		var max_x := maxf(faces[i].x, maxf(faces[i+1].x, faces[i+2].x)) + 23.5
		valid = valid and not (min_x < 24 and max_x > 23)
	check(valid, "warning does not fill whitebox gap between steps")
	check(Warning.build(space, Vector3(100, 0, 100), 2).get_surface_count() == 0, "missing ground produces no floating warning")
	print("TERRAIN_METRICS five_builds_ms=%.2f" % ((Time.get_ticks_usec() - start) / 1000.0))
	if OS.get_cmdline_user_args().has("--capture"):
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/world3d/skill_area.gdshader")
		material.set_shader_parameter("radius", 2.0)
		var marker := MeshInstance3D.new()
		marker.mesh = ramp
		marker.material_override = material
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(marker)
		marker.position = Vector3(12, 0.1 / cos(deg_to_rad(20)), 0)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-60, -30, 0)
		host.add_child(light)
		var camera := Camera3D.new()
		host.add_child(camera)
		camera.position = Vector3(8, 7, 9)
		camera.look_at(Vector3(12, 0, 0))
		camera.current = true
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("252c35")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.5
		camera.environment = environment
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("rmmo-whitebox-terrain.png"))
	host.free()
	print("test_world3d_terrain_warning: " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
