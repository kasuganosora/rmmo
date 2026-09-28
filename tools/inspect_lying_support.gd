extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var body=preload("res://scripts/char/female_axis_body.gd").new()
	root.add_child(body);body.initialize()
	for elbow_bend in [6.0,8.0,10.0,12.0,14.0]:
		var pose:Dictionary=body.POSES.lie_relaxed.duplicate(true)
		pose.rForeArm.y=elbow_bend;pose.lForeArm.y=-elbow_bend
		body.set_angles(pose)
		var bottom:=INF
		for point:Vector3 in body.posed_points:bottom=minf(bottom,point.y)
		var row:Dictionary={"elbow_bend":elbow_bend,"ground_offset":-bottom}
		for name in ["head","neck","rShldr","rForeArm","rHand","rMid1","rMid3"]:
			row[name]=body.get_solved_bone_pose(body.skeleton.find_bone(name)).origin.y-bottom
		var hand:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone("rHand")).origin
		var middle:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone("rMid1")).origin
		var index:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone("rIndex1")).origin
		var pinky:Vector3=body.get_solved_bone_pose(body.skeleton.find_bone("rPinky1")).origin
		row["palm_normal"]=(middle-hand).cross(index-pinky).normalized()
		for name:String in ["head","rHand","lHand"]:
			var minimum:=INF
			for node:Dictionary in body.nodes:
				if node.name!=name:continue
				for w:Dictionary in node.weights:
					if w.axis_weights.length_squared()>.75:minimum=minf(minimum,body.posed_points[w.vertex].y-bottom)
			row[name+"_minimum"]=minimum
		print(row)
	body.free();quit()
