extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(900,850);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var model:Node3D=studio.model
	var id:=201
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--hair="):id=int(arg.trim_prefix("--hair="))
	assert(id in [201,202,203])
	model.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":id}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
	var body:Node3D=model.axis_rig.body
	var hair:Node3D=model.axis_rig.hair
	var folder:String=Art.review_path("character_3d/source_hair_actions_01"+("" if id==201 else "_%d"%id));DirAccess.make_dir_recursive_absolute(folder)
	for clip:String in ["walk","sit_chair"]:
		model.play(clip,"front",true);model._from_rotations.clear()
		hair.spring.set_enabled(true);hair.spring.set_contacts_enabled(true)
		for frame in 100:
			model.pose_at(model.action_duration()*minf(frame/60.0,1.0 if clip=="sit_chair" else 2.0))
			await process_frame
			if frame in [30,60,99]:
				var center:Vector3=body.global_transform*(body.solved_bones[hair.head_index].origin+body.root_offset)+Vector3(0,-.15,0)
				for view:String in ["side","back"]:
					studio.camera.size=1.05
					studio.camera.position=center+(Vector3(5,.02,.1) if view=="side" else Vector3(0,.02,-5));studio.camera.look_at(center)
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(folder+"/%s_%03d_%s.png"%[clip,frame,view])
	studio.free()
	for frame in 3:await process_frame
	print("PASS 12 actual Model walk/sit hair contact captures; no seat-contact claim")
	quit()
