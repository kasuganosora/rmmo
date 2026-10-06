extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Motion=preload("res://scripts/char/character_axis_animation.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(700,900);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var motion:=Motion.new()
	var library:AnimationLibrary=load(Art.path("characters/animations/female_base_v2_universal.res"))
	assert(motion.install(body.skeleton,library))
	var folder:String=Art.review_path("character_3d/axis_animation_03");DirAccess.make_dir_recursive_absolute(folder)
	var report:Array=[]
	var identity:Array=[body.get_instance_id(),body.skeleton.get_instance_id(),body.mesh_instance.mesh.get_instance_id()]
	for clip:StringName in library.get_animation_list():
		var animation:Animation=library.get_animation(clip)
		var bottom:=INF;var max_length_error:=0.0
		for frame:int in range(31):
			assert(motion.apply(body,clip,animation.length*frame/30.0),body.pose_sync_error)
			body.position=motion.visual_offset
			for bone:int in body.skeleton.get_bone_count():
				max_length_error=maxf(max_length_error,body.skeleton.get_bone_pose_position(bone).distance_to(body.skeleton.get_bone_rest(bone).origin))
			for point:Vector3 in body.posed_points:
				assert(point.is_finite());bottom=minf(bottom,point.y+body.position.y)
			if frame not in [0,8,15,23]:continue
			var bounds:=AABB(body.posed_points[0]+body.position,Vector3.ZERO)
			for point:Vector3 in body.posed_points:bounds=bounds.expand(point+body.position)
			for view:String in ["front","side","back"]:
				var center:Vector3=bounds.get_center();studio.camera.size=maxf(2.25,maxf(bounds.size.x,bounds.size.z)*1.6)
				studio.camera.position=center+{"front":Vector3(.2,0,5),"side":Vector3(5,0,.2),"back":Vector3(.2,0,-5)}[view];studio.camera.look_at(center)
				for wait in 2:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/"+String(clip)+"_"+str(frame)+"_"+view+".png")
		assert(max_length_error<.000001)
		if animation.loop_mode==Animation.LOOP_LINEAR:
			assert(motion.apply(body,clip,0));var first:PackedVector3Array=body.posed_points.duplicate();var offset:Vector3=motion.visual_offset
			assert(motion.apply(body,clip,animation.length))
			assert(first==body.posed_points and offset==motion.visual_offset,"Loop endpoint differs")
		report.append({"clip":clip,"samples":31,"minimum_surface_y_m":bottom,"joint_translation_error":max_length_error})
		print("AXIS clip=",clip," min_y=",bottom," bone_translation=",max_length_error)
	assert(identity==[body.get_instance_id(),body.skeleton.get_instance_id(),body.mesh_instance.mesh.get_instance_id()])
	assert(not motion.apply(body,"missing",0))
	# Reject legacy translated-joint tracks before any body mutation.
	var legacy:AnimationLibrary=load(Art.path("characters/animations/female_universal.res"))
	assert(not Motion.new().install(body.skeleton,legacy))
	var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	studio.free()
	for wait in 3:await process_frame
	print("PASS axis animation structural checks; visual review remains separate");quit()
