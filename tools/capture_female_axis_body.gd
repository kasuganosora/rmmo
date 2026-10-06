extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
const Body=preload("res://scripts/char/female_axis_body.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(550,800);root.content_scale_size=root.size
	var studio=preload("res://tools/character_skin_studio.gd").new();studio.interactive=false;root.add_child(studio);studio.model.visible=false
	var body:=Body.new();root.add_child(body);body.initialize()
	assert(body.skeleton.get_bone_count()==80)
	var rest_error:=0.0
	for i in body.rest_points.size():rest_error=maxf(rest_error,body.rest_points[i].distance_to(body.posed_points[i]))
	assert(rest_error<.00001,"Rest pose must preserve source body")
	var poses:Dictionary=Body.POSES
	studio.regional_preview=body
	var canvas:=CanvasLayer.new();root.add_child(canvas);var label:=Label.new();label.position=Vector2(12,12);canvas.add_child(label)
	assert(body.enable_compute(),"GPU solver must initialize on this Vulkan test device")
	var sheet:=Image.create(550*3,800*3,false,Image.FORMAT_RGB8);var index:=0
	for name:String in poses:
		body.use_compute=false;body.set_angles(poses[name]);var reference:PackedVector3Array=body.posed_points.duplicate()
		body.use_compute=true;body.set_angles(poses[name]);var actual:PackedVector3Array=body.read_gpu_points();var max_error:=0.0
		for i in actual.size():max_error=maxf(max_error,actual[i].distance_to(reference[i]))
		assert(max_error<.00001,"CPU/GPU axis solver mismatch")
		body.set_test_pose(name);studio.update_pose_helpers()
		for point:Vector3 in body.posed_points:assert(point.y+body.world_offset.y>=-.00001,"Pose must remain above the test floor")
		for bone in body.skeleton.get_bone_count():
			var parent:int=body.skeleton.get_bone_parent(bone)
			if parent>=0:
				var actual_length:float=body.skeleton.get_bone_global_pose(bone).origin.distance_to(body.skeleton.get_bone_global_pose(parent).origin)
				assert(absf(actual_length-body.skeleton.get_bone_rest(bone).origin.length())<.00001,"Joint motion stretched a bone")
		label.text=name+" / original axis weights"
		var center:=Vector3(0,1.05,0) if not name.begins_with("lie") else Vector3(0,.35,-.4)
		studio.camera.position=center+Vector3(2.0,.3,5);studio.camera.look_at(center);studio.camera.size=2.7
		if name.begins_with("lie"):
			studio.camera.position=Vector3(4,1.2,.3);studio.camera.look_at(Vector3(0,.2,.16));studio.camera.size=3.3
		for p:Vector3 in body.posed_points:assert(p.is_finite() and p.length()<5.0)
		print("POSE ",name," GPU_ms=",body.last_solve_ms," CPU_GPU_max_error=",max_error)
		for frame in 6:await process_frame
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
		picture.save_png(Art.review_path("character_3d/female_axis_"+name+".png"))
		sheet.blit_rect(picture,Rect2i(0,0,550,800),Vector2i((index%3)*550,(index/3)*800));index+=1
		if name=="sit":
			studio.camera.position=Vector3(4,.9,.3);studio.camera.look_at(Vector3(0,.65,.15));studio.camera.size=1.65
			for frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(Art.review_path("character_3d/female_axis_sit_side.png"))
	sheet.save_png(Art.review_path("character_3d/female_axis_poses.png"))
	body.use_compute=false;body.set_angles({})
	for i in body.rest_points.size():assert(body.rest_points[i].distance_to(body.posed_points[i])<.00001)
	# A full root rotation is rigid: pairwise distances must remain unchanged.
	body.set_angles({"hip":Vector3(23,-37,14)},Vector3(.2,.1,-.1))
	var hip_index:int=body.skeleton.find_bone("hip")
	var rigid:Transform3D=body.skeleton.get_bone_global_pose(hip_index)*body.rests.hip.affine_inverse()
	for i in body.rest_points.size():assert(body.posed_points[i].distance_to(rigid*body.rest_points[i])<.00001)
	for pair in [[0,1000],[3000,7000],[14000,21000]]:
		assert(absf(body.posed_points[pair[0]].distance_to(body.posed_points[pair[1]])-body.rest_points[pair[0]].distance_to(body.rest_points[pair[1]]))<.00001)
	var combined:Dictionary={"head":Vector3(12,-20,8),"neck":Vector3(5,-8,3),"chest":Vector3(10,15,-7),"rForeArm":Vector3(20,-65,10),"rThumb1":Vector3(15,20,-12),"lowerJaw":Vector3(8,2,0),"lFoot":Vector3(-15,10,2)}
	body.set_angles(combined);var combined_reference:PackedVector3Array=body.posed_points.duplicate()
	body.use_compute=true;body.set_angles(combined)
	var combined_actual:PackedVector3Array=body.read_gpu_points()
	for i in combined_actual.size():assert(combined_actual[i].distance_to(combined_reference[i])<.00001,"Mixed-axis rotation order mismatch")
	body.use_compute=true
	for amount in [.2,.5,.8,1.0]:
		body.set_test_pose("elbow",amount)
		for point:Vector3 in body.read_gpu_points():assert(point.is_finite())
	studio.regional_preview=null;body.free();studio.free();canvas.free();print("PASS rest/reset, rigid root, CPU/GPU parity, eight poses, chair and continuous joint range");quit()
