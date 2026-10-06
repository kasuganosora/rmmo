extends SceneTree
## Real renderer acceptance on the existing Axel256 map. Outputs to user://weather_preview.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1440, 1000)
	Engine.max_fps = 60
	change_scene_to_file("res://scenes/content_editor.tscn")
	while current_scene == null:
		await process_frame
	current_scene._select_map("Axel256")
	current_scene._playtest.call_deferred()
	var deadline := Time.get_ticks_msec() + 45000
	while current_scene == null or current_scene.name != "World":
		if Time.get_ticks_msec() > deadline:
			push_error("Weather preview: World timeout")
			quit(1)
			return
		await process_frame
	await create_timer(4).timeout
	var world = current_scene
	root.get_node("MockServer").weather_auto = false
	var settings = root.get_node("GameSettings")
	settings.weather_fx = true
	settings.changed.emit()
	var output := ProjectSettings.globalize_path("user://weather_preview")
	DirAccess.make_dir_recursive_absolute(output)
	var kinds := ["snow"] if "--snow-only" in OS.get_cmdline_user_args() else ["clear", "rain", "storm", "snow", "fog"]
	for kind in kinds:
		world.map_field.set_atmosphere(0, kind, 1.0)
		world.map_field._weather_fx._process(5.0)
		await create_timer(6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(kind + ".png"))
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(kind + "_motion.png"))
		print("WEATHER_CAPTURE ", kind, " ", output)
	print("WEATHER_PREVIEW_READY")
	quit()
