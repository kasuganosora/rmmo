extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(720,720);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var folder:String=Art.review_path("character_3d/source_hair_lighting_matrix_02")
	DirAccess.make_dir_recursive_absolute(folder)
	for lighting in ["studio","game"]:
		if lighting=="game":studio.toggle_lighting()
		for row in [1001,1007,1019]:
			studio.model.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":203},"hair_on":true,"hair_row":row},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
			studio.model.play("idle","front",true);studio.model._from_rotations.clear();studio.model.pose_at(.3)
			preload("res://tools/source_hair_lighting_candidate.gd").apply(studio.model.axis_rig.hair,true,studio.key)
			for angle in [0,45,90]:
				var center:=Vector3(0,1.58,0)
				studio.camera.size=.65;studio.camera.position=center+Vector3(sin(deg_to_rad(angle))*5,.03,cos(deg_to_rad(angle))*5);studio.camera.look_at(center)
				for frame in 3:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/%s_%d_%d.png"%[lighting,row,angle])
	studio.free()
	for frame in 3:await process_frame
	print("WROTE 18 color/light/view captures; inspect shader log and images")
	quit()
