extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1100,720);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var motion:=Motion.new();var library:AnimationLibrary=load(Art.path("characters/animations/female_base_v2_universal.res"))
	assert(motion.install(body.skeleton,library))
	studio.floor_mesh.material_override.albedo_color=Color(.45,.48,.52)
	var folder:String=Art.review_path("character_3d/axis_support_01");DirAccess.make_dir_recursive_absolute(folder)
	for clip:String in ["idle","walk","dash","death"]:
		var animation:Animation=library.get_animation(clip)
		var time:float=animation.length if clip=="death" else animation.length*.25
		for enabled:bool in [false,true]:
			motion.support_enabled=enabled;assert(motion.apply(body,clip,time));body.position=motion.visual_offset
			var bounds:=AABB(body.posed_points[0]+body.position,Vector3.ZERO)
			for point:Vector3 in body.posed_points:bounds=bounds.expand(point+body.position)
			for view:String in ["full","contact"]:
				var center:Vector3=bounds.get_center()
				studio.camera.size=2.2
				if clip=="death":
					studio.camera.size=1.65
					if view=="contact":center=body.get_solved_bone_pose(body.skeleton.find_bone("hip")).origin+body.position;studio.camera.size=.7
				elif view=="contact":center=Vector3(0,.12,0);studio.camera.size=.55
				studio.camera.position=center+Vector3(5,.45,.25);studio.camera.look_at(center)
				for wait in 3:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/"+clip+"_"+("supported" if enabled else "raw")+"_"+view+".png")
	studio.free()
	for wait in 3:await process_frame
	print("PASS 16 support comparison captures");quit()
