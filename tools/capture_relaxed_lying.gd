extends SceneTree
const Art=preload("res://scripts/asset/art_paths.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1000,650)
	var studio=preload("res://tools/character_skin_studio.gd").new()
	studio.interactive=false;root.add_child(studio);studio.show_new_base()
	var body:Node3D=studio.regional_preview
	var folder:String=Art.review_path("character_3d/lying_support_03")
	DirAccess.make_dir_recursive_absolute(folder)
	var results:Array=[]
	for pose in ["lie","lie_relaxed"]:
		for amount in [.25,.5,.75,1.0]:
			body.set_test_pose(pose,amount)
			var points:PackedVector3Array=body.posed_points.duplicate()
			var requested:Dictionary=body.angles_by_name.duplicate(true)
			body.use_compute=false;body.set_angles(requested)
			var error:=0.0
			for i in points.size():error=maxf(error,points[i].distance_to(body.posed_points[i]))
			assert(error<.00001,"Lying CPU/GPU surfaces disagree")
			body.use_compute=true;body.set_test_pose(pose,amount)
			for point:Vector3 in body.posed_points:assert(point.is_finite() and point.y+body.position.y>=-.00001)
			studio.update_pose_helpers()
			for view in ["side","above"]:
				studio.camera.size=2.4
				var center:=Vector3(0,.55,-.15) if amount<1 else Vector3(0,.25,-.15)
				studio.camera.position=center+(Vector3(4,.3,0) if view=="side" else Vector3(.4,4,.2))
				studio.camera.look_at(center)
				for frame in 3:await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/"+pose+"_"+str(int(amount*100))+"_"+view+".png")
			results.append({"pose":pose,"amount":amount,"cpu_gpu_error":error,"input_unchanged":body.angles_by_name==requested})
		# Final resting pose on a simple bed, and close-ups of actual support.
		# The preceding amplitude samples are joint checks, not a lying animation.
		var support:Dictionary={"pose":pose,"support":"floor / white bed"}
		for region:String in ["head","rHand","lHand"]:
			var minimum:=INF
			for node:Dictionary in body.nodes:
				var selected:bool=node.name==region
				if region.ends_with("Hand"):
					selected=node.name.begins_with(region.left(1)) and (node.name.contains("Hand") or node.name.contains("Index") or node.name.contains("Mid") or node.name.contains("Ring") or node.name.contains("Pinky") or node.name.contains("Thumb"))
				if not selected:continue
				for weight:Dictionary in node.weights:
					if weight.axis_weights.length_squared()<.75:continue
					minimum=minf(minimum,body.posed_points[weight.vertex].y+body.position.y)
			support[region+"_minimum_clearance_m"]=minimum
		if pose=="lie_relaxed":
			assert(support.head_minimum_clearance_m<.012,"Head is hovering above the support")
			assert(maxf(support.rHand_minimum_clearance_m,support.lHand_minimum_clearance_m)<.03,"Resting hands are too high")
			assert(absf(support.rHand_minimum_clearance_m-support.lHand_minimum_clearance_m)<.001,"Mirrored rest hands disagree")
			for side:String in ["r","l"]:
				var wrist:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(side+"Hand")).origin
				var middle:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(side+"Mid1")).origin
				var index:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(side+"Index1")).origin
				var pinky:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone(side+"Pinky1")).origin
				var palm:Vector3=(middle-wrist).cross(index-pinky).normalized()*(1 if side=="r" else -1)
				assert(palm.y>.9,"A resting palm is inverted or on its edge")
				support[side+"_palm_up_dot"]=palm.y
		results.append(support)
		var bounds:=AABB(body.posed_points[0]+body.position,Vector3.ZERO)
		for p:Vector3 in body.posed_points:bounds=bounds.expand(p+body.position)
		var bed:=MeshInstance3D.new();var box:=BoxMesh.new()
		box.size=Vector3(bounds.size.x+.22,.08,bounds.size.z+.25);bed.mesh=box
		var material:=StandardMaterial3D.new();material.albedo_color=Color(.78,.8,.82);material.roughness=.9;bed.material_override=material
		bed.position=Vector3(bounds.get_center().x,.38,bounds.get_center().z);studio.add_child(bed)
		body.position.y+=.42
		for view:String in ["bed_side","head","right_hand","left_hand"]:
			var center:Vector3=bounds.get_center()+Vector3.UP*.42
			var offset:=Vector3(4,.5,0)
			studio.camera.size=2.4
			if view!="bed_side":
				var bone:String={"head":"head","right_hand":"rHand","left_hand":"lHand"}[view]
				center=body.get_solved_bone_pose(body.skeleton.find_bone(bone)).origin+body.position
				offset=Vector3(.5,3,.4);studio.camera.size=.43
			studio.camera.position=center+offset;studio.camera.look_at(center)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+pose+"_"+view+".png")
		bed.free()
	var file:=FileAccess.open(folder+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"));file.close()
	studio.free()
	for frame in 4:await process_frame
	print("PASS lying pose numerical comparison; visual review still required")
	quit()
