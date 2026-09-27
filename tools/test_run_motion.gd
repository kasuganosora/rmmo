extends SceneTree
const Model=preload("res://scripts/char/character_model_3d.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var model:=Model.new();root.add_child(model);model.set_process(false);model.configure("female",{}, {})
	model.play("dash","front",true)
	var lo:=Vector3(INF,INF,INF);var hi:=-lo
	var contact_count:=0;var previous:Dictionary={};var start:Dictionary={}
	for i in range(181):
		model.pose_at(model.action_duration()*i/180.0)
		var poses:Dictionary={}
		for key in ["hips","head","handL","handR","footL","footR"]:
			poses[key]=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.bones[key]).origin
			assert(poses[key].is_finite())
			if previous.has(key):assert(poses[key].distance_to(previous[key])<.04,"Discontinuous run: "+key)
		if i==0:start=poses.duplicate()
		lo=lo.min(poses.head);hi=hi.max(poses.head)
		var torso:Vector3=poses.head-poses.hips
		assert(atan2(torso.z,torso.y)>deg_to_rad(12),"Run lost forward lean")
		assert(poses.handL.x<-.10 and poses.handR.x>.10,"Hands crossed the torso")
		var low_foot:float=INF
		for name in ["mixamorig_LeftToeBase","mixamorig_RightToeBase"]:
			var toe:Vector3=model.skeleton.global_transform*model.skeleton.get_bone_global_pose(model.skeleton.find_bone(name)).origin
			assert(toe.y>-.01,"Toe below ground")
			low_foot=minf(low_foot,toe.y)
		assert(low_foot<.07,"Excessive flight height")
		if low_foot<.012:contact_count+=1
		previous=poses
	assert(hi.y-lo.y<.06,"Run reintroduced head bobbing")
	assert(contact_count>120,"Not enough grounded support")
	for key in start:assert(start[key].distance_to(previous[key])<.001,"Loop seam: "+key)
	model.play("walk","front",true);model.elapsed=model.action_duration()*.37
	model.play("dash","front")
	assert(absf(model.elapsed/model.action_duration()-.37)<.0001,"Walk/run phase jump")
	model.play("walk","front")
	assert(absf(model.elapsed/model.action_duration()-.37)<.0001,"Run/walk phase jump")
	print("PASS run: head span=",hi.y-lo.y,", grounded samples=",contact_count,"/181; hand clearance, foot height, continuity, loop and gait transitions")
	model.free();quit()
