extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(900,850);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio)
	var model:Node3D=studio.model
	model.configure("female",{"body_model":"female_base_v2","part_ids":{"FrontHair1":201}},{"SurfaceEquipment":preload("res://scripts/char/underwear_equipment.gd").DEFAULT_REVIEW_RECIPE})
	var body:Node3D=model.axis_rig.body
	var hair:Node3D=model.axis_rig.hair
	studio.camera.size=1.15;studio.camera.position=Vector3(2,1.55,4);studio.camera.look_at(Vector3(0,1.42,0))
	var contacts_mode:bool="--contacts" in OS.get_cmdline_user_args()
	var folder:String=Art.review_path("character_3d/source_hair_contacts_01" if contacts_mode else "character_3d/source_hair_spring_01");DirAccess.make_dir_recursive_absolute(folder)
	for enabled in [false,true]:
		hair.spring.set_enabled(true if contacts_mode else enabled)
		hair.spring.set_contacts_enabled(enabled if contacts_mode else false)
		for frame in 140:
			var angle:=35.0*sin(clampf((frame-20)/40.0,0,1)*TAU) if frame<60 else 0.0
			var pose:Dictionary=body.POSES.stand.duplicate()
			pose.head=Vector3(angle*20.0/35.0 if contacts_mode else 0.0,angle,0);body.set_angles(pose)
			await process_frame
			if frame in [19,30,50,65,139]:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/%s_%03d.png"%["on" if enabled else "off",frame])
	studio.free()
	for frame in 3:await process_frame
	print("PASS 10 native spring enabled/disabled head-turn comparison captures")
	quit()
