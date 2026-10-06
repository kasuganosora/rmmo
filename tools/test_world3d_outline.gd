extends SceneTree
var failed := 0
func _init() -> void: call_deferred("run")
func check(value: bool, label_: String) -> void:
	print(("PASS: " if value else "FAIL: ") + label_)
	if not value: failed += 1
func frames() -> void:
	for i in 8: await process_frame
	await physics_frame
	await RenderingServer.frame_post_draw
func red_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x,y)
			if p.r > .7 and p.g < .5 and p.b < .5: count += 1
	return count
func visual(mesh: Mesh, parent: Node, at: Vector3, color: Color) -> MeshInstance3D:
	var model := MeshInstance3D.new(); model.mesh = mesh; model.position = at
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = color
	model.material_override = material; parent.add_child(model); return model
func run() -> void:
	root.size = Vector2i(640,480)
	var host := Node3D.new(); root.add_child(host)
	var player := CharacterBody3D.new(); player.position = Vector3(0,1,0); host.add_child(player)
	var torso := CapsuleMesh.new(); torso.radius = .22; torso.height = 1.1
	var model := visual(torso, player, Vector3(0,-.18,0), Color.BLUE)
	var head := SphereMesh.new(); head.radius = .3; head.height = .6
	visual(head, player, Vector3(0,.62,0), Color.BLUE)
	var camera := Camera3D.new(); camera.position = Vector3(0,1,6); camera.current = true; host.add_child(camera); camera.look_at(Vector3(0,1,0)); camera.fov = 40
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(.1,.1,.1); host.add_child(environment)
	var outline := preload("res://scripts/world3d/occlusion_outline.gd").new(); host.add_child(outline); outline.bind(player,camera)
	var settings := preload("res://scripts/world3d/environment_settings.gd").defaults(); settings.outline_color = [1,.2,.1]; settings.outline_width = 3
	outline.configure(settings)
	await frames()
	check(not outline.occluded and red_pixels(root.get_texture().get_image()) == 0, "no outline for visible player")
	var wall := StaticBody3D.new(); wall.position = Vector3(0,1,2); host.add_child(wall)
	var box := BoxMesh.new(); box.size = Vector3(3,3,.3); visual(box,wall,Vector3.ZERO,Color(.3,.3,.3))
	var shape := CollisionShape3D.new(); var shape_box := BoxShape3D.new(); shape_box.size = box.size; shape.shape = shape_box; wall.add_child(shape)
	await frames()
	var shot := root.get_texture().get_image()
	var count := red_pixels(shot)
	check(outline.occluded and count > 100 and count < 640*480/20, "occluded actual player produces a narrow visible silhouette")
	shot.save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_gameplay/occlusion_outline.png"))
	var mask := outline.mask.get_texture().get_image()
	check(mask.get_pixel(0,0).a < .01 and mask.get_pixel(mask.get_width()/2,mask.get_height()/2).a > .9, "mask excludes walls and has transparent background")
	settings.outline_enabled = false; outline.configure(settings); await frames()
	check(red_pixels(root.get_texture().get_image()) == 0, "disabling outline removes the overlay")
	settings.outline_enabled = true; outline.configure(settings)
	var gear := BoxMesh.new(); gear.size = Vector3(.7,.2,.2)
	var extra := visual(gear,player,Vector3(.45,0,0),Color.BLUE)
	outline.scan_time = 0; await frames()
	check((extra.layers & outline.MASK_LAYER) != 0 and red_pixels(root.get_texture().get_image()) != count, "new character geometry updates the silhouette")
	outline.queue_free(); await frames()
	check(model.layers == 1 and extra.layers == 1, "outline cleanup restores player render layers")
	host.free()
	print("test_world3d_outline: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
