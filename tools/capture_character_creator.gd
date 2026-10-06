extends SceneTree
const ArtPaths=preload("res://scripts/asset/art_paths.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var scene = load("res://scenes/character_create.tscn").instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	for gender in ["male","female","young_male","young_female"]:
		var idx: int = ["female","male","young_male","young_female"].find(gender)
		scene.gender_option.select(idx)
		scene.gender_option.item_selected.emit(idx)
		await create_timer(0.8).timeout
		assert(scene.preview.sprite_frames.has_animation("sit_chair_back_right"))
	var toggle: CheckButton = scene.find_child("Clothing1",true,false)
	assert(toggle != null)
	toggle.button_pressed = false
	await create_timer(0.8).timeout
	assert(scene._custom.equipment["Clothing1"] == null)
	toggle.button_pressed = true
	await create_timer(0.8).timeout
	assert(scene._custom.equipment["Clothing1"] == 1)
	scene._play_preview()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ArtPaths.path("character_creator/creator_screenshot.png"))
	print("PASS actual creator scene: four bodies, equipment toggles, animations; screenshot saved")
	quit()
