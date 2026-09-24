extends SceneTree
func _init():call_deferred("run")
func run():
	root.size=Vector2i(1440,1000)
	change_scene_to_file("res://scenes/content_editor.tscn")
	while current_scene==null:await process_frame
	current_scene._select_map("Axel256")
	current_scene._playtest.call_deferred()
	var deadline:=Time.get_ticks_msec()+45000
	while current_scene==null or current_scene.name!="World":
		if Time.get_ticks_msec()>deadline:push_error("World timeout");quit(1);return
		await process_frame
	await create_timer(4).timeout
	var w=current_scene
	for hour in [12,2]:
		w.map_field.set_atmosphere(hour,"clear",0.0)
		w.map_field._weather_fx._mix=1.0
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/code/rmmo_runtime/style_work/town_m/lamp_scale_%d.png"%hour)
	print("LAMP_VISUAL_READY")
	quit()
