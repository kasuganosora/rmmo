extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(900,850);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var model:Node3D=studio.model
	var capture_name := "source_hair_fitted_02"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_name=arg.trim_prefix("--capture=").validate_filename()
	var folder:String=Art.review_path("character_3d/"+capture_name);DirAccess.make_dir_recursive_absolute(folder)
	for id in [201,202,203]:
		model.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":id},"hair_on":true,"hair_row":18},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
		assert(model.axis_rig.hair.selected==id)
		model.play("idle","front",true);model._from_rotations.clear();model.pose_at(.3)
		if "--candidate" in OS.get_cmdline_user_args():
			preload("res://tools/source_hair_lighting_candidate.gd").apply(model.axis_rig.hair,not "--no-gloss" in OS.get_cmdline_user_args(),studio.key)
		for view:String in ["front","side","back"]:
			studio.camera.size=1.05
			var center:=Vector3(0,1.45,0)
			studio.camera.position=center+({"front":Vector3(0,.03,5),"side":Vector3(5,.03,0),"back":Vector3(0,.03,-5)}[view]);studio.camera.look_at(center)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/%d_%s.png"%[id,view])
	studio.free()
	for frame in 3:await process_frame
	print("WROTE 9 fitted source-hair captures; verify shader log and inspect images before acceptance")
	quit()
