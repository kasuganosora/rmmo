extends SceneTree
## Runs the existing editor playtest entry point; no map edits or character creation.
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,800)
	change_scene_to_file("res://scenes/content_editor.tscn")
	while current_scene==null:await process_frame
	current_scene._select_map("Axel256")
	current_scene._playtest.call_deferred()
	var deadline:=Time.get_ticks_msec()+45000
	while current_scene==null or current_scene.name!="World":
		if Time.get_ticks_msec()>deadline:
			push_error("3D world preview timeout");quit(1);return
		await process_frame
	await create_timer(3).timeout
	var player=current_scene.player
	assert(player.character_3d!=null and not player.anim.visible)
	player.input_locked=true
	player.set_facing_dir(2)
	player.clear_character_action()
	var gender:="female" if "--imported" in OS.get_cmdline_user_args() else "male"
	player.character_3d.configure(gender,{},preload("res://scripts/char/starter_equipment.gd").PARTS)
	if "--size-review" in OS.get_cmdline_user_args():
		var view=player.character_3d
		view.model.set_process(false);view.model.pose_at(.3)
		var current_scale:float=view.render_scale
		for version in ["before","after"]:
			view.render_scale=current_scale/.82 if version=="before" else current_scale
			view.display.scale=Vector2.ONE*view.render_scale;view._anchor_feet()
			assert((view.display.position+view.camera.unproject_position(Vector3.ZERO)*view.render_scale).length()<.001)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world_size_")+version+".png")
		print("PASS map size before/after, fixed feet anchor, scale=",current_scale)
		quit();return
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(preload("res://scripts/asset/art_paths.gd").review_path("character_3d"))
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world.png"))
	player.set_sitting(true)
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("character_3d/world_sitting.png"))
	player.set_sitting(false)
	print("PASS real 2D map + 3D player, independent equipment, seated state; captures saved")
	quit()
