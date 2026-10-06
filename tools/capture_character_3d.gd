extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var scene=load("res://scenes/character_create.tscn").instantiate()
	root.add_child(scene)
	await create_timer(2.0).timeout
	scene._preview_action="idle";scene._play_preview()
	await process_frame;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(preload("res://scripts/asset/art_paths.gd").review_path("character_3d"))
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/creator.png"))
	print("CAPTURE_3D_OK")
	quit()
